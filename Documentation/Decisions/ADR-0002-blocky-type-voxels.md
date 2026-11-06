# ADR-0002 — Blocky type voxels, not signed distance fields

**Status:** Accepted
**Date:** 2026-11-06

## Context

Voxel Tools supports two broad terrain representations:

- **SDF / smooth**: a signed distance per voxel, meshed with `VoxelMesherTransvoxel`.
- **Blocky / type ids**: an integer type per voxel, meshed with `VoxelMesherBlocky`
  against a `VoxelBlockyLibrary`.

The milestone requires "an appropriate blocky voxel mesher".

## Decision

Use the blocky path: `VoxelMesherBlocky` over a `VoxelBlockyLibrary` built in
code, with the generator writing type ids into `VoxelBuffer.CHANNEL_TYPE`.

Three integration facts were established by experiment, and all three are easy
to get wrong silently:

1. **Type id 0 is always air.** The mesher skips id 0 unconditionally. The
   library must therefore put `VoxelBlockyModelEmpty` in slot 0 and start real
   blocks at id 1. A library whose slot 0 is a cube meshes to *nothing at all*,
   with no error.
2. **The library must be baked.** The mesher reads only baked library data
   (it is the only form safe to share across worker threads). An unbaked library
   also meshes to nothing, with no error. `BlockyLibraryBuilder` calls `bake()`
   explicitly.
3. **The type channel must be 8- or 16-bit.** The mesher rejects other depths
   with `Unsupported voxel depth`. The project pins 16-bit through `VoxelFormat`
   so it never depends on a default.

## Consequences

- Blocky faces cull against neighbours for free, and vertex-baked occlusion
  gives readable terrain with no textures at all.
- Each cube has a single colour, so a grass block's *sides* are green. Layered
  materials are present in the data (and visible in any cut deeper than the soil
  layer) but a grass voxel cannot show a dirt side without a multi-material
  model. Noted as a limitation rather than papered over.
- Switching to smooth terrain later is a mesher + buffer-channel change in
  `src/voxel/`, not a rewrite of the core.
