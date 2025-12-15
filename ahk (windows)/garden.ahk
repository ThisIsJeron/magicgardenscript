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
tGarden := 650           ; ms after Shift+2 (My Garden) — increased for lag
tShop := 700             ; ms after Shift+3 (UI open) — increased for lag
tAction := 200           ; ms per Space — slower harvest cadence
tMove := 80              ; ms per tile move — slower traversal
jitter := 10             ; +/- ms jitter — widened for variability

; Input injection tuning (engine updates sometimes ignore SendInput)
; Try: "Event" -> "InputThenPlay" -> "Play" if inputs still get ignored
sendMode := "Event"      ; "Event" | "Input" | "Play" | "InputThenPlay"
keyDelay := 30           ; ms between keystrokes (was -1)
keyPressDuration := 10   ; ms key down time (was 0)
useScanCodes := true     ; send scancodes for movement/space (more compatible for some targets)

startHotkey := "^d"      ; Ctrl+D to start a full run
abortHotkey := "^Esc"    ; Ctrl+Esc to stop

; ---------- State ----------
global running := false

movement := useArrows
  ? (useScanCodes
    ? Map("left","{sc14B}","right","{sc14D}","up","{sc148}","down","{sc150}")
    : Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}"))
  : (useScanCodes
    ? Map("left","{sc01E}","right","{sc020}","up","{sc011}","down","{sc01F}")
    : Map("left","a","right","d","up","w","down","s"))

; ---------- Utils ----------
; Tune send behavior for compatibility with targets that filter injected input
SetKeyDelay keyDelay, keyPressDuration
SendMode sendMode
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
  global useScanCodes
  if (useScanCodes && (key = " " || key = "{Space}")) {
    Send("{sc039}")
    return
  }
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
    Stroke("{Space}")
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
  Stroke("{Space}")
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

EnterRow(plotSide, dir) {
  global running
  enterStep := (plotSide = "left") ? "left" : "right"
  Move(enterStep, 1)
  if (!running) {
    return
  }
  if (dir != enterStep) {
    Move(enterStep, 9)
    if (!running) {
      return
    }
  }
}

ExitRow(plotSide, dir) {
  global running
  exitStep := (plotSide = "left") ? "right" : "left"
  if (dir != exitStep) {
    Move(exitStep, 9)
    if (!running) {
      return
    }
  }
  Move(exitStep, 1)
  if (!running) {
    return
  }
}

TraversePlot(plotSide, startFromTop := true) {
  global running
  dir := (plotSide = "left") ? "left" : "right"
  vertStep := startFromTop ? "down" : "up"
  resetStep := startFromTop ? "up" : "down"

  EnterGarden()
  if (!running) {
    return
  }
  Move(resetStep, 9) ; snap to walkway extreme
  if (!running) {
    return
  }

  Loop 10 {
    row := A_Index
    if (!running) {
      return
    }
    EnterRow(plotSide, dir)
    if (!running) {
      return
    }
    HarvestRow(dir)
    if (!running) {
      return
    }
    ExitRow(plotSide, dir)
    if (!running) {
      return
    }
    SellAtShop()
    if (!running) {
      return
    }
    if (row = 10) {
      break
    }
    Move(vertStep, 1) ; advance walkway to next row anchor
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

TrayTip("Farm macro", "Loaded. Hotkeys: Start(^d), Abort(^Esc) | SendMode: " . sendMode . " | Scancodes: " . (useScanCodes ? "on" : "off"))