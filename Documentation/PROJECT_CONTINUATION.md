# Project Continuation

Last updated: 2026-11-06
Milestone: **M0.1 complete pending review** — M0.2 not started.

Read this first, then `Documentation/Architecture/OVERVIEW.md`.

---

## 1. Current state

The project opens, loads Voxel Tools, generates seeded procedural blocky terrain
on worker threads, streams it around a camera, and renders it in 3D.

- 41/41 automated checks pass headless in ~3 s (`./tests/run_tests.sh`).
- Verified end to end on **Linux x86_64** only, with software Vulkan.
- Android and Windows: **never exported or run**. Binary present, behaviour unknown.
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
| 0006 | Extension binaries trimmed to Linux x86_64 + Windows x86_64 + Android arm64 (129 MB → 58 MB) |
| 0007 | No autoload singletons; the scene root wires world ↔ camera ↔ debug panel |

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
src/debug/debug_panel.gd            parameter widgets + status; emits regenerate_requested

tests/test_runner.gd|.tscn          suite dispatcher, exit codes, watchdog
tests/test_support.gd               PASS/FAIL recorder
tests/suites/core_suite.gd          17 checks, engine-light
tests/suites/voxel_suite.gd         24 checks, live scene
tests/capture_screenshot.gd|.tscn   rendered PNG proof (needs a display)
tests/benchmark.gd|.tscn            throughput + streaming timings
tests/run_tests.sh                  CI entry point (+ optional --screenshot)

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
- Inspection camera: orbit, zoom, pan, on mouse and touch code paths.
- Automated suites (41 checks) plus screenshot and benchmark tooling.

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
8. **Unverified platforms.** See test report §6.

---

## 6. Next steps for M0.2 (not started — awaiting approval)

Suggested order, smallest useful increments first. Do not begin any of this
before M0.1 is reviewed.

1. **Prove Android before adding features.** Set up the Android SDK/JDK and
   export templates, build an ARM64 APK, run it on a device, and record frame
   time, memory and touch behaviour. Until this exists, "mobile-first" is an
   aspiration. This is the highest-value next task and it validates every design
   choice above.
2. **Measure before optimising.** Add frame-time and memory instrumentation to
   the debug overlay. Only then decide whether GDScript generation is the
   bottleneck, or whether meshing/upload dominates.
3. **Terrain quality, still within the height-field model.** Domain warping,
   ridged noise, altitude/slope-based material selection (rock on steep faces is
   cheap and would immediately expose the strata that are already in the data).
   Each of these is a new `NoiseSource`/height-field implementation, not a
   rewrite.
4. **Multi-material blocky models** so a grass block can show a dirt side,
   removing limitation 1.
5. **Live parameter regeneration without a full rebuild**, using `VoxelTool`
   over the current view region, if the rebuild cost proves annoying in practice.
6. **Then** open the door to volume-based generation (caves/overhangs), which is
   where the climate/hydrology/biome architecture finally makes sense. That is a
   deliberate interface change, not a small addition — decide it explicitly.

Deliberately deferred, and why: LOD (`VoxelLodTerrain`) competes with the
streaming budget that Android has not yet been measured against; world saving and
collision meshing both cost time and solve no M0.2 problem.
