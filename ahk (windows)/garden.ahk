; AutoHotkey v2 - Discord Garden Macro

; ---------- Config ----------
useArrows := true
harvestRepeatsMin := 4
harvestRepeatsMax := 6
tGarden := 900           ; ms after Shift+2
tShop := 700             ; ms after Shift+3
tAction := 120           ; ms per Space
tMove := 120             ; ms per tile move
jitter := 30             ; +/- ms jitter
sellEveryRows := 2
entryAtTop := true       ; true: Shift+2 drops at top; false: bottom
autoLoop := true
loopDelayMs := 240000    ; 4 minutes
startHotkey := "!#g"     ; Alt+Win+G
abortHotkey := "^Esc"    ; Ctrl+Esc

; ---------- State ----------
global running := false
global q := []
global prevHwnd := 0

movement := useArrows
  ? Map("left","{Left}","right","{Right}","up","{Up}","down","{Down}")
  : Map("left","a","right","d","up","w","down","s")

; ---------- Utils ----------
RandDelay(ms) {
  global jitter
  return ms + Random(-jitter, jitter)
}

Enqueue(fn, delayMs) {
  global q
  q.Push(Map("f", fn, "d", delayMs))
}

SetOneShotTimer(cb, delayMs) {
  if (delayMs <= 0) {
    cb.Call()
  } else {
    SetTimer(() => cb.Call(), -delayMs)
  }
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
      RestorePrevApp()
      SetOneShotTimer(Func("RunAll"), loopDelayMs)
    }
    return
  }
  step := q.RemoveAt(1)
  SetOneShotTimer(() => (
    running ? step["f"].Call() : 0,
    ProcessNext()
  ), RandDelay(step["d"]))
}

StartQueue() {
  ProcessNext()
}

; ---------- Send helpers ----------
Press(mods, key) {
  Send(mods key)
}

Stroke(key) {
  Send(key)
}

Move(dir, times := 1, perMove := 0) {
  global movement, tMove
  Loop times {
    Stroke(movement[dir])
    Sleep RandDelay(perMove || tMove)
  }
}

HarvestTile() {
  global harvestRepeatsMin, harvestRepeatsMax, tAction
  reps := Random(harvestRepeatsMin, harvestRepeatsMax)
  Loop reps {
    Stroke(" ")
    Sleep RandDelay(tAction)
  }
}

; ---------- App focus ----------
FocusDiscord() {
  WinActivate "ahk_exe Discord.exe"
  Sleep 250
}

SavePrevApp() {
  global prevHwnd
  prevHwnd := WinExist("A")
}

RestorePrevApp() {
  global prevHwnd
  if (prevHwnd) {
    WinActivate "ahk_id " prevHwnd
  }
}

EnterGarden() {
  Press("+", "2")
  Sleep RandDelay(tGarden)
}

SellAtShop() {
  Press("+", "3")
  Sleep RandDelay(tShop)
  Stroke(" ")
}

; ---------- Traversal ----------
Traverse10x10(startDir, sellEveryRows := 0, afterRowsCb := 0, vStep := "down") {
  dir := startDir
  Loop 10 row {
    Loop 10 col {
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
  Traverse10x10("left", sellEveryRows, Func("ResumeLeft").Bind(vStep), vStep)
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
  Traverse10x10("right", sellEveryRows, Func("ResumeRight").Bind(vStep), vStep)
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
RunAll() {
  global running, q, entryAtTop
  if (running) {
    TrayTip("Farm macro", "Already running")
    return
  }
  running := true
  q := []
  SavePrevApp()

  vStep := entryAtTop ? "down" : "up"

  Enqueue(Func("FocusDiscord"), 250)

  ; Left plot
  Enqueue(Func("EnterGarden"), 0)
  Enqueue(Func("MoveDyn").Bind(vStep, 1), 0)
  Enqueue(Func("Move").Bind("left", 1), 0)
  Enqueue(Func("TraverseLeftPlot").Bind(vStep), 0)

  ; Sell before switching plots
  Enqueue(Func("SellAtShop"), 0)

  ; Right plot
  Enqueue(Func("EnterGarden"), 0)
  Enqueue(Func("MoveDyn").Bind(vStep, 1), 0)
  Enqueue(Func("Move").Bind("right", 1), 0)
  Enqueue(Func("TraverseRightPlot").Bind(vStep), 0)

  ; Final sell
  Enqueue(Func("SellAtShop"), 0)

  StartQueue()
}

; ---------- Hotkeys ----------
Hotkey(startHotkey, (*) => RunAll())
Hotkey(abortHotkey, (*) => (
  running := false,
  q := [],
  TrayTip("Farm macro", "Aborted")
))

TrayTip("Farm macro", "Loaded. " (entryAtTop ? "Entry at TOP" : "Entry at BOTTOM"))


