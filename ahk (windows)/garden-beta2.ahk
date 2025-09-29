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
tGarden := 600           ; ms after Shift+2 (My Garden)
tShop := 700             ; ms after Shift+3 (UI open)
tAction := 250           ; ms per Space (throttle harvest rate)
tMove := 80              ; ms per tile move
jitter := 10             ; +/- ms jitter

startHotkey := "^d"      ; Ctrl+D to start a full run

; ---------- State ----------
global running := false

movement := useArrows
  ? Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
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

; ---------- Traversal ----------
Traverse10x10(startDir, vStep := "down") {
  global running
  dir := startDir
  Loop 10 {
    row := A_Index
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
    ; Sell after each row and return to the same tile via My Garden
    SellAtShop()
    EnterGarden()
    if (row < 10) {
      Move(vStep, 1)
      dir := (dir = "right") ? "left" : "right"
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

  ; Ensure we are at the top of the pathway via My Garden
  EnterGarden()

  ; Traverse left plot from top-right corner, going left first, then snake down
  Move("left", 1)
  Traverse10x10("left", "down")

  ; Return to pathway top, then traverse right plot from top-left corner
  EnterGarden()
  Move("right", 1)
  Traverse10x10("right", "down")

  ; Final sell
  SellAtShop()

  running := false
  TrayTip("Farm macro", "Finished")
}

; ---------- Hotkeys ----------
Hotkey(startHotkey, RunAll)

TrayTip("Farm macro", "Loaded. Hotkey: Start(^d)")