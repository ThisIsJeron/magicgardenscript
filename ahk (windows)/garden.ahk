; AutoHotkey v2 - Discord Garden Macro (Optimized + Crash Recovery)
#Requires AutoHotkey v2.0
;
; Harvests two 10×10 plots separated by a 1×10 walkway.  Serpentine traversal
; with configurable batch-sell.  Auto-detects activity crashes via pixel check
; and rejoins by clicking the "Join Activity" button.
;
; Shift+S → start    Shift+P → pause/resume    Shift+C → calibrate    Ctrl+Esc → abort

; ════════════════════════ Config ════════════════════════

; ── Harvest ──
harvestHoldMs    := 1000      ; long-press hold for mutated fruit
harvestTapsMin   := 6         ; min rapid-tap count (normal fruit)
harvestTapsMax   := 8         ; max rapid-tap count
holdMsSpace      := 160       ; hold time per space tap
tAction          := 200       ; pause between taps

; ── Movement ──
useArrows        := true
holdMsMove       := 220       ; hold time per directional key press
pauseMs          := 250       ; base pause between any keystrokes

; ── Chords  (Shift+2  /  Shift+3) ──
holdMsChord      := 350       ; how long the key+modifier combo is held
chordPreGap      := 30        ; ms between modifier-down and key-down
;   The original script held the modifier 350 ms *before* the key as well.
;   30 ms is usually enough for the OS to register the modifier.  Bump this
;   if Shift+2 / Shift+3 miss.

; ── Shop / Garden UI ──
tGarden          := 650       ; wait after Shift+2  (My Garden)
tShop            := 700       ; wait after Shift+3  (open shop)
sellPresses      := 1         ; space presses to confirm sell
;   Increase sellPresses if a bigger batch requires multiple confirmations.

; ── Batch selling ──
;   Harvest this many rows before opening the shop.  Higher = faster but needs
;   enough inventory space.  Set to 1 for the original per-row behaviour.
rowsPerSell      := 1

; ── Anti-detection ──
jitterMs         := 30        ; ± ms random jitter on every timed sleep
microPauseChance := 8         ; % chance of a short idle between rows  (0-100)
microPauseMinMs  := 400       ; micro-pause duration low bound
microPauseMaxMs  := 1200      ; micro-pause duration high bound

; ── Crash recovery ──
;   Detects activity crashes via pixel color check and auto-rejoins.
;   Run calibration (Shift+C) once to set up detection + rejoin coordinates.
crashCheckEnabled    := true      ; master toggle for crash detection
crashPixelTolerance  := 30        ; per-channel (R/G/B) color tolerance  (0-255)
activityLoadDelay    := 8000      ; ms to wait after clicking "Join Activity"
maxRecoveryRetries   := 3         ; rejoin attempts before aborting

; ── Input engine ──
;   Try: "Event" → "InputThenPlay" → "Play" if inputs still get ignored.
sendModeName     := "Event"
keyDelay         := 30
keyPressDuration := 20
useScanCodes     := true

; ── Hotkeys ──
startHotkey      := "+s"      ; Shift+S
pauseHotkey      := "+p"      ; Shift+P
abortHotkey      := "^Esc"    ; Ctrl+Esc
calibrateHotkey  := "+c"      ; Shift+C

; ════════════════════════ State ════════════════════════

global running   := false
global paused    := false
global cycleNum  := 0
global totalRows := 0

; Calibration state (loaded from INI or set via Shift+C)
global calibrated      := false
global crashPixelX     := 0      ; window-relative X of detection pixel
global crashPixelY     := 0      ; window-relative Y of detection pixel
global crashPixelColor := ""     ; expected color string  (e.g. "0xFF00AA")
global rejoinHoverX    := 0      ; window-relative X — voice channel hover
global rejoinHoverY    := 0      ; window-relative Y — voice channel hover
global rejoinClickX    := 0      ; window-relative X — "Join Activity" button
global rejoinClickY    := 0      ; window-relative Y — "Join Activity" button

