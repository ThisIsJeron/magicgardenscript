# Magic Garden AHK Macros (Discord applet)

AutoHotkey v2 scripts to automate the two-plot garden mini-game inside Discord. Hotkeys: Shift+S (start), Shift+P (pause/resume), Ctrl+Esc (abort). Scripts assume you begin at the top tile of the walkway between the two 10x10 plots. Inputs prefer SendEvent with scancodes and held keys to register reliably in the applet.

## Quick-use prompt for future chats
Copy/paste this when opening a new chat so you do not have to re-explain the setup:

```
We have an AutoHotkey v2 macro for a Discord garden mini-game. The garden has two 10x10 plots separated by a 1x10 walkway. Start at the top of the walkway. Traversal: left plot serpentine top→bottom; each row enters from the walkway, harvests 10 tiles (long-press space ~1000ms for mutated fruit + Esc to dismiss, then 6-8 rapid taps ~160ms for normal fruit), sells (Shift+3), returns to garden (Shift+2), moves down 1, flips direction. After the left plot finishes, step right 1 to the walkway, run the right plot bottom→top with the same per-row sell/return, then step left 1 to the top walkway and loop. Inventory fills after 1 row so sell every row (rowsPerSell=1). Inputs use held keys: SendMode=Event, scancodes on, hold space/move ~160–220ms, pause between strokes ~250ms, modifier chords use chordPreGap ~30ms then holdMsChord ~350ms. Anti-detection: ±30ms jitter on all sleeps, 8% chance of a random micro-pause (400-1200ms) between rows. Hotkeys: Shift+S start, Shift+P pause/resume, Ctrl+Esc abort. If inputs are ignored, try SendMode InputThenPlay or Play. Focus is Discord (auto-activated at start); assumes My Garden (Shift+2) returns you to the same tile you left from.
```

## Files
- `ahk (windows)/garden.ahk` — main macro with held inputs, per-row sell/return serpentine traversal for both plots, pause/resume, anti-detection jitter, and progress tracking.
- `ahk (windows)/testScript.ahk` — input-method sweep tester (cycles SendEvent/Input/Play/InputThenPlay with scancodes).

## Tweaks
- Timing: `holdMsSpace`, `holdMsMove`, `holdMsChord`, `chordPreGap`, `pauseMs`, `tGarden`, `tShop`, `tAction`.
- Harvest: `harvestHoldMs` (mutated long-press), `harvestTapsMin`/`harvestTapsMax` (normal fruit tap count).
- Batch selling: `rowsPerSell` (rows harvested before selling; 1 = every row, increase if inventory allows).
- Anti-detection: `jitterMs` (±ms on all sleeps), `microPauseChance` / `microPauseMinMs` / `microPauseMaxMs`.
- Input compatibility: `sendModeName` and `useScanCodes` (default scancodes + SendEvent). If Discord ignores input, try `InputThenPlay` or `Play`.

## How to run
1) Open Discord garden applet and focus it (or let the script auto-activate Discord).
2) Run `garden.ahk`; press Shift+S to start, Shift+P to pause/resume, Ctrl+Esc to abort.
3) Start from the top of the walkway for correct alignment.
4) Adjust hold/pause timings if movement or chords miss.
