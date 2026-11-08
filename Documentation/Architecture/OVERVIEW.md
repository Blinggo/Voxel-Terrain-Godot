# Architecture Overview

## Principle

One direction of dependency, no cycles:

```
WorldConfig  ──►  core/generation (modules, hashing, sampling)  ──►  voxel adapter  ──►  Voxel Tools
      │                        ▲                                          │
      │                        └──── contains no engine nodes ────────────┘
      └──► core/terrain (palette) ─────────────────────────────────────────┘
```

`src/core/` never references Voxel Tools, nodes, the scene tree, or the
renderer. `src/voxel/` never contains terrain mathematics. `src/world/` owns
lifetime and wiring. `src/debug/` and `src/camera/` are consumers that speak to
the world only through small, explicit interfaces.

That is what makes replacing the terrain algorithm a local change: the voxel
layer only requires something shaped like `get_surface_height(x, z)` plus a
block-at-a-time height query, and M1 replaced everything behind that contract
without touching Voxel Tools integration.

## Layers

### `src/core/generation/` — the terrain pipeline (M1 pipeline, M2 geography)

| File | Role |
|---|---|
| `terrain_hash.gd` | Deterministic coordinate hashing: FNV-1a + MurmurHash3 in 32-bit lanes (ADR-0012). |
| `generation_context.gd` | Seed, generation version, frozen config; builds per-module noise with per-module streams. |
| `generation_module.gd` | The module contract: one output field, declared dependencies, `evaluate_node`, optional bulk `add_columns`. |
| `generation_registry.gd` | Registration, dependency resolution, field-slot assignment, loud failure on bad graphs. |
| `generation_engine.gd` | Runs modules on a node grid, caches nodes, interpolates, adds column terms, clamps to bounds (ADR-0013). |
| `terrain_generation_stack.gd` | The single place modules are registered; builds context → registry → engine. |
| `geographic_surface.gd` | What the voxel layer sees: heights, raw fields, classification, cache statistics. |
| `modules/*.gd` | M1: `continentalness`, `elevation`, `mountainness`, `hills`, `detail`, `surface`. M2: `tectonics`, `archipelago`, `coast_detail`, `landmass`, `plateaus`, `valleys`. |

**Module pipeline.** Each module owns one scalar field. Execution order comes from
the declared dependency graph, not from the registration list:

```
detail          (independent; per-column full-resolution term)          M1
continentalness (independent)                                           M1
tectonics       (independent)                                           M2  plate regions + boundaries
archipelago     <- continentalness                                      M2  island groups
coast_detail    <- continentalness                                      M2  bays, peninsulas
landmass        <- continentalness, archipelago, coast_detail           M2  the land signal everyone reads
elevation       <- landmass                                             M1 (rewired)
mountainness    <- landmass, tectonics                                  M1 -> v2
hills           <- landmass, mountainness                               M1 (rewired)
plateaus        <- landmass                                             M2
valleys         <- landmass, mountainness                               M2
surface         <- landmass, elevation, mountainness, hills,             M1 -> v2
                   plateaus, valleys                                    (world units)
```

**One land signal (M2).** Every landform, the elevation field, the hills field and
the surface composer read `landmass`, never the raw `continentalness`. That is what
keeps islands and coastline detail from being re-implemented six times, and it is
why the sea-level contract survived unchanged (ADR-0017).

**Composition order in `SurfaceModule` v2** — a documented contract, not an
accident: seafloor → land base → relief → plateau *blend* (removes relief, so a
plateau interior is level) → valley *carve* (last, so a valley cuts through
everything; floored at the regional base and faded on plateau tops) → coastal
softening → bounds. Each step has a test that would fail if the order changed
(ADR-0017).

Adding a field is one subclass plus one line in
`TerrainGenerationStack._register_modules()`; modules that do not depend on it
keep producing bit-identical values (ADR-0011, tested).

**Two resolutions.** Regional fields are evaluated on a node grid spaced
`sampling_stride` (8) voxels and interpolated; the detail module adds a
full-resolution term in bulk. Node positions and interpolation weights are derived
from absolute coordinates, so two blocks sharing a column compute it identically —
seams are impossible by construction, not patched up.

Node evaluation is cached in a mutex-guarded dictionary capped at 8192 entries.
Stored values are pure functions of their coordinate, so a racing pair of threads
computes the same number and the outcome equals a serial run.

One further cache was added in M2, and only because it was measured to be worth it:
`TectonicsModule` memoises the nine plate-site records for the plate cell it is in
(256 cells, 5 floats each, mutex-guarded). Recomputing them would cost nine
`hash_coords` calls per node - about 21 µs against 0.17 µs for a lookup - for a value
that is identical for every node in the same 520-voxel cell. No other M2 module caches
anything: they are arithmetic on noise and on their inputs (ADR-0014).