; ════════════════════════ Init ════════════════════════

A_SendMode    := sendModeName
A_KeyDelay    := keyDelay
A_KeyDuration := keyPressDuration

movement := useArrows
  ? Map("left","left","right","right","up","up","down","down")
  : Map("left","a","right","d","up","w","down","s")

; Scancode lookup — built once instead of per-call
scodes := Map(
  "space","sc039",
  "left","sc14B",  "right","sc14D",
  "up","sc148",    "down","sc150",
  "w","sc011",     "a","sc01E",
  "s","sc01F",     "d","sc020"
)

; ── Load calibration from INI ──
iniPath := A_ScriptDir . "\garden_calibration.ini"
if FileExist(iniPath) {
  crashPixelX     := Integer(IniRead(iniPath, "Detection", "PixelX", "0"))
  crashPixelY     := Integer(IniRead(iniPath, "Detection", "PixelY", "0"))
  crashPixelColor := IniRead(iniPath, "Detection", "PixelColor", "")
  rejoinHoverX    := Integer(IniRead(iniPath, "Rejoin", "HoverX", "0"))
  rejoinHoverY    := Integer(IniRead(iniPath, "Rejoin", "HoverY", "0"))
  rejoinClickX    := Integer(IniRead(iniPath, "Rejoin", "ClickX", "0"))
  rejoinClickY    := Integer(IniRead(iniPath, "Rejoin", "ClickY", "0"))
  calibrated := (crashPixelColor != "")
}

; ════════════════════════ Utilities ════════════════════════

Jitter(ms) {
  return ms + Random(-jitterMs, jitterMs)
}

SleepJ(ms) {
  ; Cancellable, pause-aware, jittered sleep
  global running, paused
  remaining := Jitter(ms)
  while (remaining > 0 && running) {
    while (paused && running)
      Sleep 50
    chunk := Min(remaining, 20)
    Sleep chunk
    remaining -= chunk
  }
}

MaybeMicroPause() {
  global running
  if (Random(1, 100) <= microPauseChance && running)
    SleepJ(Random(microPauseMinMs, microPauseMaxMs))
}

GetDiscordHwnd() {
  hwnd := WinExist("ahk_exe Discord.exe")
  if !hwnd
    hwnd := WinExist("Discord")
  return hwnd
}

; ════════════════════════ Crash detection ════════════════════════

ColorsMatch(expected, actual, tolerance) {
  eN := Integer(expected)
  aN := Integer(actual)
  return (Abs(((eN >> 16) & 0xFF) - ((aN >> 16) & 0xFF)) <= tolerance)
      && (Abs(((eN >>  8) & 0xFF) - ((aN >>  8) & 0xFF)) <= tolerance)
      && (Abs( (eN        & 0xFF) -  (aN        & 0xFF)) <= tolerance)
}

IsGameAlive() {
  global calibrated, crashCheckEnabled
  global crashPixelX, crashPixelY, crashPixelColor, crashPixelTolerance
  if !crashCheckEnabled || !calibrated
    return true                    ; can't check — assume alive
  hwnd := GetDiscordHwnd()
  if !hwnd
    return false                   ; Discord itself is gone
  WinGetPos(&wx, &wy, , , hwnd)
  try
    current := PixelGetColor(wx + crashPixelX, wy + crashPixelY)
  catch
    return true                    ; pixel off-screen or error — assume alive
  return ColorsMatch(crashPixelColor, current, crashPixelTolerance)
}

