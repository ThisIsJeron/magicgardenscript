require('hs.ipc')

local cfg = {
  useArrows = true,       -- true: Arrow keys; false: WASD
  harvestRepeatsMin = 4,  -- min Space presses per tile
  harvestRepeatsMax = 6,  -- max Space presses per tile
  tGarden = 0.90,         -- delay after Shift+2
  tShop = 0.70,           -- delay after Shift+3
  tAction = 0.12,         -- per Space press (slower)
  tMove = 0.12,           -- per tile move (slower)
  jitter = 0.03,          -- +/- jitter for human-like timing
  autoLoop = true,        -- run continuously
  loopDelay = 120,        -- seconds to wait between runs (2 minutes)
  sellEveryRows = 2,      -- sell after N rows (0 to disable)
  entryAtTop = true,      -- true: Shift+2 drops at top; false: bottom
  gardenFacingDown = true,-- true: garden UI faces down (default), false: faces up
  hotkeyStart = { {'ctrl','alt','cmd'}, 'g' },
  hotkeyStartDown = { {'ctrl'}, 'd' }, -- start with facing down
  hotkeyStartUp = { {'ctrl'}, 'u' },   -- start with facing up
  hotkeyAbort = { {'ctrl'}, 'escape' },
}

local running = false
local farmMenu = hs.menubar.new()
local actionQueue = {}
local currentTimer = nil
-- Forward declarations for locals referenced before definition
local runAll
local enqueueSellAtShop
local enqueueEnterGarden
local previousApp = nil

local function updateMenu()
  if not farmMenu then return end
  if running then
    farmMenu:setTitle("🌾")
    farmMenu:setMenu({
      { title = "Stop Macro", fn = function()
          running = false
          hs.alert.show("Stopping farm macro")
          -- menu will update once runAll completes
        end
      },
    })
  else
    farmMenu:setTitle("🌱")
    farmMenu:setMenu({
      { title = "Start Macro", fn = function()
          if not running then
            hs.alert.show("Starting farm macro")
            runAll()
          end
        end
      },
    })
  end
end
local function jitter(s) return s + ((math.random()*2 - 1) * cfg.jitter) end
local function stroke(mods, key)
  if running then hs.eventtap.keyStroke(mods or {}, key, 0) end
end

local movement = cfg.useArrows
  and { left='left', right='right', up='up', down='down' }
  or  { left='a',    right='d',     up='w',  down='s'   }

local function enqueue(fn, delaySeconds)
  table.insert(actionQueue, { fn = fn, delay = delaySeconds or 0 })
end 
                  
local function scheduleNext()
  if not running then
    actionQueue = {}
    if currentTimer then currentTimer:stop() end
    currentTimer = nil
    return          
  end      
  local nextAction = table.remove(actionQueue, 1)
  if not nextAction then
    -- done
    running = false
    updateMenu()
    if cfg.autoLoop then
      hs.alert.show("Waiting " .. math.floor(cfg.loopDelay/60) .. "m, will run again")
      pcall(function()
        local discordApp = hs.application.find("Discord")
        if previousApp and discordApp and previousApp:bundleID() ~= discordApp:bundleID() then
          previousApp:activate()
        elseif previousApp and not discordApp then
          previousApp:activate()
        end
      end)
      currentTimer = hs.timer.doAfter(cfg.loopDelay, function() runAll() end)
    else
      hs.alert.show("Farm macro finished")
    end
    return
  end
  local function step()
    if not running then return end
    pcall(nextAction.fn)
    scheduleNext()
  end
  local delay = jitter(nextAction.delay or 0)
  if delay <= 0 then
    step()
  else
    currentTimer = hs.timer.doAfter(delay, step)
  end
end

local function enqueueMove(dir, times, perMoveDelay)
  local n = times or 1
  for i = 1, n do
    enqueue(function() stroke({}, movement[dir]) end, perMoveDelay or cfg.tMove)
  end
end

local function enqueueHarvestTile()
  local repeats = math.random(cfg.harvestRepeatsMin, cfg.harvestRepeatsMax)
  for i = 1, repeats do
    enqueue(function() stroke({}, 'space') end, cfg.tAction)
  end
end

