# Project Continuation

Last updated: 2026-11-07
Milestone: **M2 complete pending review** (M0.1, M0.2 and M1 reviewed and accepted).
The full M2 record is `Milestones/M02_ADVANCED_GEOGRAPHICAL_FORMATIONS.md`.

Read this first, then `Documentation/Architecture/OVERVIEW.md`.

---

## 1. Current state

The project opens, loads Voxel Tools, generates seeded procedural blocky terrain
on worker threads, streams it around a camera, and renders it in 3D.

The terrain is a **geographic** one. Twelve registered modules run on a node grid
and the live Voxel Tools generator is driven by their output. A world shows oceans,
shelves, coastlines with bays and peninsulas, plains, hills, island groups, mountain
systems with ridges and foothills, valley networks with passes, and stepped plateaus
— placed by a lightweight plate model rather than by noise alone. It regenerates
identically from the same seed, and the overlay reports the terrain type and the raw
fields under the viewer.

- **274 automated checks**: 17 core + 57 generation + **63 M2** + 27 voxel + 24
  reliability + 41 perf (headless) + 45 UI input (needs a display), plus verified
  screenshot captures and three generated maps. `./tests/run_tests.sh` runs windowed
  when a display exists, headless otherwise.
- The M1 generation suite was silently skipping 12 checks (an over-argumented
  `check_equal` call aborts a GDScript call without failing the run). Fixed in M2:
  `check_equal` takes an optional `detail`, all 57 checks execute, all pass, and the
  run now asserts zero `SCRIPT ERROR` lines.
- M2 additions: `tectonics`, `archipelago`, `coast_detail`, `landmass`, `plateaus`,
  `valleys`; `mountainness` rebuilt (v2) as structural bands with noise relief;
  `surface` rebuilt (v2) as a six-step composition. `generation_version` is now 2, so
  **M1 terrain is not reproduced** — deliberate, and recorded.
- Verified end to end on **Linux x86_64** with software Vulkan.
- **Android: confirmed running on a physical device** from the Godot Editor —
  terrain, streaming, touch camera, regenerate, random seed, default-seed
  persistence, same-seed reproducibility, and touch editing of all four
  numerical fields.
- **An ARM64 release APK has been exported and statically verified but never
  installed.** Signature, ABI, packaged extension and permissions all check out;
  runtime behaviour of the release build is unknown.
- Windows: never exported or run.
- Generation throughput: **38.2 µs** per 16³ block in the project benchmark
  (M1: 43.9 µs, M0.1: 36 µs), ~26,000 blocks/s single-threaded, GDScript. On a fresh
  contiguous region a block costs **107 µs warm / 196 µs cold**, which is the number
  streaming actually pays. Streaming region at view distance 128: **0.13 s**
  (M1: 0.18 s, M0.2: 0.16 s). Per-node cost rose from an estimated ~3.3 µs to a
  measured 16.6 µs, because six new fields now run per node.

- **Known visual gaps** (M2): ranges can follow a near-straight plate boundary;
  plateau coverage varies from 0.8 % to 6.8 % of land depending on seed. The sea
  plane is a flat translucent placeholder — it now follows the camera, which is what
  made the ocean appear in the M2 captures at all (the plane used to be pinned to the
  world origin).

Nothing is stubbed. There are no placeholder scripts and no disabled features
hiding behind flags except those explicitly listed as out of scope.

---

## 2. Technology decisions (full detail in `Decisions/`)

