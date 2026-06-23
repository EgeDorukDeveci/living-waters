# Living Waters

Living Waters is a persistent aquarium simulation for Windows. The aquarium keeps living while the PC is on, even when the visible 2D Godot aquarium window is closed.

This is a vertical slice, not a screensaver. The background process simulates water chemistry, a nitrogen cycle, filtration, feeding, oxygen, aquascape plants, fish stress, health, mortality explanations, and Windows notifications.

## Run

Double-click:

```text
Living Waters.bat
```

That starts:

- `LivingWatersBackground.exe` or the Python daemon
- `Living Waters.exe` or the Godot editor project

Closing the aquarium window does not stop the ecosystem. Use the tray icon to reopen it, feed modestly, pause, send a test notification, or exit.

## Build

Install Godot 4.7 stable locally for this project:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup_godot.ps1
```

Then build:

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The build creates:

- `Living Waters.exe`
- `LivingWatersBackground.exe`

## Tests

```powershell
py -3 .\tests\run_tests.py
py -3 .\background\living_waters_daemon.py --self-test
.\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path . --quit
```

## Background Responsibility

- Startup uses the current user's Windows Run key.
- Offline progression is capped at 12 hours.
- The background process has no visual rendering, so the ecosystem can keep running quietly.
- Notifications are sent only for important warning or critical events.
- Major interventions are commands, never automatic hidden fixes.

## V1 Species

- Neon tetra
- Siamese fighting fish
- Zebra danio
- Peppered corydoras
- Cherry shrimp
- Harlequin rasbora
- Fancy guppy
- Honey gourami
- Kuhli loach

The shipped starter tank uses neon tetras, peppered corydoras, and cherry shrimp because their water parameters overlap better than the full catalogue. The other species are present to demonstrate compatibility constraints and future scenarios.

## Visual Direction

The client uses a 2D planted-aquarium style. The default aquascape is `greenscape`: carpet plants, taller stems, stone clusters, driftwood, bubbles, calm layered water, and species-specific fish silhouettes.

The Scape Studio controls can add river stones, moss stones, branch driftwood, root driftwood, hairgrass, vallisneria, java fern, and floating plants. Plant choices affect nitrate uptake, daytime oxygen, nighttime oxygen use, hiding cover, algae control, and maintenance load.

## Not Veterinary Advice

This is an educational simulation and game. Do not use it as professional veterinary or aquarium-care advice.
