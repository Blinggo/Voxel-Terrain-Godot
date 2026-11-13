# M5 public-source terrain research

Inspected public repositories only. No third-party implementation or asset was copied into the runtime. Licence texts are preserved under `m5-licenses/`, with SHA-256 hashes. Repository licences do not automatically license every linked asset or dependency. These findings concern the pinned revisions below, not every future release.

## 1. Primitive Voxels / TerraForge

- Repository: https://github.com/TsokasGit/primitive-voxels-godot
- Inspected revision: `5af560bb8ff936bfbd12468f64c22d63ffb0e36c`.
- **Verified licence: CC0-1.0, not MIT.** [Licence at revision](https://github.com/TsokasGit/primitive-voxels-godot/blob/5af560bb8ff936bfbd12468f64c22d63ffb0e36c/LICENSE).
- Inspected README and `Voxels/Scripts/{voxel_world,voxel_chunk,voxel_mesher}.gd`.
- Chunk representation: 16 cells / 17 lattice points, packed density/material storage. The world samples `height - y` (**positive inside**, unlike our Voxel Tools field), applies nearby cave-segment/room carving, and passes mesh-array results from worker builds to main-thread application. The mesher uses Marching Cubes and accumulated vertex normals. Mountain influence combines biome and mountain masks; separate height/detail/ridge signals establish scale hierarchy.
- Useful concepts: shared lattice values, immutable build results, column-work reuse, spatially limited modification. Independently adapted the separation of density from mesh generation, not this implementation or its sign convention.
- Not adopted: its custom mesher, finite-world seeded path construction, gameplay/editing systems, full cave paths and material/biome catalogue. Those would replace existing extension responsibilities or exceed scope.
- Performance evidence: source has chunk-density and mesh/collision timing prints and threaded queue controls. No comparable SM6115 benchmark was established from the inspected material. Threading itself is not a measured speed guarantee.
- Reuse: CC0 public-domain dedication/fallback permissions differ from MIT notice obligations. Reuse is generally permitted under that instrument; no source reuse was necessary here.

## 2. Terrain3D

- Repository: https://github.com/TokisanGames/Terrain3D
- Revision: `852b6c9742bcfebab30d06857c547e2d8daa2f60`.
- **MIT**, [LICENSE.txt](https://github.com/TokisanGames/Terrain3D/blob/852b6c9742bcfebab30d06857c547e2d8daa2f60/LICENSE.txt).
- Inspected README, `src/terrain_3d.cpp`, mesh-asset implementation and `doc/docs/introduction.md`.
- Its geographical mesh is a geomorphing geometric clipmap: dense geometry near the viewer and progressively coarser rings, divided into data regions. Material/asset management is separate from terrain-data organization.
- Lesson: distant silhouettes require an explicit distance/detail strategy, not increasingly expensive fine noise. Regional ownership and separation of data from rendering are useful architectural precedents.
- Rejected as a dependency: it is a heightmap terrain system, not a volumetric replacement for Voxel Tools. Its clipmap shaders, texture/material pipeline and editor tooling are not transplanted. M5 does **not** gain clipmap/LOD merely by researching it.
- Performance: documentation explains the bounded, viewer-centred LOD mechanism; no directly comparable benchmark for this GDScript density pipeline or target Android device was verified. No FPS claim is imported.
- Reuse: MIT source reuse requires retaining copyright/permission notices. No source or assets copied.

## 3. FastNoiseLite

- Repository: https://github.com/Auburn/FastNoiseLite
- Revision: `785f37a9ad76e283586a379675085f2063ae03f7`.
- **MIT**, [LICENSE](https://github.com/Auburn/FastNoiseLite/blob/785f37a9ad76e283586a379675085f2063ae03f7/LICENSE).
- Inspected README and `Cpp/FastNoiseLite.h`: coordinate-driven 2D/3D sampling, FBm/ridged/ping-pong accumulation and single/progressive/independent domain-warp dispatch.
- Built-in Godot `FastNoiseLite` was already used by the project. M5 uses that API and existing deterministic substream hashing. **No new library installed.** New 3D bands use one octave of smooth Simplex; the existing macro stack retains its separate ridged/warped fields.
- The README's C++ benchmark reports 36.83 million 3D OpenSimplex points/s and 71.30 million 2D Simplex points/s on Intel 7820X at 4.9 GHz, Win10 x64, clang-cl 10 `/O2`. These are upstream native throughput figures, **not** Godot/GDScript/Android measurements and not used to estimate project FPS.
- Frequency is global per band; spatial profile blends change amplitude, not frequency, avoiding spatially varying phase discontinuities. Optional bounded warp is off by default. Each enabled layer adds sampling cost; measurements in the milestone evidence are authoritative for this implementation.
- Reuse: MIT notices would accompany copied source. No separate upstream implementation copied; existing engine licence/distribution remains unchanged.

## 4. Terrainy

- Repository: https://github.com/fabian-becker/Terrainy
- Revision: `98f42ff4463f14bc89798020670e13149eaf2f14`.
- **MIT**, [LICENSE](https://github.com/fabian-becker/Terrainy/blob/98f42ff4463f14bc89798020670e13149eaf2f14/LICENSE).
- Inspected README; `addons/terrainy/nodes/basic/heightmap_evaluation_context.gd`, `nodes/noise/noise_evaluation_context.gd`, `nodes/landscapes/mountain_range_node.gd`, and `helpers/terrain_heightmap_builder.gd`.
- Evaluation contexts snapshot transforms, influence shape/size/falloff, strength and blending. Heightmaps use bilinear sampling; noise uses world coordinates. Mountain-range controls describe a wandering crest, broad skirt plus narrow summit profile, ridged peaks/cols, elongated foothills and gullies. The builder has independent heightmap workers and separate influence-map generation.
- Independently adapted: read-only parameter snapshots and smooth influence blending. Our ranges remain driven by the existing M2 tectonic/mountain fields rather than importing an unrelated feature-node architecture.
- Rejected: editor-node graphs, whole heightmap building and GPU blending as runtime dependencies. A heightmap feature system does not itself provide overhangs.
- Performance: inspected source establishes worker/context organization, not a controlled comparable device benchmark. No numeric project speedup claimed from it.
- Reuse: MIT notice obligations apply to copied code; no code/assets copied.

## 5. Voxel Tools — actual v1.7

- Repository: https://github.com/Zylann/godot_voxel/tree/v1.7
- Tag tree: `2ac9f5f8a8219bf499314cc0fad54ffc47df908f`.
- **MIT**, [LICENSE.md](https://github.com/Zylann/godot_voxel/blob/2ac9f5f8a8219bf499314cc0fad54ffc47df908f/LICENSE.md).
- Inspected `doc/source/smooth_terrain.md`, `doc/source/api/VoxelBuffer.md`, and `generators/simple/voxel_generator_noise.cpp`.
- Sphere example `distance - radius` confirms **negative inside**. Shaped/approximate SDFs and saturation are usable; exact Euclidean distance is not required. Native noise generator snapshots configuration under a read/write lock and uses shaped-noise bounds to skip uniform work.
- Independently adapted: conservative, mathematically bounded uniform-region early-outs and construction-time snapshots. Existing `VoxelGeneratorScript`, TYPE and 32-bit SDF channels and Transvoxel mesher are retained. Transitions remain disabled because this is still single-resolution streaming.
- Performance: source demonstrates useful early-out mechanisms, not a transferable timing claim. Actual GDScript and native meshing work is measured separately where available.
- Reuse: existing extension notices are preserved. No new native code or custom engine build added.

## Decisions and rejected experiment

1. Keep the existing macro geography and deterministic registry; introduce blended parameter profiles before hydrology, then a shared density object after carving.
2. First reproduce `D=y-H`; keep that mode available.
3. Use finite-band geological/fine displacement plus slope-masked, carve-only structural recesses. An initial unrestricted signed 3D structural displacement visibly produced excessive rounded blobs and was rejected after rendering.
4. Protect hydrological beds conservatively rather than letting independent density noise punch them open.
5. Do not introduce native/GPU/ML dependencies, full-world preprocessing, cave networks, erosion or fluid simulation.
6. Keep explicit limitations: this is not Terrain3D LOD, not Primitive Voxels' cave system, and not visual parity with Vintage Story or modded Minecraft.