| ADR | Decision |
|---|---|
| 0001 | Stock Godot 4.7.2 + Voxel Tools 1.7 **GDExtension** (`v1.7x` release, not the custom-module `v1.7` build) |
| 0002 | Blocky **type-id** voxels with `VoxelMesherBlocky`, not SDF/Transvoxel |
| 0003 | Surface = pure function of world `(x, z)` behind a `NoiseSource` interface; no global RNG |
| 0004 | Changing seed/parameters **recreates** the `VoxelTerrain` node (Voxel Tools has no public cache-invalidate API) |
| 0005 | Mobile-first defaults: 128-voxel radius, vertical ratio 0.5, no collisions, no GPU generation |
| 0006 | Extension binaries trimmed; now **Linux x86_64 only** (editor + template_release). Windows and Android binaries were removed on request during M0.2 pre-work to keep the download small — restore them by unzipping `GodotVoxelExtension.zip` over `addons/zylann.voxel/bin/`. Project: 61 MB → 26 MB |
| 0007 | No autoload singletons; the scene root wires world ↔ camera ↔ debug panel |
| 0008 | Numerical fields are a custom `NumericField` (`LineEdit` + step buttons), not `SpinBox`, because stock `SpinBox` ignores `InputEventScreenTouch` when mouse emulation is off |
| 0009 | Performance instrumentation reports only measurements that exist: frame window, Godot memory, pass-through Voxel Tools statistics, and generic named phase timings |
| 0010 | Generation reads a `BlockPalette` snapshot taken before worker threads start; the generator and the blocky library share it |
| 0011 | Terrain is a pipeline of registered **single-field modules** with declared dependencies; one registration point, deterministic order, independent testability. Supersedes ADR-0003's implementation, not its rule |
| 0012 | Deterministic randomness is hand-written hashing in **32-bit lanes** (FNV-1a + MurmurHash3), because GDScript cannot write hex literals ≥ 2^63 or shift negatives |
| 0013 | Regional fields are evaluated on a **node grid** 8 voxels apart and interpolated; detail is a bulk per-column term; nodes are cached behind a mutex |
| 0014 | Tectonic influence is an **analytic jittered-Voronoi plate lattice**, not a simulated or persisted plate map: deterministic, independently sampleable, one bounded cache |
| 0015 | Mountain ranges are **structural bands** along tectonic boundaries times noise relief, plus a massif term, an apron for foothills and a rift cut — not layered ridged noise |
| 0016 | Any field that depends on a **discrete regional choice** must blend across that choice (tie-window blending) or be built so the choice is well separated; caches may never change a value |
| 0017 | Landforms are composed in a **fixed order over one shared `landmass` signal**: plateau *blends*, valley *carves last*, carve floored at the regional base, both faded where they overlap |

---

## 3. Files and responsibilities

```
project.godot                       mobile renderer, landscape, touch→mouse emulation off
icon.svg

scenes/main.tscn                    World, camera + VoxelViewer, sun, environment, debug overlay

src/core/generation/terrain_hash.gd        deterministic coordinate hashing
src/core/generation/generation_context.gd  seed + versions + frozen config; per-module noise
src/core/generation/generation_module.gd   module contract (one output field, declared deps)
src/core/generation/generation_registry.gd registration + dependency resolution
src/core/generation/generation_engine.gd   node-grid execution, cache, interpolation, bounds
src/core/generation/terrain_generation_stack.gd  the one place modules are registered
src/core/generation/geographic_surface.gd  what the voxel layer sees (heights, fields, classify)
src/core/generation/modules/continentalness_module.gd  domain-warped continent field
src/core/generation/modules/elevation_module.gd        three-band broad elevation
src/core/generation/modules/tectonics_module.gd        M2: jittered-Voronoi plates, boundary character, tie blend
src/core/generation/modules/archipelago_module.gd      M2: island groups and lone islands (offshore only)
src/core/generation/modules/coast_module.gd            M2: bays, peninsulas, shoreline crinkle
src/core/generation/modules/landmass_module.gd         M2: the composed land signal everyone reads
src/core/generation/modules/plateau_module.gd          M2: plateau mask + terrace() shelves
src/core/generation/modules/valley_module.gd           M2: valley network, tributaries, basins, passes
src/core/generation/modules/mountain_module.gd         v2: structural band + massif + apron + ribs
src/core/generation/modules/hills_module.gd            shaped hills, damped under mountains
src/core/generation/modules/surface_module.gd          v2: depth, land base, relief, plateau blend, valley carve, coast
src/core/generation/modules/detail_module.gd           per-column fine roughness
src/core/terrain/block_palette.gd          type ids, colours, soil depth, classify()

src/voxel/terrain_block_generator.gd     VoxelGeneratorScript adapter (no geography)
src/voxel/blocky_library_builder.gd      library (slot 0 = air) + mesher + material, baked
src/voxel/voxel_terrain_builder.gd       VoxelTerrain + VoxelFormat factory

src/world/world_config.gd           all generation parameters (Resource)
src/world/voxel_world.gd            terrain lifetime, assembly, rebuild(), get_status()
src/world/main_scene.gd             wiring only; applies regeneration requests

src/camera/orbit_camera.gd          orbit/zoom/pan for mouse and touch
src/debug/numeric_field.gd          touch-capable numeric entry: LineEdit + step buttons, validation
src/debug/performance_sampler.gd    frame/memory/voxel/section measurements for the overlay
src/debug/debug_panel.gd            parameter widgets + status; emits regenerate_requested

tests/test_runner.gd|.tscn          suite dispatcher, exit codes, watchdog
tests/test_support.gd               PASS/FAIL recorder
tests/suites/core_suite.gd          17 checks, engine-light (surface contract, seams, threads)
tests/suites/generation_suite.gd    57 checks, determinism + fields + module system + integration
tests/suites/m2_generation_suite.gd  63 checks, M2 determinism, continuity, geography, integration, perf
tests/suites/voxel_suite.gd         27 checks, live scene (incl. the sea-plane regression)
tests/suites/ui_input_suite.gd      45 checks, touch/mouse numeric input (needs a display)
tests/suites/reliability_suite.gd   24 checks, palette snapshot stability
tests/suites/perf_suite.gd          41 checks, instrumentation arithmetic and schema
tests/capture_screenshot.gd|.tscn   rendered PNG proof (needs a display); --center=x,z frames a landmark
tests/render_map.gd                 hillshaded top-down map of the surface (geography tuning tool)
tests/benchmark.gd|.tscn            throughput + streaming timings
tests/run_tests.sh                  CI entry point (+ optional --screenshot), propagates failures

export_presets.cfg                  Android ARM64 release preset (arm64-v8a only)
artifacts/android/                  exported, signed, verified release APK + sha256

Documentation/                      this documentation set
```