RecoverFromCrash() {
  global running, activityLoadDelay, maxRecoveryRetries
  global rejoinHoverX, rejoinHoverY, rejoinClickX, rejoinClickY

  TrayTip("Farm macro", "Activity crash detected — attempting recovery")

  ; Clean up accidental chat input first:
  ; Esc dismisses autocomplete menus, Ctrl+A selects any typed text, Delete clears it
  Send("{Esc}")
  Sleep 100
  Send("{Esc}")
  Sleep 100
  Send("^a")
  Sleep 50
  Send("{Delete}")
  Sleep 100

  Loop maxRecoveryRetries {
    attempt := A_Index
    if !running
      return false

    hwnd := GetDiscordHwnd()
    if !hwnd {
      TrayTip("Farm macro", "Discord not found — aborting recovery")
      return false
    }
    WinGetPos(&wx, &wy, , , hwnd)
    try WinActivate(hwnd)
    Sleep 300

    ; Hover over the voice channel to trigger the overlay
    MouseMove(wx + rejoinHoverX, wy + rejoinHoverY)
    Sleep 600

    ; Click "Join Activity"
    MouseMove(wx + rejoinClickX, wy + rejoinClickY)
    Sleep 200
    Click

    ; Wait for the activity to finish loading
    Sleep activityLoadDelay
    if !running
      return false

    ; Verify we're back in the game
    if IsGameAlive() {
      TrayTip("Farm macro", "Recovery successful — resuming from walkway")
      EnterGarden()
      return true
    }

    TrayTip("Farm macro",
      "Recovery attempt " . attempt . "/" . maxRecoveryRetries . " failed")
    Sleep 2000
  }

  TrayTip("Farm macro",
    "Recovery failed after " . maxRecoveryRetries . " attempts — aborting")
  return false
}

; ════════════════════════ Calibration ════════════════════════

WaitForCalibKey(&outX, &outY) {
  ; InputHook installs its own low-level hook, so it works regardless of
  ; hotkey registrations, focused window, or SendMode settings.
  ih := InputHook("L0")           ; don't collect text, just watch keys
  ih.KeyOpt("v", "E")             ; end the hook when V is pressed (key-down)
  ih.Start()
  ih.Wait()                        ; blocks until V key-down
  MouseGetPos(&outX, &outY)       ; grab position at the moment of press
  Sleep 200                        ; debounce before next step
}

CalibrateMode(*) {
  global running, calibrated
  global crashPixelX, crashPixelY, crashPixelColor
  global rejoinHoverX, rejoinHoverY, rejoinClickX, rejoinClickY

  if running {
    TrayTip("Calibration", "Stop the macro first (Ctrl+Esc)")
    return
  }

  hwnd := GetDiscordHwnd()
  if !hwnd {
    MsgBox("Discord window not found.", "Calibration Error")
    return
  }
  WinGetPos(&wx, &wy, , , hwnd)

  MsgBox(
    "Calibration will capture 3 mouse positions.`n`n"
    . "After clicking OK, a tooltip will tell you what to do.`n"
    . "Position your mouse and press V for each step.",
    "Calibration")

  ; ── Step 1: game pixel ──
  ToolTip("Step 1/3: Move mouse over a GAME-ONLY pixel, then press V")
  WaitForCalibKey(&mx, &my)
  crashPixelX     := mx - wx
  crashPixelY     := my - wy
  crashPixelColor := PixelGetColor(mx, my)
  ToolTip()

  ; ── Step 2: voice-channel hover position ──
  ToolTip("Step 2/3: Move mouse over the voice channel, then press V")
  WaitForCalibKey(&mx, &my)
  rejoinHoverX := mx - wx
  rejoinHoverY := my - wy
  ToolTip()

  ; ── Step 3: "Join Activity" button ──
  ToolTip("Step 3/3: Hover channel so 'Join Activity' appears, move to the button, press V")
  WaitForCalibKey(&mx, &my)
  rejoinClickX := mx - wx
  rejoinClickY := my - wy
  ToolTip()

  ; ── Save to INI ──
  IniWrite(crashPixelX,     iniPath, "Detection", "PixelX")
  IniWrite(crashPixelY,     iniPath, "Detection", "PixelY")
  IniWrite(crashPixelColor, iniPath, "Detection", "PixelColor")
  IniWrite(rejoinHoverX,    iniPath, "Rejoin",    "HoverX")
  IniWrite(rejoinHoverY,    iniPath, "Rejoin",    "HoverY")
  IniWrite(rejoinClickX,    iniPath, "Rejoin",    "ClickX")
  IniWrite(rejoinClickY,    iniPath, "Rejoin",    "ClickY")

  calibrated := true
  MsgBox(
    "Calibration saved to garden_calibration.ini`n`n"
    . "Game pixel: (" . crashPixelX . ", " . crashPixelY . ") color=" . crashPixelColor . "`n"
    . "Hover pos:  (" . rejoinHoverX . ", " . rejoinHoverY . ")`n"
    . "Button pos: (" . rejoinClickX . ", " . rejoinClickY . ")",
    "Calibration Complete")
}

