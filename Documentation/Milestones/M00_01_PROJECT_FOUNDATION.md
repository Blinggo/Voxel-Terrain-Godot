# M0.1 — Project Foundation and Early Voxel Integration

Date: 2026-11-06
Status: implemented, tested, awaiting review

This document records what was verified about the environment, what was built,
and how the Voxel Tools integration is configured. Test results and honest gaps
are in `M00_01_TEST_REPORT.md`.

---

## 1. Environment verification

Everything below was executed on the development machine, not assumed.

### 1.1 Host

| Item | Value |
|---|---|
| OS | Debian GNU/Linux 13 (trixie), x86_64 |
| CPU / RAM | 2 vCPU / 1.9 GiB |
| GPU | none; Mesa **lavapipe** software Vulkan (`llvmpipe`, LLVM 19.1.7) |
| Display | none; `Xvfb :99` used for any run that needs a rendering device |

No physical GPU and no Android device are present. This constrains what could be
verified — see section 6 of the test report.

### 1.2 Godot

Obtained from the official release, Linux x86_64 build:

```
Godot_v4.7.2-stable_linux.x86_64 --version
→ 4.7.2.stable.official.ed1daf0bf
```

Matches the mandated Godot 4.7.2.

### 1.3 Voxel Tools

Release line matters, so this was checked rather than assumed. The Voxel Tools
`v1.7` release is a **custom engine build** with the module compiled in; the
`v1.7x` release is the **standalone GDExtension**. The brief excludes the
former, so `v1.7x` was used:

```
GodotVoxelExtension.zip  (release tag v1.7x, "Voxel Tools GDExtension 1.7 for Godot 4.5+")
→ addons/zylann.voxel/voxel.gdextension
   entry_symbol          = "voxel_library_init"
   compatibility_minimum = "4.4.1"
```

`compatibility_minimum = 4.4.1` places 4.7.2 inside the supported range, but the
extension was still verified to actually load (section 1.5) rather than inferred
from the version string.

### 1.4 Native libraries present and their architectures

Inspected with `file` and `sha256sum`, after trimming (ADR-0006):

| Library | Architecture | Kept for |
|---|---|---|
| `libvoxel.linux.editor.x86_64.so` | ELF 64-bit x86-64 | development, CI |
| `libvoxel.linux.template_release.x86_64.so` | ELF 64-bit x86-64 | Linux export |
| `libvoxel.windows.editor.x86_64.dll` | PE32+ x86-64 | Windows (secondary target) |
| `libvoxel.windows.template_release.x86_64.dll` | PE32+ x86-64 | Windows export |
| `libvoxel.android.editor.arm64.so` | ELF 64-bit ARM aarch64 | Android (primary target) |
| `libvoxel.android.template_release.arm64.so` | ELF 64-bit ARM aarch64 | Android export |

Removed from the upstream 129 MB archive: macOS universal, iOS arm64, Linux
arm64, Android x86_64 (58 MB remains). The `.gdextension` file itself is
unmodified. See ADR-0006 for how to restore them.

### 1.5 Does the extension actually load?

**Yes** — verified, with one trap worth recording.

A project that has never been scanned will report every Voxel class as missing.
The GDExtension is only registered into `ClassDB` after the project has been
imported once, which is what generates `.godot/extension_list.cfg`:

```
# first run on a fresh project
VoxelTerrain -> false        # ← misleading: not an incompatibility
...
# after: godot --headless --path . --import
$ cat .godot/extension_list.cfg
res://addons/zylann.voxel/voxel.gdextension
# running again
VoxelTerrain -> true
VoxelGeneratorScript -> true
VoxelMesherBlocky -> true
...
```

So the test order is: import, then assert. A first-run failure of this kind must
not be reported as an unsupported extension.

### 1.6 Supported platforms (binary-level)

android arm64 ✔, windows x86_64 ✔, linux x86_64 ✔ (present and correct
architecture). **Deployment to Android was not performed** — no Android SDK, no
JDK, no export templates and no device in this environment. Android support is
therefore *available in principle and unverified in practice*.

---

## 2. Project structure

```
procedural-world/
├── project.godot
├── icon.svg
├── addons/zylann.voxel/            Voxel Tools 1.7 GDExtension (trimmed)
├── scenes/
│   └── main.tscn                   the only game scene
├── src/
│   ├── core/                       ← no Voxel Tools, no nodes
│   │   ├── noise/
│   │   │   ├── noise_source.gd              abstract, pure, thread-safe field
│   │   │   └── fast_noise_lite_source.gd    FastNoiseLite implementation
│   │   └── terrain/
│   │       ├── terrain_height_field.gd      surface height per column
│   │       └── block_palette.gd             type ids, colours, depth rule
│   ├── voxel/                      ← Voxel Tools integration only
│   │   ├── terrain_block_generator.gd       VoxelGeneratorScript adapter
│   │   ├── blocky_library_builder.gd        library + mesher + material
│   │   └── voxel_terrain_builder.gd         VoxelTerrain factory
│   ├── world/
│   │   ├── world_config.gd                  all generation parameters
│   │   ├── voxel_world.gd                   lifetime, assembly, rebuild, status
│   │   └── main_scene.gd                    wiring only
│   ├── camera/orbit_camera.gd      mouse + touch inspection camera
│   └── debug/debug_panel.gd        parameters, status, regenerate request
├── tests/
│   ├── test_runner.gd/.tscn        headless entry point, exit codes
│   ├── test_support.gd             assertion recorder
│   ├── suites/core_suite.gd        17 checks, no engine nodes
│   ├── suites/voxel_suite.gd       24 checks, live terrain
│   ├── capture_screenshot.gd/.tscn render proof (needs a display)
│   ├── benchmark.gd/.tscn          throughput + streaming timing
│   └── run_tests.sh                CI entry point
└── Documentation/
    ├── Architecture/OVERVIEW.md
    ├── Milestones/
    │   ├── M00_01_PROJECT_FOUNDATION.md   (this file)
    │   ├── M00_01_TEST_REPORT.md
    │   └── screenshots/                   rendered evidence
    ├── Decisions/ADR-0001 .. ADR-0007
    └── PROJECT_CONTINUATION.md
```

