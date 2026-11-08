# ADR-0015 — Mountain ranges are structural bands with noise relief, not a noise layer

**Status:** Accepted
**Date:** 2026-11-07
**Supersedes (implementation):** the M1 `MountainModule` (one ridged fractal times a
belt mask and an inland gate). The module id `mountainness` and its output range are
unchanged; its algorithm is version 2.

## Context

M1's mountain field was one ridged fractal multiplied by two masks. The M1 milestone
recorded the consequence honestly: it produced mountain-shaped *texture*, but a range
had no length, no spine and no reason to be where it was. M2 requires connected
mountain regions, long primary ridges, secondary ridges, individual peaks, foothills,
valleys inside ranges, natural transitions between range and plain, and irregular
silhouettes - explicitly *not* several layers of ridged noise.

Measurement on the M1-derived field (see the M2 milestone document) showed the shape
problem in numbers: 30% of land classified as mountain, 125 separate components, and
a mean fill ratio of 0.82 - that is, mountain regions were nearly solid blobs filling
their bounding boxes, not long thin ranges.

## Decision

`MountainModule` version 2 composes four terms with distinct jobs:

| Term | Source | Job |
| --- | --- | --- |
| `structural` | the tectonic band, times the ridge field | the range itself: a long, continuous, elevated line |
| `massif` | a squared belt field, times the ridge field | noise-driven provinces away from any boundary |
| `ridge` | ridged fBm, domain-warped | crest shape, ribs and peaks inside both |
| `apron` | the unsharpened tail of the ridge field | foothills, and the saddle between two ranges |

The composition is:

```
band       = smoothstep(0.02, 0.55, tectonics)
ridge      = max(spine, secondary_ribs)
structural = band * (0.42 + 0.58 * ridge)
massif     = belt^2 * ridge
relief     = max(max(structural, massif), apron * (0.35 + 0.65 * belt))
mountain   = relief * inland * rift_suppression * variation
```

Key properties:

- **Length comes from the tectonic band, not from noise.** Plate boundaries are
  lines, and proximity to a boundary is a band. A term built from that band is
  elongated by construction. Noise then varies the height *within* the band instead
  of deciding where the band is.
- **Continuity comes from `BAND_BASE`.** The band raises its whole width by 42% of
  the ridge amplitude, not just the crests, so a range is continuous along its
  length: crests are peaks on a raised system rather than isolated summits.
- **Connections come from the apron and the belt floor.** A belt damps a range
  rather than cutting it, and the apron never falls to zero across a belt, so a
  province edge becomes a saddle. Adjacent ranges therefore join at a col instead of
  stopping.
- **Foothills come from the apron**, taken from the ridge field *before* it is
  sharpened into a crest, so the transition from range to plain is a set of
  decreasing hills rather than a wall.
- **Secondary ridges** are a second ridged field at 3.2x the primary frequency,
  weighted by how far up the primary ridge the point already is, so ribs grow on
  flanks and do not invent ranges of their own.
- **Height varies between ranges** through a very low frequency field (about a
  1000-voxel wavelength) that scales the whole result, so one range in a world is a
  line of hills and another is a massif. Measured spread of tile peaks: 45 voxels.
- **Rifts cut ranges.** A negative tectonic value suppresses the field by up to 55%,
  so a belt that crosses a rift loses its mountains there instead of crossing it.
- **Islands get relief.** The inland gate is `smoothstep(-0.04, 0.18, land)` rather
  than M1's `smoothstep(0.10, 0.30, land)`. Gating hard at the coast made every
  island a flat pancake; a low floor keeps islands hilly while the surface
  composer's own inland ramp (which is squared) still keeps the shoreline gentle.

## Consequences

**Measured, seed 1337, 1024-voxel window:** mountains 18.2% of land (M1 30.6%),
49 components, largest 26% of mountain cells, mean fill ratio of large components
0.92 in this window and 0.65-0.68 in the other two sampled seeds, mountains average
56.9 voxels against 36.6 on lowland and 42.3 on hills, and tile peaks span 45
voxels.

**Accepted limits.**

- Where a plate boundary is strong and the belt field agrees, a range follows a
  nearly straight bisector. The domain warp bends it, but a straight range is
  visible in some seeds. Judged preferable to shapeless blobs; the alternative
  (warping the tectonic field itself) would require the tectonic module to know
  about the mountain module.
- The fill ratio is still above a real mountain chain's. Ranges here are ranges
  *within a mountain province*, which is what the tuning was steered to.
- `mountain_scale`, `mountain_frequency` and the tectonic cell size remain the three
  knobs that matter; the internal constants are deliberately not exposed, because
  exposing six more tunables would multiply the parameter space without adding a
  capability.
