; AutoHotkey v2 - Discord Garden Macro (Simplified)
#Requires AutoHotkey v2.0
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
jitter := 10             ; +/- ms jitter — widened for variability
holdMsSpace := 160       ; hold time for space taps
harvestHoldMs := 1000    ; exact hold time per harvest tile
holdMsMove := 220        ; hold time for movement keys
pauseBetweenStrokes := 250 ; pause after each key action
holdMsChord := 350       ; hold time for modifier chords (e.g., Shift+2)

; Input injection tuning (engine updates sometimes ignore SendInput)
; Try: "Event" -> "InputThenPlay" -> "Play" if inputs still get ignored
sendModeName := "Event"  ; "Event" | "Input" | "Play" | "InputThenPlay"
keyDelay := 30           ; ms between keystrokes (was -1)
keyPressDuration := 20   ; ms key down time (was 0)
useScanCodes := true     ; send scancodes for movement/space (more compatible for some targets)

startHotkey := "+s"      ; Shift+S to start a full run
abortHotkey := "^Esc"    ; Ctrl+Esc to stop

; ---------- State ----------
global running := false

movement := useArrows
  ? Map("left","left","right","right","up","up","down","down")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
; Tune send behavior for compatibility with targets that filter injected input
A_SendMode := sendModeName
A_KeyDelay := keyDelay
A_KeyDuration := keyPressDuration
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

PressChord(mod, key, holdMs := 0) {
  global holdMsChord
  dur := holdMs ? holdMs : holdMsChord
  Send("{" . mod . " down}")
  Sleep dur
  Send(key)
  Sleep dur
  Send("{" . mod . " up}")
}

PressHold(key, holdMs) {
  global useScanCodes
  scodes := Map(
    "space", "sc039",
    "left",  "sc14B",
    "right", "sc14D",
    "up",    "sc148",
    "down",  "sc150",
    "w",     "sc011",
    "a",     "sc01E",
    "s",     "sc01F",
    "d",     "sc020"
  )
  normKey := StrLower(key)
  if (useScanCodes && scodes.Has(normKey)) {
    Send("{" . scodes[normKey] . " down}")
    Sleep holdMs
    Send("{" . scodes[normKey] . " up}")
    return
  }
  vkKey := normKey ~= "^(left|right|up|down|space)$"
    ? "{" . (normKey = "space" ? "Space" : normKey) . "}"
    : key
  Send(vkKey . " down")
  Sleep holdMs
  Send(vkKey . " up")
}

Move(dir, times := 1, perMoveHold := 0) {
  global movement, pauseBetweenStrokes, holdMsMove, running
  hold := perMoveHold ? perMoveHold : holdMsMove
  Loop times {
    if (!running) {
      return
    }
    PressHold(movement[dir], hold)
    if (!running) {
      return
    }
    SleepCancellable(pauseBetweenStrokes)
  }
}

HarvestTile() {
  global harvestHoldMs, pauseBetweenStrokes, running
  if (!running) {
    return
  }
  PressHold("space", harvestHoldMs)
  if (!running) {
    return
  }
  Send("{Esc}")
  SleepCancellable(pauseBetweenStrokes)
}

; ---------- App focus (not used; assume Discord is focused) ----------

EnterGarden() {
  PressChord("Shift", "2")
  SleepCancellable(tGarden)
}

SellAtShop() {
  PressChord("Shift", "3")
  SleepCancellable(tShop)
  PressHold("space", holdMsSpace)
  SleepCancellable(pauseBetweenStrokes)
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
  moveInto := (plotSide = "left") ? "left" : "right" ; step from walkway into plot each row
  dir := moveInto                                   ; first row moves away from walkway
  vertStep := startFromTop ? "down" : "up"

  ; Enter the plot for the first row from the walkway anchor
  Move(moveInto, 1)
  if (!running) {
    return
  }

  Loop 10 {
    row := A_Index
    if (!running) {
      return
    }
    HarvestRow(dir)         ; sweep across the row in current direction
    if (!running) {
      return
    }
    SellAtShop()            ; sell from current edge
    if (!running) {
      return
    }
    EnterGarden()           ; return to garden (assumed same anchor)
    if (!running) {
      return
    }
    if (row = 10) {
      break
    }
    Move(vertStep, 1)       ; move one tile along walkway to next row
    if (!running) {
      return
    }
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

  EnterGarden() ; start at top of walkway between plots
  if (!running) {
    return
  }

  while (running) {
    ; Left plot: top -> bottom serpentine
    TraversePlot("left", true)
    if (!running) {
      break
    }

    ; Step onto the walkway at bottom and let TraversePlot("right") enter the right plot
    Move("right", 1) ; from left plot walkway edge onto the walkway
    if (!running) {
      break
    }

    ; Right plot: bottom -> top serpentine
    TraversePlot("right", false)
    if (!running) {
      break
    }

    ; Reset to top walkway between plots, ready to start left plot again
    EnterGarden() ; back to last anchor (top of right plot edge)
    if (!running) {
      break
    }
    Move("left", 1) ; step onto the walkway; next loop will enter left plot
    if (!running) {
      break
    }
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

TrayTip(
  "Farm macro",
  "Loaded. Hotkeys: Start(Shift+S), Abort(^Esc) | SendMode: " . sendModeName
    . " | Scancodes: " . (useScanCodes ? "on" : "off")
    . " | Hold(space/move): " . holdMsSpace . "/" . holdMsMove
    . " | Pause: " . pauseBetweenStrokes
)