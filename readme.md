# Magic Garden AHK Macros (Discord applet)

AutoHotkey v2 scripts to automate the two-plot garden mini-game inside Discord. Hotkeys default to Ctrl+D (start) and Ctrl+Esc (stop). Scripts assume you begin at the top tile of the walkway between the two 10x10 plots. Inputs prefer SendEvent with scancodes and held keys to register reliably in the applet.

## Quick-use prompt for future chats
Copy/paste this when opening a new chat so you do not have to re-explain the setup:

```
We have an AutoHotkey v2 macro for a Discord garden mini-game. The garden has two 10x10 plots separated by a 1x10 walkway. Starting position: top of the walkway. Traversal pattern: left plot serpentine top→bottom; each row enters from the walkway, harvests 10 tiles, sells (Shift+3), returns to garden (Shift+2), moves down 1 on the walkway, flips direction. Then the right plot serpentine bottom→top with the same per-row sell/return pattern. Inputs should be sent with held keys: SendMode=Event, scancodes on, hold space/move ~160–220ms, pause between strokes ~250ms, modifier chords (Shift+2/Shift+3) held ~350ms. Hotkeys: Ctrl+D to start, Ctrl+Esc to abort. If inputs get ignored, try SendMode InputThenPlay or Play. Focus target is Discord; no fancy orientation detection—assumes My Garden returns you to the same tile.
```

## Files
- `ahk (windows)/garden.ahk` — main macro with held inputs, per-row sell/return serpentine traversal for both plots.
- `ahk (windows)/testScript.ahk` — input-method sweep tester (cycles SendEvent/Input/Play/InputThenPlay with scancodes).

## Tweaks
- Timing: `holdMsSpace`, `holdMsMove`, `holdMsChord`, `pauseBetweenStrokes`, `tGarden`, `tShop`, `tAction`.
- Input compatibility: `sendModeName` and `useScanCodes` (default scancodes + SendEvent). If Discord ignores input, try `InputThenPlay` or `Play`.

## How to run
1) Open Discord garden applet and focus it.  
2) Run `garden.ahk`; press Ctrl+D to start, Ctrl+Esc to abort.  
3) Start from the top of the walkway for correct alignment.  
4) Adjust hold/pause timings if movement or chords miss.***