22 GDScript/scene files. No empty placeholder modules: every file listed is
loaded by the running project or by a test.

---

## 3. Implemented architecture

Dependency direction is one-way: `world` → `voxel` → `core`, with `core` free of
both. Details in `Documentation/Architecture/OVERVIEW.md`.

The generation stack, innermost first:

```
WorldConfig            seed, base height, amplitude, frequency, octaves, view distance
   ↓
FastNoiseLiteSource    NoiseSource implementation (seeded, pure, thread-safe)
   ↓
TerrainHeightField     get_surface_height(x, z) — the only thing the voxel layer asks
   ↓
BlockPalette           classify(y, surface) → air / grass / dirt / stone
   ↓
TerrainBlockGenerator  VoxelGeneratorScript: writes VoxelBuffer type ids
   ↓
VoxelTerrain           Voxel Tools: streaming, threading, blocky meshing
```

Each arrow is a seam that can be replaced independently. Replacing the terrain
algorithm means a new `NoiseSource` or a new height field; replacing the voxel
backend means editing `src/voxel/`; neither touches the other.

Deliberate non-goals in M0.1: no climate/hydrology/biome system, no caves, no
LOD, no world saving, no collision meshing, no chunk system of our own.

---

## 4. Voxel Tools integration

### 4.1 Node configuration

`VoxelTerrainBuilder.create_terrain()` produces:

| Setting | Value | Why |
|---|---|---|
| `VoxelTerrain` (not `VoxelLodTerrain`) | — | fixed-detail streaming; LOD is out of scope for M0.1 |
| `format` → `TYPE` depth | `DEPTH_16_BIT` | blocky mesher accepts only 8/16-bit; pinned so it never depends on a default |
| `generator` | `TerrainBlockGenerator` | our adapter |
| `mesher` | `VoxelMesherBlocky` | required by the milestone |
| `material_override` | `StandardMaterial3D`, vertex colour as albedo | the mesher emits per-vertex colours, no textures |
| `mesh_block_size` | 16 | smaller uploads, friendlier to mobile GPUs |
| `generate_collisions` | false | no physics in M0.1 (ADR-0005) |
| `use_gpu_generation` | false | compute is not a mobile baseline |
| `max_view_distance` | `WorldConfig.view_distance_voxels` (128) | streaming radius |
| `VoxelViewer.view_distance_vertical_ratio` | 0.5 | heightmap world wastes work on a full cube |

`VoxelViewer` is a child of the camera and registers itself with the Voxel Tools
engine globally — it does not need to be a child of the terrain.

Verified at runtime (1.7 defaults confirmed empirically, not assumed):
`data_block_size = 16`, `mesh_block_size = 16`.

### 4.2 Block library

Built in code by `BlockyLibraryBuilder` rather than saved as a `.tres`, so the
palette is the single source of truth for both ids and colours:

| Slot | Model | Meaning |
|---|---|---|
| 0 | `VoxelBlockyModelEmpty` | air — **must** be 0, asserted in code |
| 1 | cube, grass colour | `BlockPalette.GRASS` |
| 2 | cube, dirt colour | `BlockPalette.DIRT` |
| 3 | cube, stone colour | `BlockPalette.STONE` |

`bake()` is called explicitly before the mesher is created; the mesher reads only
baked data.

### 4.3 Generation contract

`_generate_block(out_buffer, origin_in_voxels, lod)`:

- reads one noise sample per **column**, then fills with at most three
  `fill_area` calls (stone, dirt, grass) instead of per-voxel `set_voxel`;
- clamps every range to the buffer, so a block straddling the surface, or buried
  far below it, is handled by the same code path;
- mutates no member state, and is therefore safe to call concurrently from the
  worker pool;
- ignores `lod` (fixed-detail terrain only passes 0).

---

## 5. Configuration

All parameters live in `WorldConfig` (`src/world/world_config.gd`), editable in
the inspector on the `World` node and at runtime in the debug overlay.

| Property | Default | Meaning |
|---|---|---|
| `world_seed` | 1337 | drives all noise; same seed ⇒ same world |
| `base_height` | 24.0 | average surface height, voxels |
| `terrain_height` | 26.0 | max deviation above/below `base_height`, voxels |
| `terrain_frequency` | 0.008 | noise cycles per voxel |
| `fractal_octaves` | 4 | fBm octaves; 1 disables fractal accumulation |
| `view_distance_voxels` | 128 | streaming radius |

`BlockPalette` additionally exposes `soil_depth` (dirt thickness, default 4) and
the three block colours.

Changing the seed, height or frequency rebuilds the world (ADR-0004).

---

## 6. How to run

```bash
# open in the editor
godot --path procedural-world

# run the game directly
godot --path procedural-world res://scenes/main.tscn

# tests (headless, CI-friendly; exit code 0 = pass)
godot --headless --path procedural-world res://tests/test_runner.tscn -- --suite=all
./tests/run_tests.sh

# render proof (needs a rendering device)
xvfb-run -s "-screen 0 1280x720x24" ./tests/run_tests.sh --screenshot

# performance numbers
godot --headless --path procedural-world res://tests/benchmark.tscn
```

Controls: left-drag (or one finger) orbits · wheel or pinch zooms · middle/right
drag pans · `R` regenerate · `F3` hide the overlay.