---

## 4. Completed work

- Environment verified for real: engine version, extension variant, binary
  architectures, and actual class registration.
- Layered foundation with a one-way dependency graph; core contains no engine
  or Voxel Tools types.
- Custom `VoxelGeneratorScript` producing seeded, deterministic, seam-free
  terrain, safe under concurrent generation.
- Blocky mesher with a code-built, baked library and vertex-coloured material.
- Streaming via the camera's `VoxelViewer`; Voxel Tools does the scheduling.
- Debug overlay: seed / height / frequency / view distance, regenerate, random
  seed, live status, `R` and `F3` shortcuts.
- M0.2: the four numerical fields are editable by touch. Root cause was that
  `SpinBox` and `LineEdit` ignore raw `InputEventScreenTouch` while `Button`
  handles it — see `Milestones/M00_02_ANDROID_INPUT_FIX.md` and ADR-0008.
- Inspection camera: orbit, zoom, pan, on mouse and touch code paths.
- Automated suites (151 checks) plus screenshot, benchmark and export tooling.
- M1: modular generation pipeline (`src/core/generation/`), deterministic hashing,
  two-resolution sampling with a node cache, five geographic fields plus a detail
  term, coastal softening, classification, sea plane, module/field/statistics
  reporting in the overlay, and 45 new checks. See
  `Milestones/M01_DETERMINISTIC_TERRAIN_FOUNDATION.md`.
- M2: six new fields (tectonics, archipelago, coast_detail, landmass, plateaus,
  valleys), `mountainness` and `surface` rebuilt as version 2, two real continuity
  defects found and fixed (triple-point swap, coincident plate sites), plateau
  terracing, valley carving with a base-level floor and plateau fade, island and
  coastline shaping over an unchanged sea-level contract, eleven new configuration
  parameters, two new overlay field lines, and 63 new checks. See
  `Milestones/M02_ADVANCED_GEOGRAPHICAL_FORMATIONS.md`.
- M0.2: Android release APK exported and verified (see
  `Milestones/M00_02_ANDROID_VALIDATION.md` §3); performance overlay with F4
  toggle; screenshot harness with real exit codes; palette snapshot for worker
  thread safety.

---

## 5. Known limitations

1. **Single-colour cubes.** A grass voxel's side faces are green; layered
   materials only appear where the surface is cut deeper than `soil_depth`.
   Fixing this properly needs a multi-material cube model.
