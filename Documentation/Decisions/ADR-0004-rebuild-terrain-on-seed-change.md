# ADR-0004 — Recreate the terrain node when generation parameters change

**Status:** Accepted
**Date:** 2026-11-06

## Context

Changing the seed must change the terrain immediately, and re-entering the same
seed must reproduce the same world exactly.

Voxel Tools caches generated data blocks and their meshes. Assigning a new
generator to a live `VoxelTerrain` does **not** invalidate that cache, and
`VoxelTerrain` exposes no public "discard all blocks" operation (`save_block`,
`try_set_block_data` and the `VoxelTool` editing API all modify or persist data;
none of them clear the volume).

## Decision

`VoxelWorld.rebuild()` tears down the existing `VoxelTerrain` node and builds a
new one from the current `WorldConfig`.

The configuration is snapshotted (`WorldConfig.duplicate_config()`) before the
build, so a parameter edited in the inspector mid-generation cannot be observed
half-applied by a worker thread.

## Consequences

- Regeneration is guaranteed correct rather than dependent on undocumented cache
  invalidation behaviour.
- A rebuild costs a full re-stream of the region around the viewer. That is
  acceptable for a debug/seed-change action and is visible as the short "loading…"
  state in the overlay.
- A future milestone that wants live parameter tweaking without a full reload
  should implement it deliberately (for example by regenerating blocks through
  `VoxelTool` over the view region), rather than by mutating a live generator and
  hoping the cache follows.