; ════════════════════════ Send helpers ════════════════════════

PressHold(key, holdMs) {
  k := StrLower(key)
  if (useScanCodes && scodes.Has(k)) {
    sc := scodes[k]
    Send("{" . sc . " down}")
    Sleep holdMs
    Send("{" . sc . " up}")
    return
  }
  wrap := (k ~= "^(left|right|up|down|space)$")
    ? "{" . (k = "space" ? "Space" : k) . "}"
    : key
  Send(wrap . " down")
  Sleep holdMs
  Send(wrap . " up")
}

PressChord(modifier, key, holdMs := 0) {
  dur := holdMs ? holdMs : holdMsChord
  Send("{" . modifier . " down}")
  Sleep chordPreGap              ; just enough for the modifier to register
  Send(key)
  Sleep dur                      ; hold the combo so the game reads it
  Send("{" . modifier . " up}")
}

Move(dir, times := 1, perMoveHold := 0) {
  global running
  hold := perMoveHold ? perMoveHold : holdMsMove
  Loop times {
    if !running
      return
    PressHold(movement[dir], hold)
    if !running
      return
    SleepJ(pauseMs)
  }
}

; ════════════════════════ Harvest ════════════════════════

HarvestTile() {
  global running
  if !running
    return
  ; Mutated fruit: long press
  PressHold("space", harvestHoldMs)
  if !running
    return
  Send("{Esc}")                  ; dismiss dialog if it appeared
  ; Normal fruit: rapid taps
  reps := Random(harvestTapsMin, harvestTapsMax)
  Loop reps {
    if !running
      return
    PressHold("space", holdMsSpace)
    if !running
      return
    SleepJ(tAction)
  }
}

HarvestRow(dir) {
  global running
  Loop 10 {
    if !running
      return
    ; Per-tile crash check — catch a dead activity before typing into chat
    if !IsGameAlive()
      return
    HarvestTile()
    if (A_Index < 10)
      Move(dir, 1)
  }
}

; ════════════════════════ Shop / Garden ════════════════════════

SellAtShop() {
  PressChord("Shift", "3")
  SleepJ(tShop)
  Loop sellPresses {
    PressHold("space", holdMsSpace)
    SleepJ(pauseMs)
  }
}

EnterGarden() {
  PressChord("Shift", "2")
  SleepJ(tGarden)
}

; ════════════════════════ Traversal ════════════════════════