2. **Height-field world.** No caves, overhangs or floating geometry — by design.
   `get_surface_height`/`sample_block_heights` cannot express them; a volume query
   is the future interface shape. M1 made the *geography* rich, not the geometry.
3. **Full rebuild on parameter change.** Necessary given Voxel Tools' caching
   (ADR-0004). Costs a re-stream, visible as "loading…".
4. **Vertical streaming limited to ±64 voxels** around the camera. Terrain
   outside that band is neither generated nor meshed.
5. **`updated_blocks` statistic is dead** in Voxel Tools 1.7; progress is
   reported via `is_area_meshed` around the viewer instead.
6. **No collisions generated.** Fine until something needs to stand on the ground.
7. **GDScript generation cost.** ~44 µs/block in the benchmark, ~126 µs/block in
   a scattered-block probe. Far richer terrain than M0.1 for ~20-30 % more time in
   the benchmark, but a native generator would still be much faster; this is the
   known ceiling until a device measurement proves a bottleneck.
8. **The exported release APK is unrun.** Editor runtime on the device is
   confirmed; an exported build has never been installed. This is the one
   outstanding acceptance test for M0.2.
9. **Streaming block counts are not available** in Voxel Tools 1.7x, so the
   overlay cannot show loaded or pending block counts; the four timing counters
   and the dropped counters are all the extension offers.
10. **Overlay memory is Godot-side only.** Device RSS needs `adb shell dumpsys
    meminfo`.
11. **Number entry is per-field, committed on Enter / focus loss / Regenerate.**
   There is no live update while typing; that is deliberate so a half-typed value
   cannot reach the world configuration.
12. **Orientation changed to landscape** (`DisplayServer.SCREEN_LANDSCAPE = 0`);
   the old value was portrait despite a landscape comment. Needs a device check.
13. **M1 terrain characteristics** — gentle slopes read as terraces (integer column
    heights); low coastal plains are large on some seeds (the price of removing
    coastal scarps); mountains are noise-driven belts, not tectonic simulation.
14. **M1 rebuild cost** measured 8.8–26.7 ms on this machine (module construction)
    against ~0.7 ms in M0.2; it is a one-off on the main thread, but it is the
    number to watch on a phone.
15. **Android/Windows for M1 are untested.** Every M1 number in this file is Linux
    x86_64 with software Vulkan. This is the milestone's biggest evidence gap.
16. **M2 ranges can be straight.** Where a plate boundary dominates, a range follows
    a warped Voronoi bisector; the warp bends it but does not hide it in every seed.
17. **M2 mountain fill ratio is still 0.65–0.92** of the bounding box. Ranges read as
    ranges inside a province, not as thin chains.
18. **M2 plateau coverage varies from 0.8 % to 6.8 % of land** between seeds; the
    plateau field is a thresholded noise field and some seeds have almost none.
19. **Scattered single-cell seafloor dips** appear as dark specks in open water on
    the hillshaded maps. Cosmetic, not a discontinuity (continuity is tested).
20. **No water simulation.** The sea is one flat translucent plane (it now follows
    the camera instead of sitting at the world origin) and nothing drains inland, so
    carved land is held above sea level on purpose.
21. **Per-node generation cost rose** from ~3.3 µs (M1, estimated) to 16.6 µs
    (measured). The right next step if more fields are added is to reduce noise
    *calls* per node, not to add caches.
22. **M2 is untested on Android and Windows**, exactly as M1 was. The Android
    editor checklist is in the M2 milestone document, §16.

---

## 6. Continuing development

### 6.1 Exact current state

Everything in `src/` is implemented and covered by tests. There are no stubs, no
disabled feature flags, and no known-incomplete code paths. What is unproven is
external to the code: the exported release APK has never been run on a device.

| Proven | Unproven |
|---|---|
| 274 automated checks on Linux x86_64, software Vulkan | release APK at runtime |
| M1 geographic fields, determinism, module system | M1/M2 behaviour on Android/Windows |
| M2 formations visible in rendered 3D terrain (screenshots) | M2 frame rate on hardware |
| M2 determinism, continuity, geography and configurability (63 checks) | sustained-streaming memory over a long flight |
| terrain generation, streaming, seams, rebuild determinism | release-build extension loading |
| touch/mouse numerical input (synthetic events) | device process memory and thermals |
| Android Editor run on hardware (owner) | any second Android device |
| ARM64 APK exported, signed, statically verified | Windows build |

