; AutoHotkey v2 - Discord Garden Macro
; 
; This macro handles both upward and downward facing gardens.
; Set gardenFacingDown := true for gardens that face down (default)
; Set gardenFacingDown := false for gardens that face up

; ---------- Config ----------
useArrows := true
harvestRepeatsMin := 6
harvestRepeatsMax := 8
tGarden := 600           ; ms after Shift+2
tShop := 700             ; ms after Shift+3 (UI open)
tAction := 250           ; ms per Space (throttle harvest rate)
tMove := 80             ; ms per tile move
jitter := 10             ; +/- ms jitter
sellEveryRows := 1
entryAtTop := true       ; true: Shift+2 drops at top; false: bottom
gardenFacingDown := true ; true: garden faces down (default), false: garden faces up
autoLoop := true
loopDelayMs := 0        ; immediate next run
startHotkey := "^+g"     ; Ctrl+Shift+G
abortHotkey := "^Esc"    ; Ctrl+Esc
startHotkeyDown := "^d"  ; Ctrl+D (start run for downward-facing garden)
startHotkeyUp := "^u"    ; Ctrl+U (start run for upward-facing garden)

; Auto-detect & calibration
autoDetectFacing := true
pixelCoordMode := "Window"   ; "Window" or "Screen"
colorTolerance := 60          ; color distance threshold for a match
calibrationFile := A_ScriptDir . "\garden_cal.ini"
calHotkeyDown := "^+j"       ; Ctrl+Shift+J (save sample for DOWN)
calHotkeyUp := "^+k"         ; Ctrl+Shift+K (save sample for UP)
testDetectHotkey := "^+t"    ; Ctrl+Shift+T (test detection)
; Recheck between plots
recheckFacingAfterLeft := true

; ---------- State ----------
global running := false
global q := []
global prevHwnd := 0
global currentTimerCb := 0  ; holds the currently scheduled one-shot timer callback for cancellation
global lastFacingDown := gardenFacingDown

; Calibration state
global calDown := Map("x", 0, "y", 0, "color", 0, "set", false)
global calUp := Map("x", 0, "y", 0, "color", 0, "set", false)

movement := useArrows
  ? Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
RandDelay(ms) {
  global jitter
  return ms + Random(-jitter, jitter)
}

EnsureCoordModes() {
  global pixelCoordMode
  CoordMode "Pixel", pixelCoordMode
  CoordMode "Mouse", pixelCoordMode
}

GetPixelRGB(x, y) {
  EnsureCoordModes()
  ; Return RGB integer 0xRRGGBB
  return PixelGetColor(x, y, "RGB")
}

RGBComponents(color) {
  r := (color >> 16) & 0xFF
  g := (color >> 8) & 0xFF
  b := color & 0xFF
  return [r, g, b]
}

ColorDistance(c1, c2) {
  parts1 := RGBComponents(c1)
  parts2 := RGBComponents(c2)
  dr := Abs(parts1[1] - parts2[1])
  dg := Abs(parts1[2] - parts2[2])
  db := Abs(parts1[3] - parts2[3])
  return dr + dg + db
}

SaveCalibration() {
  global calibrationFile, calDown, calUp
  IniWrite calDown["x"], calibrationFile, "Calibration", "DownX"
  IniWrite calDown["y"], calibrationFile, "Calibration", "DownY"
  IniWrite calDown["color"], calibrationFile, "Calibration", "DownColor"
  IniWrite (calDown["set"] ? 1 : 0), calibrationFile, "Calibration", "DownSet"
  IniWrite calUp["x"], calibrationFile, "Calibration", "UpX"
  IniWrite calUp["y"], calibrationFile, "Calibration", "UpY"
  IniWrite calUp["color"], calibrationFile, "Calibration", "UpColor"
  IniWrite (calUp["set"] ? 1 : 0), calibrationFile, "Calibration", "UpSet"
}

