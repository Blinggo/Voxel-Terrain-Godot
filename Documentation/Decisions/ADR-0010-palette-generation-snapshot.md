# ADR-0010 — Generation reads a palette snapshot, not the editable resource

**Status:** Accepted
**Date:** 2026-11-07

## Context

`VoxelWorld` handed `TerrainBlockGenerator` a reference to the live
`BlockPalette`. `WorldConfig` was already snapshotted with `duplicate_config()`
before generation began, for exactly the reason that applies here: the resource
stays editable in the inspector while Voxel Tools generates blocks on worker
threads.

Type ids are constants and cannot drift, but `soil_depth` and the three colours
are `@export` variables. Editing `soil_depth` mid-generation could produce one
block with four voxels of dirt and the next with eight — a visible discontinuity,
and a violation of the same-seed reproducibility the project promises.

## Decision

`BlockPalette.create_snapshot()` returns an independent copy of the configurable
fields. `VoxelWorld.rebuild()` takes one snapshot and builds **both** the
generator and the blocky library from it, so the voxels a block is made of and
the model used to draw it cannot disagree.

The copy is written out field by field rather than using `Resource.duplicate()`,
so that adding an exported field is a conscious decision ("does generation read
this?") instead of being picked up silently.

Type ids and material assignments are unchanged: `AIR=0`, `GRASS=1`, `DIRT=2`,
`STONE=3` remain constants and are shared by construction. One small resource is
copied per rebuild; there is no per-block cost.

## Consequences

- Worker threads never read editor-facing state that can change under them.
- An edit takes effect at the next `rebuild()`, not immediately. That is the
  intended behaviour and matches `WorldConfig`.
- `tests/suites/reliability_suite.gd` proves the snapshot is stable **and** that
  a rebuild still applies edits — a snapshot that ignored configuration changes
  would otherwise look like a pass.
- Any future generation input (climate tables, biome maps) should follow the same
  rule: snapshot before generation, share one snapshot between the generator and
  anything that must agree with it.
