# Architecture Overview

## Principle

One direction of dependency, no cycles:

```
WorldConfig  ──►  core (noise, height field, palette)  ──►  voxel adapter  ──►  Voxel Tools
                        ▲                                        │
                        └────────── contains no engine nodes ─────┘
```

`src/core/` never references Voxel Tools, nodes, the scene tree, or the
renderer. `src/voxel/` never contains terrain mathematics. `src/world/` owns
lifetime and wiring. `src/debug/` and `src/camera/` are consumers that speak to
the world only through small, explicit interfaces.

That is what makes a later replacement of the terrain algorithm a local change:
a new generator system produces something with the same
`get_surface_height(x, z)` shape (or an equivalent volume query), and the voxel
layer keeps working.

## Layers

### `src/core/noise/` — scalar field sources

| File | Role |
|---|---|
| `noise_source.gd` | Abstract contract: a pure, thread-safe, coordinate-based 2D field in `[-1, 1]`. |
| `fast_noise_lite_source.gd` | The M0.1 implementation, wrapping Godot's `FastNoiseLite`. |

The abstraction exists for one concrete reason: the height field must not be
welded to `FastNoiseLite`. Swapping in a custom or native field means writing
one subclass. Nothing else changes.

The contract is written into the base class because it is what makes worker
threads safe: **pure function of the arguments, configured once in `_init`,
never mutated afterwards.**

### `src/core/terrain/` — terrain model

| File | Role |
|---|---|
| `terrain_height_field.gd` | Maps 2D noise to a world-space surface height per column. |
| `block_palette.gd` | Voxel type ids, their colours, and the depth rule that turns a voxel position into a type. |

`TerrainHeightField` is the M0.1 surface model and nothing more. It is
deliberately not the climate/hydrology/biome architecture; it is a single noise
band, and it says so.

Determinism and seam-freedom come from one design rule: **the height of a column
depends only on its absolute world `(x, z)`**, never on the block being
generated, the generation order, or the calling thread. Adjacent blocks
therefore compute identical values for the voxels they share, which makes seams
structurally impossible rather than something to patch up afterwards.

`BlockPalette` owns the material rule (air / grass / dirt / stone by depth below
the surface) so that neither the generator nor the voxel layer has to know it.
`AIR == 0` is a hard contract with Voxel Tools and is asserted, not assumed.

### `src/voxel/` — Voxel Tools integration

| File | Role |
|---|---|
| `terrain_block_generator.gd` | `VoxelGeneratorScript` adapter: walks a block's columns, asks the core for the surface, writes type ids into a `VoxelBuffer`. |
| `blocky_library_builder.gd` | Builds the `VoxelBlockyLibrary`, the `VoxelMesherBlocky` and the material. |
| `voxel_terrain_builder.gd` | Creates and configures the `VoxelTerrain` node. |

The generator's job is translation, not geography. Its performance shape is
deliberate: one noise evaluation per column and at most three `fill_area` calls
per column, rather than one noise call and one `set_voxel` per voxel. Each
GDScript→C++ crossing has real cost, and this is the cheapest correct shape for
a scripted generator.

Thread safety is not assumed: `_generate_block` mutates no state, and the objects
it touches are read-only once `configure()` has run on the main thread.

### `src/world/` — configuration and orchestration

| File | Role |
|---|---|
| `world_config.gd` | The parameters: seed, base height, amplitude, frequency, octaves, view distance. |
| `voxel_world.gd` | Owns the terrain lifetime, assembles the generation stack, rebuilds on change, reports status. |
| `main_scene.gd` | Connects world ↔ camera ↔ debug panel. |

`VoxelWorld` is a plain node, not an autoload. A second world for comparison is
just another instance.

### `src/camera/`, `src/debug/`

`OrbitCamera` handles mouse and touch from one code path. `DebugPanel` knows
nothing about the world: it emits `regenerate_requested(request)` and renders
whatever status dictionary the scene hands it. Deleting the panel does not touch
generation code.

## Threading model

```
 main thread            worker threads (Voxel Tools pool)
 ───────────            ──────────────────────────────────
 rebuild()              TerrainBlockGenerator._generate_block()
   ├ build frozen   ──►   ├ TerrainHeightField.get_surface_height()  (pure)
   │  config + noise      └ BlockPalette.classify()                 (pure)
   ├ create terrain        writes into its own VoxelBuffer
   └ attach
```

Nothing in the generation path is shared mutable state. No global RNG is used;
all randomness is derived from the seed through the noise function.

## Rendering and streaming

Streaming, threading, meshing and block bookkeeping are all Voxel Tools'
`VoxelTerrain`. M0.1 deliberately does not implement a competing chunk system.
The `VoxelViewer` lives under the camera and registers itself globally with the
Voxel Tools engine; `VoxelWorld` only pushes streaming settings to it.