LoadCalibration() {
  global calibrationFile, calDown, calUp
  downSet := IniRead(calibrationFile, "Calibration", "DownSet", "0")
  upSet := IniRead(calibrationFile, "Calibration", "UpSet", "0")
  calDown["x"] := Integer(IniRead(calibrationFile, "Calibration", "DownX", "0"))
  calDown["y"] := Integer(IniRead(calibrationFile, "Calibration", "DownY", "0"))
  calDown["color"] := Integer(IniRead(calibrationFile, "Calibration", "DownColor", "0"))
  calDown["set"] := (downSet = "1")
  calUp["x"] := Integer(IniRead(calibrationFile, "Calibration", "UpX", "0"))
  calUp["y"] := Integer(IniRead(calibrationFile, "Calibration", "UpY", "0"))
  calUp["color"] := Integer(IniRead(calibrationFile, "Calibration", "UpColor", "0"))
  calUp["set"] := (upSet = "1")
}

CalibrateAtMouse(isDown) {
  global calDown, calUp
  EnsureCoordModes()
  MouseGetPos &mx, &my
  col := GetPixelRGB(mx, my)
  if (isDown) {
    calDown["x"] := mx
    calDown["y"] := my
    calDown["color"] := col
    calDown["set"] := true
    SaveCalibration()
    TrayTip("Farm macro", "Saved DOWN calibration at (" . mx . "," . my . ")")
  } else {
    calUp["x"] := mx
    calUp["y"] := my
    calUp["color"] := col
    calUp["set"] := true
    SaveCalibration()
    TrayTip("Farm macro", "Saved UP calibration at (" . mx . "," . my . ")")
  }
}

DetectFacing() {
  global calDown, calUp, colorTolerance, lastFacingDown
  if !(calDown["set"] && calUp["set"]) {
    return ""
  }
  colDownCur := GetPixelRGB(calDown["x"], calDown["y"])
  colUpCur := GetPixelRGB(calUp["x"], calUp["y"])
  dDown := ColorDistance(colDownCur, calDown["color"])
  dUp := ColorDistance(colUpCur, calUp["color"])
  if (dDown > 10000 || dUp > 10000) { ; guard for bogus values
    return lastFacingDown
  }
  if (dDown <= colorTolerance || dUp <= colorTolerance) {
    return dDown <= dUp
  }
  ; If both are over tolerance, fall back to last known
  return lastFacingDown
}

MaybeRecheckFacingAndRestart() {
  global autoDetectFacing, gardenFacingDown, lastFacingDown, running
  if (!autoDetectFacing) {
    return
  }
  detected := DetectFacing()
  if (detected = "") {
    return
  }
  if (detected != gardenFacingDown) {
    ; Orientation changed mid-run: abort and immediately restart with new facing
    running := false
    lastFacingDown := detected
    SetOneShotTimer(() => RunAll(detected), 0)
  }
}

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

Enqueue(fn, delayMs) {
  global q
  q.Push(Map("f", fn, "d", delayMs))
}

SetOneShotTimer(cb, delayMs) {
  global currentTimerCb
  if (currentTimerCb) {
    ; cancel any previously scheduled one-shot timer
    SetTimer(currentTimerCb, 0)
    currentTimerCb := 0
  }
  if (delayMs <= 0) {
    cb.Call()
    return
  }
  wrapper := () => cb.Call()
  currentTimerCb := wrapper
  SetTimer(wrapper, -delayMs)
}

ProcessNext() {
  global q, running
  if (!running) {
    q := []
    return
  }
  if (q.Length = 0) {
    running := false
    TrayTip("Farm macro", autoLoop ? "Waiting before next run..." : "Finished")
    if (autoLoop) {
      SetOneShotTimer(() => RunAll(lastFacingDown), loopDelayMs)
    }
    return
  }
  step := q.RemoveAt(1)
  SetOneShotTimer(() => (
    running ? step["f"].Call() : 0,
    running ? ProcessNext() : 0
  ), RandDelay(step["d"]))
}

StartQueue() {
  ProcessNext()
}

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
Traverse10x10(startDir, sellEveryRows := 0, afterRowsCb := 0, vStep := "down") {
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
    if (row < 10) {
      Move(vStep, 1)
      dir := (dir = "right") ? "left" : "right"
    }
    if (sellEveryRows > 0 && Mod(row, sellEveryRows) = 0 && row < 10) {
      SellAtShop()
      if (IsSet(afterRowsCb) && afterRowsCb) {
        afterRowsCb.Call(row, dir)
      }
    }
  }
}

MoveDyn(dir, times := 1) {
  Move(dir, times)
}

TraverseLeftPlot(vStep) {
  global sellEveryRows
  Traverse10x10("left", sellEveryRows, (row, nextDir) => ResumeLeft(vStep, row, nextDir), vStep)
}

