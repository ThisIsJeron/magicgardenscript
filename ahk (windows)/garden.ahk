; AutoHotkey v2 - Discord Garden Macro
; 
; This macro handles both upward and downward facing gardens.
; Set gardenFacingDown := true for gardens that face down (default)
; Set gardenFacingDown := false for gardens that face up

; ---------- Config ----------
useArrows := true
harvestRepeatsMin := 4
harvestRepeatsMax := 6
tGarden := 600           ; ms after Shift+2
tShop := 600             ; ms after Shift+3
tAction := 60           ; ms per Space
tMove := 80             ; ms per tile move
jitter := 10             ; +/- ms jitter
sellEveryRows := 2
entryAtTop := true       ; true: Shift+2 drops at top; false: bottom
gardenFacingDown := true ; true: garden faces down (default), false: garden faces up
autoLoop := true
loopDelayMs := 15000    ; 15 sec
startHotkey := "^!g"     ; Ctrl+Alt+G
abortHotkey := "^Esc"    ; Ctrl+Esc
startHotkeyDown := "^!d"  ; Ctrl+Alt+D (start run for downward-facing garden)
startHotkeyUp := "^!u"    ; Ctrl+Alt+U (start run for upward-facing garden)

; ---------- State ----------
global running := false
global q := []
global prevHwnd := 0
global currentTimerCb := 0  ; holds the currently scheduled one-shot timer callback for cancellation
global lastFacingDown := gardenFacingDown

movement := useArrows
  ? Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
RandDelay(ms) {
  global jitter
  return ms + Random(-jitter, jitter)
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
      SetOneShotTimer(() => RunAll(), loopDelayMs)
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
  global running, q, entryAtTop, gardenFacingDown, lastFacingDown
  if (running) {
    TrayTip("Farm macro", "Already running")
    return
  }
  running := true
  q := []
  
  ; Determine facing for this run (argument overrides current setting)
  if (IsSet(facingDown) && facingDown != "") {
    gardenFacingDown := facingDown
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
  Enqueue(() => EnterGarden(), 0)
  Enqueue(() => MoveDyn(vStep, 1), 0)
  Enqueue(() => Move("left", 1), 0)
  Enqueue(() => TraverseLeftPlot(vStep), 0)

  ; Sell before switching plots
  Enqueue(() => SellAtShop(), 0)

  ; Right plot
  Enqueue(() => EnterGarden(), 0)
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

TrayTip("Farm macro", "Loaded. " . (entryAtTop ? "Entry at TOP" : "Entry at BOTTOM") . 
  ". Facing " . (gardenFacingDown ? "DOWN" : "UP") .
  ". Hotkeys: Start(^!g), Down(^!d), Up(^!u), Abort(^Esc)")