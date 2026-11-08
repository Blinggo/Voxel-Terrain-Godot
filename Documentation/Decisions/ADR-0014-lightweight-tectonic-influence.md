# ADR-0014 — Lightweight tectonic influence from a jittered Voronoi lattice

**Status:** Accepted
**Date:** 2026-11-07
**Extends:** ADR-0011 (module pipeline), ADR-0012 (deterministic hashing), ADR-0013 (node grid and cache)

## Context

M2 requires the geography to be driven by something *structural* rather than by
noise alone: approximate plate regions, their boundaries, and per-boundary
convergent / divergent (and, if useful, transform) influence, which in turn drives
where mountain ranges stand, which regions are geologically elevated, and how
strongly. The constraints are explicit:

- deterministic and independently sampleable at any coordinate;
- cheap enough for a Snapdragon 662 Android target at four gigabytes of RAM;
- no geological simulation, no persistent world map, no mutable global state;
- it must not create a second generation architecture (ADR-0011 stands).

Three designs were considered:

1. **Simulated plates.** Seed plate nuclei, grow them, integrate motion, compute
   collisions and crust thickness. This is what the reference projects do on a
   bounded grid. It needs a grid, an iteration pass and a stored result, so it
   cannot be sampled at an arbitrary coordinate without generating the world
   around it. Rejected: incompatible with chunk-independent, order-free sampling.
2. **No tectonics; keep noise belts.** Cheapest, and it is what M1 did. Rejected:
   it is exactly the limitation M2 was raised to address - ranges with no
   structural reason to be where they are.
3. **An analytic plate field.** Plates as a Voronoi diagram of a jittered lattice,
   with per-site attributes derived by hashing the cell coordinate, so the field is
   a pure function of position with no state.

## Decision

`TectonicsModule` (`id = "tectonics"`, field `tectonics`) samples a jittered square
lattice of feature points, one per cell, and treats the nearest feature point as
the plate a coordinate belongs to.

- **Site placement.** A site is placed inside the central half of its own cell
  (`JITTER_SPAN = 0.25` around the cell centre). Confining sites to the central
  half is what guarantees that any two sites are at least half a cell apart; see
  ADR-0016 for why that matters.
- **Attributes.** Each site has a **drift vector** (heading and speed derived from
  one hash) and an **interior bias** (a second hash). Both are functions of the
  world seed, the module id, the module version and the cell coordinate, all mixed
  by `TerrainHash`.
- **Boundary.** A node samples its own cell and the eight around it. The distance
  to the bisector of the two nearest sites is estimated as
  `(d2 - d1) / 2`, which is the standard cheap Voronoi edge distance. The nearest
  site is always inside the 3x3 neighbourhood because sites are confined to their
  cells.
- **Character.** The relative drift `v = drift(second) - drift(nearest)` is
  decomposed against the unit normal `n` from the nearest site to the second:
  `along = v . n` (negative = approaching), `across = v x n` (sideways). Approaching
  plates uplift, separating plates subside, sideways motion shears:

  ```
  stress = (uplift - rift * 0.85 + shear * 0.16) * proximity * rate
  field  = clamp(stress + interior_bias, -1, 1)
  ```

  Every term is invariant under swapping the two sites, so a boundary reads the
  same from both sides.
- **Cache.** The nine cell records for one plate cell are cached in a bounded,
  mutex-guarded dictionary keyed by the cell coordinate, because hashing is far
  more expensive than the geometry: measured on the development container one
  `TerrainHash.hash_coords` call costs about 2.3 us and a cache lookup about
  0.17 us. Eighteen hashes per node would cost roughly 41 us per node on its own -
  more than the entire M1 node budget - while one lookup replaces them all, because
  every node inside one plate cell needs exactly the same nine records.

## Consequences

**Good.**

- The field is a pure function of coordinate: no map, no iteration, no state, no
  ordering dependency, and it works outside any generated region.
- It can be disabled, re-tuned (cell size, boundary width) or replaced by
  configuration without touching the modules that consume it.
- It gives mountain placement a structural reason: the M2 test suite measures
  mountainness at `tectonic > 0.35` at 0.526 against 0.222 in plate interiors, and
  rift boundaries 2.6 voxels below plate interiors.
- Cost is one dictionary lookup and about twenty floating-point operations per
  node, plus the neighbourhood build once per 520-voxel cell crossed.

**Accepted costs and limits.**

- Plates are irregular but not organic: cell size is uniform, so plate areas vary
  by less than a simulated set would. Nothing in the pipeline observes plate area.
- The boundary is a straight bisector. Range shape is deliberately made irregular
  elsewhere (ADR-0015); the tectonic field supplies the *line*, the noise supplies
  the silhouette.
- The 3x3-neighbourhood estimate is exact for the nearest site and a very good
  approximation for the second. It is verified against a wider brute-force scan in
  the M2 tests rather than assumed, and the tie blending in ADR-0016 removes the
  discontinuity that a naive pair selection produces at triple points.

## References consulted

- Classification of plate boundaries into convergent, divergent and transform, and
  the use of Voronoi cells as plates: general plate-tectonics literature and
  publicly documented procedural generators (see the M2 milestone document,
  section 4, for the licence review). No source code was copied.
- `Guy-Shalev/terrain-generator` (MIT) - the M1 reference for falloff-masked uplift;
  the same idea appears here as `proximity`.
