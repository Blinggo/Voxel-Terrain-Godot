# ADR-0017 — Landforms are composed in a fixed order, over one shared land signal

**Status:** Accepted
**Date:** 2026-11-07
**Extends:** ADR-0011 (module pipeline), ADR-0013 (two-resolution sampling)

## Context

M2 adds five landform fields - islands, coastline detail, plateaus, valleys,
tectonic influence - plus a composed land signal. Competing arrangements:

1. Each landform module reads the raw continental field and applies its own island
   and coastline corrections.
2. One module composes the land signal, and every landform reads it.
3. The surface composer reads the raw fields and decides everything itself.

Option 1 duplicates the island and coast terms in six places: change island strength
and six modules drift apart. Option 3 collapses the pipeline into one module, which
is the architecture M1 replaced. Option 2 keeps each landform independent while
giving them a single shared definition of where land is.

The *order* in which landforms are composed into a height is equally consequential,
because several of them overlap. A plateau that overlaps a range cannot both keep its
level interior and leave the range standing; a valley that cuts through a mountain
can remove the mountain.

## Decision

**One shared land signal.** `LandmassModule` computes

```
landmass = clamp(continentalness + archipelago * island_strength
                                 + coast_detail * coast_strength, -1, 1)
```

and every landform, the elevation field, the hills field, the surface composer and
the classifier read `landmass`, never `continentalness`. The raw continental field is
still available (and still reported by the debug panel) because the difference
between the two is what M2 added. Because both corrections are additive and the sum
is clamped, no combination can leave the range the pipeline's thresholds were
calibrated against, and the sea-level contract is unchanged: the waterline is still
where this signal crosses `SurfaceModule.OCEAN_EDGE`.

**A fixed composition order in `SurfaceModule` (version 2):**

1. Seafloor depth model, with the shelf depth modulated by the elevation signal so
   offshore transitions are not a uniform ramp.
2. Land base: base height, inland rise, elevation signal.
3. Relief: hills and mountains, ramped in inland with a squared smoothstep.
4. Plateaus: **blend towards a level**, not add a lift. Blending removes the relief
   computed in step 3, which is what makes a plateau interior level. The mask is
   faded out by up to 85% where a mountain range is, so whichever landform would
   otherwise win cannot level the other.
5. Valleys and basins: **carve**, applied last so a valley cuts through hills, a
   range and a plateau alike. Carving is limited in two ways: it may not go below
   the regional base level (`VALLEY_FLOOR_MARGIN`), which stops a deep valley from
   removing the range it crosses; and it is faded by up to 90% across a plateau top
   (`PLATEAU_VALLEY_FADE`), so a plateau is a level surface rather than a set of
   mesas. Carved land is held just above sea level, because there is no hydrology to
   drain an inland depression and a basin floor below the sea plane would fill with
   water it cannot have.
6. Coastal softening, then world-unit bounds.

## Consequences

- The order is a documented contract with a test per rule: plateau interiors are
  flatter than open land (1.52 against 6.04 voxels per 16), the shortest valley
  floors are lower than their surroundings (41.4 against 47.4), mountains stand
  above both (56.9), and no new formation introduces a step above 3.0 voxels.
- Each landform remains independently testable: the M2 suite evaluates
  `LandmassModule`, `MountainModule`, `ValleyModule` and `PlateauModule` in
  isolation with synthetic inputs and no world, and checks that valleys and plateaus
  vanish under the ocean and that the land signal's composition is exact.
- Each remains configurably independent: zeroing `island_strength` restores
  `landmass = continentalness + coast`, zeroing `valley_depth` raises 267 columns
  and lowers none, and zeroing `mountain_scale` drops the peak by 14 voxels.
- **The order is not negotiable at runtime.** A future landform that needs to go
  between two of these steps must be added to this list deliberately, with a test
  that shows what it does to the neighbours.
