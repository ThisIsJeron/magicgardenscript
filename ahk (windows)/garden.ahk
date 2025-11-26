; AutoHotkey v2 - Discord Garden Macro (Simplified)
; 
; This simplified macro assumes the "My Garden" button returns you to the last
; location (top tile of the 1x10 pathway between two 10x10 plots). Orientation
; detection and calibration are removed. Press Ctrl+D to run a full harvest of
; left plot then right plot using a serpentine traversal.

; ---------- Config ----------
useArrows := true
harvestRepeatsMin := 6
harvestRepeatsMax := 8
tGarden := 450           ; ms after Shift+2 (My Garden) — lowered for low ping
tShop := 500             ; ms after Shift+3 (UI open) — lowered for low ping
tAction := 120           ; ms per Space — faster harvest cadence
tMove := 40              ; ms per tile move — faster traversal
jitter := 5              ; +/- ms jitter — slightly reduced

startHotkey := "^d"      ; Ctrl+D to start a full run
abortHotkey := "^Esc"    ; Ctrl+Esc to stop

; ---------- State ----------
global running := false

movement := useArrows
  ? Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
; Optimize key send speed for low-latency environments
SetKeyDelay -1, 0
SendMode "Input"
RandDelay(ms) {
  global jitter
  return ms + Random(-jitter, jitter)
}

; Calibration and detection removed

SleepCancellable(ms) {
  global running
  remaining := RandDelay(ms)
  chunk := 20
  while (remaining > 0 && running) {
    thisSleep := remaining < chunk ? remaining : chunk
    Sleep thisSleep
    remaining -= thisSleep
  }
}

; Queue/timer helpers removed in simplified flow

; Timer queue removed

; ---------- Send helpers ----------
Press(mods, key) {
  Send(mods . key)
}

Stroke(key) {
  Send(key)
}

Move(dir, times := 1, perMove := 0) {
  global movement, tMove, running
  stepDelay := perMove ? perMove : tMove
  Loop times {
    if (!running) {
      return
    }
    Stroke(movement[dir])
    if (!running) {
      return
    }
    SleepCancellable(stepDelay)
  }
}

HarvestTile() {
  global harvestRepeatsMin, harvestRepeatsMax, tAction, running
  reps := Random(harvestRepeatsMin, harvestRepeatsMax)
  Loop reps {
    if (!running) {
      return
    }
    Stroke(" ")
    if (!running) {
      return
    }
    SleepCancellable(tAction)
  }
}

; ---------- App focus (not used; assume Discord is focused) ----------

EnterGarden() {
  Press("+", "2")
  SleepCancellable(tGarden)
}

SellAtShop() {
  Press("+", "3")
  SleepCancellable(tShop)
  Stroke(" ")
}

; Removed settled sell as tAction throttling mitigates latency sufficiently

; ---------- Traversal ----------
HarvestRow(dir) {
  global running
  Loop 10 {
    col := A_Index
    if (!running) {
      return
    }
    HarvestTile()
    if (col < 10) {
      Move(dir, 1)
    }
  }
}

TraversePlot(plotSide, startFromTop := true) {
  global running
  dir := (plotSide = "left") ? "left" : "right"
  enterStep := (plotSide = "left") ? "left" : "right"
  exitStep := (plotSide = "left") ? "right" : "left"
  vertStep := startFromTop ? "down" : "up"

  EnterGarden()
  if (!running) {
    return
  }
  Move(enterStep, 1)

  Loop 10 {
    row := A_Index
    if (!running) {
      return
    }
    HarvestRow(dir)
    if (!running) {
      return
    }
    SellAtShop()
    if (!running) {
      return
    }
    EnterGarden()
    if (!running) {
      return
    }
    if (row = 10) {
      Move(exitStep, 1)
      return
    }
    Move(vertStep, 1)
    dir := (dir = "right") ? "left" : "right"
  }
}

; ---------- Run logic ----------
RunAll(*) {
  global running
  if (running) {
    TrayTip("Farm macro", "Already running")
    return
  }
  running := true

  while (running) {
    TraversePlot("left", true)
    if (!running) {
      break
    }
    TraversePlot("right", false)
  }
}

AbortMacro(*) {
  global running
  running := false
  TrayTip("Farm macro", "Aborted")
}

; ---------- Hotkeys ----------
Hotkey(startHotkey, RunAll)
Hotkey(abortHotkey, AbortMacro)

TrayTip("Farm macro", "Loaded. Hotkeys: Start(^d), Abort(^Esc)")