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
  Loop times {
    if (!running) {
      return
    }
    Stroke(movement[dir])
    if (!running) {
      return
    }
    SleepCancellable(perMove || tMove)
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

; ---------- Traversal (deterministic re-anchoring per row) ----------
Traverse10x10(startDir, vStep := "down") {
  global running
  ; Determine which way to enter the plot from the walkway each row
  enterDir := (startDir = "left") ? "left" : "right"
  Loop 10 {
    row := A_Index
    if (!running) {
      return
    }
    ; From walkway row position, step into the plot edge for this row
    Move(enterDir, 1)

    ; Harvest across the row in a fixed direction to avoid drift
    Loop 10 {
      col := A_Index
      if (!running) {
        return
      }
      HarvestTile()
      if (col < 10) {
        Move(startDir, 1)
      }
    }

    ; Sell and re-anchor back to walkway's top tile
    SellAtShop()
    EnterGarden()

    ; Advance along the walkway to align with the next row deterministically
    if (row < 10) {
      Move(vStep, row) ; move down the walkway by the current row index
    }
  }
}

; Plot-specific helpers removed; we traverse directly in RunAll

; ---------- Run logic ----------
RunAll(*) {
  global running
  if (running) {
    TrayTip("Farm macro", "Already running")
    return
  }
  running := true

  while (running) {
    ; Ensure we are at the top of the pathway via My Garden
    EnterGarden()

    ; Left plot: enter from walkway to the right edge, harvest leftwards each row
    Traverse10x10("left", "down")

    ; Re-anchor, then Right plot: enter from walkway to the left edge, harvest rightwards
    EnterGarden()
    Traverse10x10("right", "down")

    ; Final sell at end of both plots
    SellAtShop()
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