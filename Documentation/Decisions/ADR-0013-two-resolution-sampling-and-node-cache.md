# ADR-0013 — Regional fields on a node grid, detail per column, node cache

**Status:** Accepted
**Date:** 2026-11-07

## Context

Geographic fields vary over hundreds of voxels. Sampling all of them per column
would repeat nearly the same answer 64 times inside one 16×16 block, which is
wasteful on the exact target the project cares about — a low-end phone. But
interpolating *everything* from a coarse grid loses fine surface texture.

Three constraints pull in different directions: cost, visual quality, and the
absolute requirement that adjacent blocks agree on shared columns.

## Decision

Two resolutions.

1. **Node grid.** All regional modules are evaluated on a grid spaced
   `WorldConfig.sampling_stride` (8) voxels apart, with node positions snapped to
   absolute multiples of the stride. The composed surface is bilinearly
   interpolated for each column, using weights derived from absolute coordinates.
2. **Per-column terms.** A module may declare `contributes_columns` and add a
   full-resolution term *in bulk* via `add_columns(heights, origin, size)`. The
   detail module does this: one noise lookup per column.
3. **Node cache.** A `Dictionary<Vector2i, PackedFloat32Array>` guarded by a
   `Mutex`, capped at 8192 entries, evicting by clearing when full. Values stored
   are pure functions of the coordinate, so a racing pair of threads computing the
   same node produces the same value and the outcome equals a serial run.

Interpolation weights are computed once per block for columns and rows and the
node surface values are copied into flat `PackedFloat32Array` rows, because
indexing an array-of-arrays four times per column was measurably the dominant cost
in GDScript (203 µs → 126 µs per block from that change alone).

Bulk, not per column: a scripted call costs far more than the arithmetic inside
it, so 256 calls per block would dominate the block time (164 µs → 126 µs).

## Consequences

- Cost per 16³ block dropped to ~44 µs in the project benchmark (M0.1: 36 µs)
  while producing five fields instead of one, and ~126 µs in a worst-case
  scattered-block probe.
- Seams remain impossible: identical nodes, identical weights, for every block
  that touches a column. Tested at the field level (one 64² request vs sixteen
  16² requests vs per-column queries) and at the voxel level (reconstructed from
  block data).
- The cache cannot change results — proven by comparing 2304 heights with the
  cache enabled and disabled.
- Structure finer than the stride must go through a column term; a module that
  forgets this will look smooth rather than wrong, so the stride is documented on
  `WorldConfig.sampling_stride` and defaults to one block face.
- The mutex is on the hot path but uncontended in practice; a per-thread cache
  would avoid it and is the obvious next optimisation if profiling ever shows
  contention.
