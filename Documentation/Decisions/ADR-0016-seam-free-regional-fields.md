# ADR-0016 — Regional fields must be continuous under pair swaps and cache boundaries

**Status:** Accepted
**Date:** 2026-11-07
**Extends:** ADR-0013 (node grid and cache), ADR-0014 (tectonic lattice)

## Context

M2 introduced fields whose value depends on a *set* of nearby regional features
rather than on noise alone: the tectonic field depends on the two nearest plate
sites, and the mountain and valley fields depend on the composed land signal. Such a
field is a function of a discrete choice - *which* pair of sites is nearest - and a
discrete choice is exactly what produces a seam in an otherwise smooth terrain.

Two defects were found by measurement rather than by inspection, and both produced
real cliffs in the generated terrain:

1. **Triple-point swap.** At a point equidistant from three plate sites, the
   second-nearest site changes. The *distance* to the bisector is continuous through
   that change, but the *normal* is not, so the drift decomposition
   (`along = v . n`) flipped sign across a one-voxel line. Measured on the M2
   terrain: `tectonics` jumped by 0.64 and the surface by 25 voxels in a single
   voxel step, on the medial axis between three plates.
2. **Coincident sites.** Site jitter was a full cell, so two neighbouring cells
   could place their sites a few voxels apart. A boundary between nearly coincident
   sites has no well-defined normal; the guard returned zero stress, which was an
   even larger discontinuity (0 to 0.41).

## Decision

Three rules, all enforced in code and each with a regression test:

1. **Blend across ties.** The tectonic field tracks the third-nearest site as well
   as the second. Where the second and third are nearly tied - within `TIE_WIDTH`
   = 30 voxels of distance - the boundary character is the average of the two
   candidate pairs, weighted by `smoothstep(0, TIE_WIDTH, d3 - d2)`. At the exact
   tie the weight is symmetric, so the result does not depend on which site the
   sort happened to return; away from it one candidate carries all the weight.
2. **Make the degeneracy impossible rather than tolerated.** Sites are confined to
   the central half of their cell (`JITTER_SPAN = 0.25`), so any two sites are at
   least half a cell apart and the normal is always well conditioned. The `span`
   guard remains as a safety net, but it is unreachable in a valid configuration.
3. **Never let a cache boundary change a value.** The 3x3 neighbourhood is keyed by
   the cell that contains the query point, and the nearest site is guaranteed to be
   in that neighbourhood because sites are confined to their cells. The cache is
   therefore a pure memo: crossing a cell border may rebuild the neighbourhood but
   cannot change what it contains that matters. Verified by comparing the cached
   field against a brute-force wider scan at 4000 scattered coordinates (maximum
   difference 0.000000) and by a test that walks every plate cell border.

## Consequences

- No seams: the largest adjacent-voxel step in the tectonic field anywhere in a
  6000-sample sweep is 0.148, which is a gradient, and the largest surface step is
  4.6 voxels against a limit of 8.
- The blend costs one extra nearest-site distance and two pair evaluations per node;
  it is inside the node budget measured in the milestone document.
- The rule generalises: **any future module that reads a discrete regional choice
  (nearest feature, cell membership, classification) must blend across the boundary
  of that choice or guarantee the choice is well separated.** Recorded here so the
  next milestone does not rediscover it as a cliff.
