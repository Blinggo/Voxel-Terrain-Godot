# Project Continuation

Last updated: 2026-11-07
Milestone: **M0.2 complete pending review** (M0.1 reviewed and accepted).
M1 not started.

Read this first, then `Documentation/Architecture/OVERVIEW.md`.

---

## 1. Current state

The project opens, loads Voxel Tools, generates seeded procedural blocky terrain
on worker threads, streams it around a camera, and renders it in 3D.

- 151 automated checks: 17 core + 24 voxel + 24 reliability + 41 perf (headless)
  + 45 UI input (needs a display), plus two verified screenshot captures.
  `./tests/run_tests.sh` runs windowed when a display exists, headless otherwise.
- Verified end to end on **Linux x86_64** with software Vulkan.
- **Android: confirmed running on a physical device** from the Godot Editor —
  terrain, streaming, touch camera, regenerate, random seed, default-seed
  persistence, same-seed reproducibility, and touch editing of all four
  numerical fields.
- **An ARM64 release APK has been exported and statically verified but never
  installed.** Signature, ABI, packaged extension and permissions all check out;
  runtime behaviour of the release build is unknown.
- Windows: never exported or run.
- Generation throughput: ~36 µs per 16³ block, ~27,700 blocks/s single-threaded, GDScript.

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

---

## 3. Files and responsibilities

```
project.godot                       mobile renderer, landscape, touch→mouse emulation off
icon.svg

scenes/main.tscn                    World, camera + VoxelViewer, sun, environment, debug overlay

src/core/noise/noise_source.gd      abstract pure/thread-safe 2D field contract
src/core/noise/fast_noise_lite_source.gd  FastNoiseLite implementation (seeded once)
src/core/terrain/terrain_height_field.gd  noise → surface height per column
src/core/terrain/block_palette.gd        type ids, colours, soil depth, classify()

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
tests/suites/core_suite.gd          17 checks, engine-light
tests/suites/voxel_suite.gd         24 checks, live scene
tests/suites/ui_input_suite.gd      45 checks, touch/mouse numeric input (needs a display)
tests/suites/reliability_suite.gd   24 checks, palette snapshot stability
tests/suites/perf_suite.gd          41 checks, instrumentation arithmetic and schema
tests/capture_screenshot.gd|.tscn   rendered PNG proof (needs a display)
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
- M0.2: Android release APK exported and verified (see
  `Milestones/M00_02_ANDROID_VALIDATION.md` §3); performance overlay with F4
  toggle; screenshot harness with real exit codes; palette snapshot for worker
  thread safety.

---

## 5. Known limitations

1. **Single-colour cubes.** A grass voxel's side faces are green; layered
   materials only appear where the surface is cut deeper than `soil_depth`.
   Fixing this properly needs a multi-material cube model.
2. **Height field only.** No caves, overhangs, cliffs or floating geometry — by
   design for M0.1. The current interface (`get_surface_height`) cannot express
   them; a volume query is the future shape.
3. **Full rebuild on parameter change.** Necessary given Voxel Tools' caching
   (ADR-0004). Costs a re-stream, visible as "loading…".
4. **Vertical streaming limited to ±64 voxels** around the camera. Terrain
   outside that band is neither generated nor meshed.
5. **`updated_blocks` statistic is dead** in Voxel Tools 1.7; progress is
   reported via `is_area_meshed` around the viewer instead.
6. **No collisions generated.** Fine until something needs to stand on the ground.
7. **GDScript generation cost.** 36 µs/block is good for script, but a native
   generator would be far faster; this is the known ceiling until a bottleneck is
   proven.
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

---

## 6. Continuing development

### 6.1 Exact current state

Everything in `src/` is implemented and covered by tests. There are no stubs, no
disabled feature flags, and no known-incomplete code paths. What is unproven is
external to the code: the exported release APK has never been run on a device.

| Proven | Unproven |
|---|---|
| 151 automated checks on Linux x86_64, software Vulkan | release APK at runtime |
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
# suites: core | voxel | reliability | perf | ui | all

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

### 6.3 Next steps (M1 not started — awaiting approval)

1. **Run the exported APK on the device.** This is the only outstanding
   acceptance test for M0.2 and it is one install away. Step-by-step checklist:
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
