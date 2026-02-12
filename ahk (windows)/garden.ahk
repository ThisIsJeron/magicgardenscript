; AutoHotkey v2 - Discord Garden Macro (Optimized)
#Requires AutoHotkey v2.0
;
; Harvests two 10×10 plots separated by a 1×10 walkway.  Serpentine traversal
; with configurable batch-sell: harvest N rows before visiting the shop, cutting
; sell/return overhead by up to 80%.
;
; Shift+S  → start        Shift+P  → pause / resume        Ctrl+Esc → abort

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

; ════════════════════════ State ════════════════════════

global running   := false
global paused    := false
global cycleNum  := 0
global totalRows := 0

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

TraversePlot(plotSide, startFromTop := true) {
  global running, totalRows
  intoPlot      := (plotSide = "left") ? "left" : "right"
  dir           := intoPlot            ; first row sweeps away from walkway
  vertStep      := startFromTop ? "down" : "up"
  rowsSinceSell := 0

  ; Step from walkway into the plot for the first row
  Move(intoPlot, 1)
  if !running
    return

  Loop 10 {
    row := A_Index
    if !running
      return

    ; ── Harvest the row ──
    HarvestRow(dir)
    if !running
      return

    rowsSinceSell++
    totalRows++

    ; ── Sell when batch is full or plot is done ──
    doSell := (rowsSinceSell >= rowsPerSell) || (row = 10)
    if doSell {
      SellAtShop()
      if !running
        return
      EnterGarden()              ; returns to the tile we left from
      if !running
        return
      rowsSinceSell := 0
      ShowProgress()
    }

    if (row = 10)
      break

    ; ── Advance to next row ──
    Move(vertStep, 1)
    if !running
      return

    dir := (dir = "right") ? "left" : "right"

    MaybeMicroPause()
  }
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
    TraversePlot("left", true)
    if !running
      break

    ; After row 10 (even), last sweep headed toward the walkway,
    ; so we are one step into the left plot at the bottom.
    Move("right", 1)               ; step onto walkway (bottom)
    if !running
      break

    ; ── Right plot: bottom → top ──
    TraversePlot("right", false)
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

TrayTip("Farm macro",
  "Ready  |  Start: Shift+S   Pause: Shift+P   Abort: Ctrl+Esc"
  . "`nSendMode: " . sendModeName
  . "  Scancodes: " . (useScanCodes ? "on" : "off")
  . "  Batch: " . rowsPerSell . " rows/sell")
