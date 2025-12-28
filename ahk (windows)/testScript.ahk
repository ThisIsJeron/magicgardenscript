; AutoHotkey v2 — Discord Garden input tester
#Requires AutoHotkey v2.0
#SingleInstance Force

; Press F8 to run all input-method variants against the active window
; Press F9 to stop early

; ------------ Config ------------
targetWin := "ahk_exe Discord.exe"  ; set "" to skip focusing
delayBetweenTests := 2000           ; ms pause between methods
keyDelay := 30                      ; default key delay
keyPressDuration := 10              ; default key hold

; ------------ State ------------
global running := false
global useScan := false

tests := [
  { name: "SendEvent + VirtualKeys", mode: "Event", sc: false },
  { name: "SendEvent + ScanCodes",   mode: "Event", sc: true  },
  { name: "SendInput + VirtualKeys", mode: "Input", sc: false },
  { name: "SendInput + ScanCodes",   mode: "Input", sc: true  },
  { name: "SendPlay + VirtualKeys",  mode: "Play",  sc: false },
  { name: "SendPlay + ScanCodes",    mode: "Play",  sc: true  },
  { name: "InputThenPlay + Virtual", mode: "InputThenPlay", sc: false },
  { name: "InputThenPlay + Scan",    mode: "InputThenPlay", sc: true }
]

; ------------ Helpers ------------
FocusDiscord() {
  global targetWin
  if (!targetWin)
    return
  if WinExist(targetWin)
    WinActivate(targetWin)
}

Stroke(key) {
  global useScan
  scodes := Map(
    "space", "{sc039}",
    "left",  "{sc14B}",
    "right", "{sc14D}",
    "up",    "{sc148}",
    "down",  "{sc150}",
    "w",     "{sc011}",
    "a",     "{sc01E}",
    "s",     "{sc01F}",
    "d",     "{sc020}"
  )
  if (useScan && scodes.Has(key)) {
    Send(scodes[key])
  } else {
    ; For arrow keys with virtual keys, use the brace form
    vkKey := key ~= "^(left|right|up|down)$" ? "{" . key . "}" : key
    Send(vkKey)
  }
}

Notify(title, msg) {
  TrayTip(title, msg, 2)
}

RunOneTest(testObj) {
  global useScan
  A_SendMode := testObj.mode
  A_KeyDelay := keyDelay
  A_KeyDuration := keyPressDuration
  useScan := testObj.sc

  msg := testObj.name . " | ScanCodes: " . (useScan ? "On" : "Off")
  Notify("Garden Input Test", msg)
  Sleep 400

  FocusDiscord()

  ; Sequence: tap space 3x, then left/right/up/down, then WASD
  Loop 3 {
    Stroke("space")
    Sleep 120
  }
  for dir in ["left","right","up","down"] {
    Stroke(dir)
    Sleep 120
  }
  for key in ["w","a","s","d"] {
    Stroke(key)
    Sleep 120
  }
}

StopTests(*) {
  global running
  running := false
  Notify("Garden Input Test", "Stopped")
}

RunAllTests(*) {
  global running
  if (running) {
    Notify("Garden Input Test", "Already running")
    return
  }
  running := true
  Notify("Garden Input Test", "Starting input-method sweep")
  for test in tests {
    if (!running)
      break
    RunOneTest(test)
    Sleep delayBetweenTests
  }
  running := false
  Notify("Garden Input Test", "Finished sweep")
}

; ------------ Hotkeys ------------
Hotkey("^Esc", StopTests) ; emergency stop if Discord ignores F9
Hotkey("F8", RunAllTests)
Hotkey("F9", StopTests)

Notify("Garden Input Test", "Loaded. Hotkeys: Start(F8), Stop(F9/^Esc)")