local function enqueueTraverse10x10(startDir, sellEveryRows, afterRowsCallback, vStep)
  local dir = startDir or 'right'
  local sellEvery = sellEveryRows or 0
  local vstep = vStep or 'down'
  for row = 1, 10 do
    for col = 1, 10 do
      enqueueHarvestTile()
      if col < 10 then enqueueMove(dir, 1) end
    end
    if row < 10 then
      enqueueMove(vstep, 1)
      dir = (dir == 'right') and 'left' or 'right'
    end
    if sellEvery > 0 and (row % sellEvery == 0) and row < 10 then
      -- Sell, then resume at next row maintaining direction
      enqueueSellAtShop()
      if afterRowsCallback then afterRowsCallback(row + 0, dir) end
    end
  end
end

local function enqueueFocusDiscord()
  enqueue(function() hs.application.launchOrFocus("Discord") end, 0.25)
end
function enqueueEnterGarden()
  enqueue(function() stroke({'shift'}, '2') end, cfg.tGarden)
end
function enqueueSellAtShop()
  enqueue(function() stroke({'shift'}, '3') end, cfg.tShop)
  enqueue(function() stroke({}, 'space') end, 0.05)
end

function runAll(facingDown)
  if running then return end
  running = true
  math.randomseed(os.time())
  updateMenu()

  actionQueue = {}
  previousApp = hs.application.frontmostApplication()

  enqueueFocusDiscord()

  -- Determine vertical step based on entry position and facing
  local gardenFacesDown = cfg.gardenFacingDown
  if type(facingDown) == 'boolean' then
    gardenFacesDown = facingDown
  end
  local vStep
  if gardenFacesDown then
    vStep = cfg.entryAtTop and 'down' or 'up'
  else
    vStep = cfg.entryAtTop and 'up' or 'down'
  end

  -- Left plot: start at upper-right corner, go leftwards first
  enqueueEnterGarden()
  enqueueMove(vStep, 1)
  enqueueMove('left', 1)
  -- We are on upper-right corner of left plot, so first row direction is left
  enqueueTraverse10x10('left', cfg.sellEveryRows, function(resumeRow, dir)
    -- After selling, re-enter garden and navigate back to next row start
    enqueueEnterGarden()
    enqueueMove(vStep, 1)
    enqueueMove('left', 1)
    -- Move down resumeRow rows already completed to the next row start
    enqueueMove(vStep, resumeRow)
    -- We are anchored on the right edge; for next row direction:
    -- if dir == 'left', start at rightmost (already here). If dir == 'right', move to leftmost.
    if dir == 'right' then
      enqueueMove('left', 9)
    end
  end)

  -- Sell before switching plots to clear inventory
  enqueueSellAtShop()

  -- Right plot (re-center via garden entry)
  enqueueEnterGarden()
  enqueueMove(vStep, 1)
  enqueueMove('right', 1)
  -- We are on upper-left corner of right plot, so first row direction is right
  enqueueTraverse10x10('right', cfg.sellEveryRows, function(resumeRow, dir)
    enqueueEnterGarden()
    enqueueMove(vStep, 1)
    enqueueMove('right', 1)
    enqueueMove(vStep, resumeRow)
    -- We are anchored on the left edge; for next row direction:
    -- if dir == 'right', start at leftmost (already here). If dir == 'left', move to rightmost.
    if dir == 'left' then
      enqueueMove('right', 9)
    end
  end)

  -- Sell
  enqueueSellAtShop()

  scheduleNext()
end

hs.hotkey.bind(cfg.hotkeyAbort[1], cfg.hotkeyAbort[2], function()
  -- Abort regardless of current running state (also cancels auto-loop timer)
  if currentTimer then currentTimer:stop() end
  currentTimer = nil
  actionQueue = {}
  running = false
  updateMenu()
  hs.alert.show("Farm macro aborted")
end)

hs.hotkey.bind(cfg.hotkeyStart[1], cfg.hotkeyStart[2], function()
  if running then
    hs.alert.show("Already running")
  else
    hs.alert.show("Starting farm macro")
    runAll()
  end
end)

-- Start macros with explicit facing direction
hs.hotkey.bind(cfg.hotkeyStartDown[1], cfg.hotkeyStartDown[2], function()
  if running then
    hs.alert.show("Already running")
  else
    hs.alert.show("Starting farm macro (facing down)")
    runAll(true)
  end
end)

hs.hotkey.bind(cfg.hotkeyStartUp[1], cfg.hotkeyStartUp[2], function()
  if running then
    hs.alert.show("Already running")
  else
    hs.alert.show("Starting farm macro (facing up)")
    runAll(false)
  end
end)

hs.alert.show("Farm macro loaded")
updateMenu()