**A continuity rule that M2 learned the hard way:** any field that depends on a
discrete regional choice (the nearest site, a cell membership, a classification) can
jump where that choice changes, even when the underlying quantity is continuous.
Such a field must either blend across the choice or be constructed so the choice is
well separated. Both defects found in M2 were of this kind (ADR-0016).

**Determinism.** Every value is a pure function of
`seed + module id + module version + generation version + (x, z)`. No global RNG,
no clock, no accumulation. `generation_version` exists so a deliberate algorithm
change can reshuffle the world honestly instead of silently.

### `src/core/terrain/` — materials

| File | Role |
|---|---|
| `block_palette.gd` | Voxel type ids, their colours, and the depth rule that turns a voxel position into a type. Snapshot-able (ADR-0010). |

`BlockPalette` owns the material rule so neither the generator nor the voxel layer
has to know it. `AIR == 0` is a hard contract with Voxel Tools and is asserted,
not assumed. Geography decides *where* the surface is; the palette decides *what*
it is made of — the seam a biome milestone would extend.

### `src/voxel/` — Voxel Tools integration

| File | Role |
|---|---|
| `terrain_block_generator.gd` | `VoxelGeneratorScript` adapter: asks the surface for a block's column heights, writes type ids into a `VoxelBuffer`. |
| `blocky_library_builder.gd` | Builds the `VoxelBlockyLibrary`, the `VoxelMesherBlocky` and the material. |
| `voxel_terrain_builder.gd` | Creates and configures the `VoxelTerrain` node. |

The generator's job is translation, not geography. Its performance shape is
deliberate: **one** `sample_block_heights()` call per block (which shares node
lookups and interpolation weights across all 256 columns) and at most three
`fill_area` calls per column, rather than one noise call and one `set_voxel` per
voxel. Each GDScript→C++ crossing has real cost, and this is the cheapest correct
shape for a scripted generator.

Thread safety is not assumed: `_generate_block` mutates no state, and the objects
it touches are read-only once `configure()` has run on the main thread.

### `src/world/` — configuration and orchestration

| File | Role |
|---|---|
| `world_config.gd` | All generation parameters: seed, generation version, landform amplitudes, field frequencies, streaming radius, sampling stride. |
| `voxel_world.gd` | Owns the terrain lifetime, assembles the generation stack, adds the sea plane, rebuilds on change, reports status. |
| `main_scene.gd` | Connects world ↔ camera ↔ debug panel; frames the camera on land at startup. |

`VoxelWorld` is a plain node, not an autoload. A second world for comparison is
just another instance.

### `src/camera/`, `src/debug/`

`OrbitCamera` handles mouse and touch from one code path. `DebugPanel` knows
nothing about the world: it emits `regenerate_requested(request)` and renders
whatever status dictionary the scene hands it — including, since M1, the terrain
type and the raw fields under the viewer. Deleting the panel does not touch
generation code.

## Threading model

```
 main thread            worker threads (Voxel Tools pool)
 ───────────            ──────────────────────────────────
 rebuild()              TerrainBlockGenerator._generate_block()
   ├ snapshot config ──►  ├ GeographicSurface.sample_block_heights()
   ├ build modules        │    ├ node cache (mutex-guarded, pure values)
   ├ create terrain       │    ├ bilinear interpolation
   └ attach               │    └ detail module: add_columns() in bulk
                          └ BlockPalette.classify()            (pure)
                            writes into its own VoxelBuffer
```

No global RNG and no shared mutable state that can change a result. The only
shared mutable object is the node cache, which holds pure values and is
mutex-guarded; `tests/suites/core_suite.gd` and `generation_suite.gd` both compare
4-thread sampling against a serial run exactly.

## Rendering and streaming

Streaming, threading, meshing and block bookkeeping are all Voxel Tools'
`VoxelTerrain`; the project does not implement a competing chunk system. The
`VoxelViewer` lives under the camera and registers itself globally with the Voxel
Tools engine; `VoxelWorld` only pushes streaming settings to it.

Since M1 the world also adds one purely visual object: a translucent
`MeshInstance3D` plane at `sea_level`, so submerged terrain reads as water. It is
not a fluid simulation and nothing queries it. M2 changed nothing about it, which is
why carved inland basins are held above sea level: a basin below the sea plane would
fill, and nothing in M2 can drain it.

## M3 implementation update (supersedes camera/vertical/mesher descriptions above)
The world now selects blocky or smooth adapters over the same GeographicSurface.
Independent horizontal/vertical streaming replaces the fixed 0.5 ratio; composition
has no fixed altitude clamp. One camera/viewer switches between orbit and flight.
See [M3 camera, streaming and adapter guide](M3_CAMERA_STREAMING_ADAPTERS.md) for
controls, density semantics, launch instructions and remaining validation limits.