ResumeLeft(vStep, resumeRow, nextDir) {
  EnterGarden()
  MoveDyn(vStep, 1)
  Move("left", 1)
  MoveDyn(vStep, resumeRow)
  if (nextDir = "right") {
    Move("left", 9)
  }
}

TraverseRightPlot(vStep) {
  global sellEveryRows
  Traverse10x10("right", sellEveryRows, (row, nextDir) => ResumeRight(vStep, row, nextDir), vStep)
}

ResumeRight(vStep, resumeRow, nextDir) {
  EnterGarden()
  MoveDyn(vStep, 1)
  Move("right", 1)
  MoveDyn(vStep, resumeRow)
  if (nextDir = "left") {
    Move("right", 9)
  }
}

; ---------- Run logic ----------
RunAll(facingDown := "") {
  global running, q, entryAtTop, gardenFacingDown, lastFacingDown, autoDetectFacing
  if (running) {
    TrayTip("Farm macro", "Already running")
    return
  }
  running := true
  q := []

  openedForDetection := false
  ; Determine facing for this run (argument overrides current setting)
  if (IsSet(facingDown) && facingDown != "") {
    gardenFacingDown := facingDown
  } else if (autoDetectFacing) {
    ; Open garden and detect orientation from calibrated pixels
    EnterGarden()
    SleepCancellable(tGarden)
    openedForDetection := true
    detected := DetectFacing()
    if (detected != "") {
      gardenFacingDown := detected
    }
  }
  lastFacingDown := gardenFacingDown

  ; Determine vertical step based on entry position and facing
  if (gardenFacingDown) {
    vStep := entryAtTop ? "down" : "up"
  } else {
    vStep := entryAtTop ? "up" : "down"
  }
  ; Assuming Discord is already focused

  ; Left plot
  if (openedForDetection) {
    Enqueue(() => MoveDyn(vStep, 1), 0)
    Enqueue(() => Move("left", 1), 0)
  } else {
    Enqueue(() => EnterGarden(), 0)
    Enqueue(() => MoveDyn(vStep, 1), 0)
    Enqueue(() => Move("left", 1), 0)
  }
  Enqueue(() => TraverseLeftPlot(vStep), 0)

  ; Sell before switching plots
  Enqueue(() => SellAtShop(), 0)

  ; Right plot
  Enqueue(() => EnterGarden(), 0)
  if (recheckFacingAfterLeft) {
    Enqueue(() => MaybeRecheckFacingAndRestart(), 0)
  }
  Enqueue(() => MoveDyn(vStep, 1), 0)
  Enqueue(() => Move("right", 1), 0)
  Enqueue(() => TraverseRightPlot(vStep), 0)

  ; Final sell
  Enqueue(() => SellAtShop(), 0)

  StartQueue()
}

AbortMacro(*) {
  global running, q, currentTimerCb
  running := false
  q := []
  if (currentTimerCb) {
    SetTimer(currentTimerCb, 0)
    currentTimerCb := 0
  }
  TrayTip("Farm macro", "Aborted")
}

; ---------- Hotkeys ----------
Hotkey(startHotkey, (*) => RunAll())
Hotkey(startHotkeyDown, (*) => RunAll(true))
Hotkey(startHotkeyUp, (*) => RunAll(false))
Hotkey(abortHotkey, AbortMacro)

; Calibration & test hotkeys
Hotkey(calHotkeyDown, (*) => CalibrateAtMouse(true))
Hotkey(calHotkeyUp, (*) => CalibrateAtMouse(false))
Hotkey(testDetectHotkey, (*) => (
  result := DetectFacing(),
  TrayTip("Farm macro", result = "" ? "Detect: need calibration (J for DOWN, K for UP)" : (result ? "Detect: DOWN" : "Detect: UP"))
))

; Load calibration at startup
LoadCalibration()

TrayTip("Farm macro", "Loaded. " . (entryAtTop ? "Entry at TOP" : "Entry at BOTTOM") . 
  ". Facing " . (gardenFacingDown ? "DOWN" : "UP") .
  ". AutoDetect:" . (autoDetectFacing ? "ON" : "OFF") .
  ". Hotkeys: Start(^+g), Down(^d), Up(^u), Abort(^Esc), CalDown(^+j), CalUp(^+k), Test(^+t)")