### 6.2 Commands

```bash
# tests (windowed if DISPLAY is set, so the UI suite runs)
./tests/run_tests.sh
./tests/run_tests.sh --screenshot      # adds two verified PNG captures

# single suite
godot --headless --path . res://tests/test_runner.tscn -- --suite=voxel
# suites: core | generation | m2 | voxel | reliability | perf | ui | all

# run the game
godot --path .
#   F3 hides the overlay, F4 toggles profiling, R regenerates

# export the ARM64 release APK
#   1. restore the Android extension binary (trimmed by ADR-0006):
unzip GodotVoxelExtension.zip 'addons/zylann.voxel/bin/libvoxel.android.*' -d .
#   2. keystore comes from the environment, never from the preset:
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/release.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=alias
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=password
#   3. export
godot --headless --path . --export-release "Android ARM64" build/android/app.apk

# verify what was actually built
apksigner verify --verbose build/android/app.apk
aapt2 dump badging build/android/app.apk | head -5
unzip -l build/android/app.apk | grep -E "lib/|assets/src"
```

A verified build from this environment is kept in
`artifacts/android/procedural-world-arm64.apk` (sha256 in `SHA256SUMS.txt`). It is
signed with a throwaway key: uninstall any differently-signed build first.

### 6.3 Next steps (M2 complete, awaiting approval)

**Immediate: review M2.** The documentary artifact is
`Milestones/M02_ADVANCED_GEOGRAPHICAL_FORMATIONS.md`; the most important things to
look at are §10 (visual evidence and what it does and does not prove), §11 (the 63
executed checks) and §13 (performance, including the honest per-node regression).

**Then, for M3, in value order** (detail in the M2 milestone doc §16):

1. **Water that follows the terrain** — the single biggest visual gap. Sea-level
   awareness for carved basins and valley floors, and a water surface that is not one
   flat plane 2048 voxels across.
2. **Rivers from the existing valley field** — drainage direction from the composed
   surface gradient; no full simulation. `valleys` already marks the network.
3. **Biome / strata materials** — `BlockPalette.classify()` is the seam, and the M2
   fields (`mountainness`, `plateaus`, `valleys`, `tectonics`) are the inputs it
   was waiting for.
4. **Device performance pass** before adding more per-node cost: six new fields took
   the node from ~3.3 µs to 16.6 µs; measure on the phone before M3 adds more, and
   prefer reducing noise calls per node over adding caches.

### 6.4 Older next steps (M0.2 era, still valid where not superseded)

1. **Run the exported APK on the device.** Still the only outstanding acceptance
   test for M0.2 (the APK in `artifacts/android/` is the M0.2 build; M1 did not
   regenerate it, as the milestone required). Step-by-step checklist:
   `Milestones/M00_02_ANDROID_TESTING_CHECKLIST.md`.
2. **Then measure on the device**, not on the desktop: the overlay reports frame
   time and Godot memory, and `adb shell dumpsys meminfo` reports process
   memory. Decide whether GDScript generation is the bottleneck or whether
   meshing/upload dominates. Everything after this point depends on that answer.
3. **Terrain quality, still within the height-field model.** Domain warping,
   ridged noise, altitude/slope-based material selection (rock on steep faces is
   cheap and would immediately expose the strata already in the data). Each is a
   new `NoiseSource`/height-field implementation, not a rewrite — and each should
   report its cost through `record_section()`.
4. **Multi-material blocky models** so a grass block can show a dirt side,
   removing limitation 1.
5. **Live parameter regeneration without a full rebuild**, using `VoxelTool`
   over the current view region, if the rebuild cost proves annoying in practice.
6. **Then** open the door to volume-based generation (caves/overhangs), which is
   where the climate/hydrology/biome architecture finally makes sense. That is a
   deliberate interface change, not a small addition — decide it explicitly.

Deliberately deferred, and why: LOD (`VoxelLodTerrain`) competes with a streaming
budget that has not yet been measured on a device; world saving and collision
meshing both cost time and solve no current problem.
