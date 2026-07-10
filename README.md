# Living Waters

Living Waters is a persistent aquarium simulation for Windows. The aquarium keeps living while the PC is on, even when the visible 2D Godot aquarium window is closed.

This is a living-aquarium companion, not a normal game or screensaver. The background process simulates freshwater and saltwater systems, water chemistry, a nitrogen cycle, filtration, feeding, oxygen, aquascape plants, corals, fish stress, acclimation shock, health, mortality explanations, and Windows notifications.

You can keep multiple aquariums at once. Each aquarium has its own saved water, animals, scape, cycle, events, and timeline, and the background process advances all of them while Windows is running. The visible window shows the selected aquarium.

The simulation includes a welfare engine. It evaluates minimum group sizes, preferred school sizes, active bioload, tank length/volume, open swimming room, hiding cover, territorial aggression, fin-nipping risk, predation intimidation, salinity mismatch, and species-specific water limits. Schooling or shoaling fish kept alone or in small groups now suffer severe chronic stress and can die even when the water looks clean.

Filtration is modeled as mechanical, biological, and chemical media. Mechanical media traps suspended waste but clogs and lowers flow. Biological media needs maturity, oxygen, alkalinity, pH stability, and flow to process ammonia and nitrite. Chemical carbon polishes organics but depletes over time. Servicing the filter restores flow and carbon without fully destroying the biofilter.

Planning and husbandry are part of the simulation too. The tank tracks estimated loaded weight, stand rating, level support, direct sunlight, vibration, room temperature swing, maintenance access, required equipment, cycling state, water-test dates, water-change dates, substrate vacuuming, dechlorinator use, light duration, plant spectrum, substrate depth, tannins, phosphate, and algae pressure. Bad planning or missed care creates warnings and can feed back into fish welfare and water quality.

New aquariums start as clear empty tanks with chosen litre size, calculated dimensions, clean water, equipment, no livestock, no hidden scape, and an immature biofilter. They must be cycled and deliberately stocked.

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

Freshwater:

- Neon tetra
- Cardinal tetra
- Rummy-nose tetra
- Black neon tetra
- Siamese fighting fish
- Zebra danio
- White cloud mountain minnow
- Peppered corydoras
- Cherry shrimp
- Harlequin rasbora
- Fancy guppy
- Platy
- Honey gourami
- Kuhli loach
- Ember tetra
- Otocinclus catfish
- Celestial pearl danio
- Bristlenose pleco
- German blue ram
- Dwarf chain loach

Saltwater:

- Ocellaris clownfish
- Royal gramma
- Banggai cardinalfish
- Blue green chromis
- Yellow watchman goby
- Firefish
- Tailspot blenny
- Pajama cardinalfish
- Yellow clown goby
- Skunk cleaner shrimp

No animals are pre-placed; add each fish, shrimp, or marine animal yourself when you are ready to acclimate it.

## Research Cards

The animal selector includes a local research card for the selected species. It summarizes adult size, minimum tank volume and length, minimum and preferred group size, water parameters, social behavior, nitrate sensitivity, care notes, and source domains. This is deliberately partial and conservative: it gives enough information to avoid obvious stocking mistakes without pretending to replace proper research.

## Visual Direction

The client uses a 2D planted-aquarium style. The default aquascape is `greenscape`: carpet plants, taller stems, stone clusters, driftwood, bubbles, calm layered water, and species-specific fish silhouettes.

The Scape Studio controls can add river stones, moss stones, slate stacks, lava rock, live rock, reef arches, branch driftwood, root driftwood, manzanita, hairgrass, vallisneria, amazon sword, cryptocoryne, java fern, java moss, hornwort, floating plants, macroalgae, and starter corals. Click a scape item, then click a valid place in the aquarium. Floaters must stay near the surface, rooted plants must touch substrate, hornwort must either float or be planted, and hardscape/corals need a surface. Select an existing placed object and click a new valid spot to relocate it. Use **Clear scape** for a truly empty tank.

Plant, rock, macroalgae, and coral choices affect nitrate uptake, daytime oxygen, nighttime oxygen use, hiding cover, algae control, maintenance load, and reef stability. Water color shifts with freshwater/saltwater style and worsens visibly as turbidity, ammonia, or nitrate rise.

Animals can be added from the side panel. The safe path is **Acclimate**. **Skip acclimation** is intentionally dangerous: sensitive animals can die from shock, and dead animals add organic waste and ammonia until removed or decomposed.

The status area shows the current welfare score and the first major welfare issue. Individual animal rows can show concrete reasons such as undersized groups, aggression pressure, crowding, lack of cover, or lack of swimming room.

The side panel also shows filter flow, mechanical clogging, carbon remaining, cycle readiness, planning risk, and maintenance status. Use **Weekly care** for a dechlorinated water change and substrate cleanup, **Test water** to log parameter checks, **Service filter** when flow drops, and **Dose cycle** only for fishless cycling before animals are present.

At normal speed, simulation time matches real time. Acute chemistry and oxygen emergencies can become dangerous quickly, while social, nutritional, and disease pressure develops over realistic multi-day or multi-week timescales. Tank volume now changes how strongly livestock waste concentrates, and feeding portions adapt to the current living bioload and hunger.

Use **Fit safety & outage kit** to prepare a lid, guarded filter intake, drip loops, protected-power plan, dedicated tools, spare conditioner, and battery aeration. The action has an in-tank setup animation and the safeguards remain visible in the planning status and aquarium drawing.

Fish, plants, stones, and driftwood are rendered from transparent 2D sprites in `assets/sprites`. Run `py -3 .\art\generate_sprites.py` to regenerate the current sprite set.

## Not Veterinary Advice

This is an educational companion simulation. Do not use it as professional veterinary or aquarium-care advice.
