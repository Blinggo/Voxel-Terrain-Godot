# ADR-0005 — Mobile-first streaming and rendering defaults

**Status:** Accepted
**Date:** 2026-11-06

## Context

Android ARM64 is the primary target, Windows x86_64 secondary. Mobile GPUs and
thermal budgets make "it runs on desktop" an insufficient bar.

## Decision

- `renderer/rendering_method = "mobile"` for both desktop and mobile, so the
  project is developed against the renderer it ships with.
- Horizontal streaming radius 128 voxels; `view_distance_vertical_ratio = 0.5`.
  A heightmap world is mostly air above and stone below, so a cube-shaped
  streaming region spends most of its budget generating blocks nobody sees.
- `generate_collisions = false`. M0.1 has no physics interacting with the world;
  collision meshing is pure cost. A `WorldConfig` flag should return when a
  character controller exists.
- `use_gpu_generation = false`. Compute-shader generation is not a mobile
  baseline.
- Mesh block size 16, to keep mesh uploads small.
- Blocks are written with `fill_area` per column segment rather than per-voxel
  `set_voxel`, and the surface is sampled once per column rather than per voxel.

## Consequences

- The default view shows the streaming boundary if the camera is moved further
  than ~128 voxels from the terrain it is looking at. This is expected behaviour
  of a streamed world, not a bug — it is visible in early screenshots taken at
  distance 150.
- Terrain more than 64 voxels above or below the camera is not streamed. The
  camera therefore orbits a point near the surface.
- Real device performance remains unmeasured (see the test report's "unverified"
  section); these are reasoned defaults, not profiled ones.
