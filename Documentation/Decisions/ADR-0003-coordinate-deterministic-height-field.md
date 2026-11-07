# ADR-0003 — Coordinate-deterministic height field behind a noise interface

**Status:** Accepted — implementation superseded by ADR-0011 (M1), rule still binding
**Date:** 2026-11-06

## Context

Terrain must be seed-configurable, reproducible, seamless across block
boundaries, and safe to generate on several threads at once. The milestone also
forbids welding the generator to a single noise implementation, and forbids
global mutable RNGs.

## Decision

The surface is a pure function of absolute world coordinates:

```gdscript
surface_height(x, z) = base_height + noise.sample_2d(x, z) * amplitude
```

with `noise` an instance of `NoiseSource` (an abstract `RefCounted`), whose
concrete implementation in M0.1 is `FastNoiseLiteSource`.

`NoiseSource`'s contract, documented in the class itself:

- **pure** — same input, same output, for the object's whole life;
- **thread-safe** — no mutation inside `sample_2d`, configure in `_init` only;
- **coordinate-based** — depends on world position, never on the block or the
  generation order.

The height field lives in `src/core/` and knows nothing about Voxel Tools.

## Consequences

- **Seams are structurally impossible**, not merely unlikely: two adjacent
  blocks evaluate the same function at the same coordinates. The test suite still
  verifies this empirically, because "by construction" is a claim worth checking.
- **Determinism is cheap**: the same seed reproduces byte-identical blocks, and
  the test suite compares whole generated blocks, not samples.
- **No global RNG** anywhere in the path. The debug panel's "Random seed" button
  uses a local `RandomNumberGenerator` purely to pick a number, which then
  becomes an explicit, recorded seed.
- Replacing the algorithm means a new `NoiseSource`, or a new height field that
  still answers `get_surface_height(x, z)`. Later systems that need more than a
  height (caves, overhangs) will need a volume query instead; that is an
  acknowledged, deliberate future refactor, not an accident of this design.