; Returns true  = plot completed normally (or user aborted — check `running`)
; Returns false = crash detected & recovered — caller should restart the cycle
TraversePlot(plotSide, startFromTop := true) {
  global running, totalRows
  intoPlot      := (plotSide = "left") ? "left" : "right"
  dir           := intoPlot            ; first row sweeps away from walkway
  vertStep      := startFromTop ? "down" : "up"
  rowsSinceSell := 0

  ; Step from walkway into the plot for the first row
  Move(intoPlot, 1)
  if !running
    return true

  Loop 10 {
    row := A_Index
    if !running
      return true

    ; ── Harvest the row ──
    HarvestRow(dir)
    if !running
      return true

    ; ── Crash check (before sell to avoid typing @/# into Discord chat) ──
    if !IsGameAlive() {
      if RecoverFromCrash()
        return false             ; recovered — signal RunAll to restart cycle
      running := false           ; unrecoverable
      return true
    }

    rowsSinceSell++
    totalRows++

    ; ── Sell when batch is full or plot is done ──
    doSell := (rowsSinceSell >= rowsPerSell) || (row = 10)
    if doSell {
      SellAtShop()
      if !running
        return true
      EnterGarden()              ; returns to the tile we left from
      if !running
        return true
      rowsSinceSell := 0
      ShowProgress()
    }

    if (row = 10)
      break

    ; ── Advance to next row ──
    Move(vertStep, 1)
    if !running
      return true

    dir := (dir = "right") ? "left" : "right"

    MaybeMicroPause()
  }
  return true
}

; ════════════════════════ Progress ════════════════════════

ShowProgress() {
  global cycleNum, totalRows
  TrayTip("Farm macro",
    "Cycle " . cycleNum
    . "  |  Rows: " . totalRows
    . "  |  Tiles: ~" . (totalRows * 10))
}

; ════════════════════════ Main loop ════════════════════════

RunAll(*) {
  global running, paused, cycleNum, totalRows
  if running {
    TrayTip("Farm macro", "Already running")
    return
  }
  running   := true
  paused    := false
  cycleNum  := 0
  totalRows := 0

  ; Auto-focus Discord if it isn't already active
  if !WinActive("ahk_exe Discord.exe") && !WinActive("Discord") {
    TrayTip("Farm macro", "Discord not in focus — activating")
    try WinActivate("Discord")
    Sleep 500
  }

  EnterGarden()                    ; land at top of walkway
  if !running
    return

  while running {
    cycleNum++
    ShowProgress()

    ; ── Left plot: top → bottom ──
    if !TraversePlot("left", true) {
      if running
        continue                 ; crash recovered — restart cycle from walkway
      break
    }
    if !running
      break

    ; After row 10 (even), last sweep headed toward the walkway,
    ; so we are one step into the left plot at the bottom.
    Move("right", 1)               ; step onto walkway (bottom)
    if !running
      break

    ; ── Right plot: bottom → top ──
    if !TraversePlot("right", false) {
      if running
        continue                 ; crash recovered — restart cycle from walkway
      break
    }
    if !running
      break

    ; After row 10 (even), last sweep headed toward the walkway,
    ; so we are one step into the right plot at the top.
    Move("left", 1)                ; step onto walkway (top) — ready for next cycle
    if !running
      break
  }
}

; ════════════════════════ Controls ════════════════════════

AbortMacro(*) {
  global running, paused
  running := false
  paused  := false
  TrayTip("Farm macro",
    "Aborted  |  Rows: " . totalRows . "  Tiles: ~" . (totalRows * 10))
}

TogglePause(*) {
  global paused, running
  if !running
    return
  paused := !paused
  TrayTip("Farm macro", paused ? "Paused" : "Resumed")
}

; ════════════════════════ Hotkeys ════════════════════════

Hotkey(startHotkey, RunAll)
Hotkey(abortHotkey, AbortMacro)
Hotkey(pauseHotkey, TogglePause)
Hotkey(calibrateHotkey, CalibrateMode)

recoveryStatus := calibrated
  ? "Crash recovery: ON"
  : "Crash recovery: OFF (run Shift+C to calibrate)"

TrayTip("Farm macro",
  "Ready  |  Start: Shift+S   Pause: Shift+P   Calibrate: Shift+C   Abort: Ctrl+Esc"
  . "`nSendMode: " . sendModeName
  . "  Scancodes: " . (useScanCodes ? "on" : "off")
  . "  Batch: " . rowsPerSell . " rows/sell"
  . "`n" . recoveryStatus)
