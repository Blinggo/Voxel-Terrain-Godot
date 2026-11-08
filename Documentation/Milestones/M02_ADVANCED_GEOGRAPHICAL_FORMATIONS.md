# M2 — Advanced Geographical Formations

**Status:** implemented and tested on Linux; awaiting owner review, and awaiting
owner testing in the Godot editor on Android.
**Date:** 2026-11-07
**Engine:** Godot 4.7.2-stable · Voxel Tools GDExtension 1.7x
**Generation version:** 2 (was 1 in M1 — M1 terrain is deliberately not reproduced)

---

## 1. Objectives

M2 raises the geography from *plausible noise* to *formations with structure*:

- **A. Mountain systems** — connected regions, long primary ridges, secondary
  ridges, individual peaks, varied heights, foothills, mountain valleys, natural
  transitions, irregular silhouettes. Explicitly *not* several layers of ridged
  noise over one another.
- **B. Valleys and basins** — broad and narrow valleys, mountain passes, enclosed
  basins, irregular depressions, transitions that follow plausible structure rather
  than being circles.
- **C. Plateaus** — large plateaus and smaller tablelands, rolling interiors,
  irregular eroded edges, stepped or layered transitions, integrated into the
  elevation pipeline.
- **D. Archipelagos and ocean geography** — recognisable island groups, isolated
  islands, varying sizes, continental shelves, irregular coastlines, bays,
  peninsulas, coastal lowlands; existing sea-level behaviour preserved.
- **E. Lightweight tectonic influence** — deterministic, independently sampleable,
  approximate plate regions and boundaries with convergent / divergent (and
  transform) character, driving mountain placement and large-scale elevation.
- **F. Seed diversity** — different seeds give different geographical identities.

The M1 architecture (ADR-0011) was extended, never replaced, and everything M1
established — determinism without an RNG object, chunk-independent sampling, the
node grid and cache, the module registry and versioning — still holds.

---

## 2. What was delivered

Six new fields, three new landform behaviours and a rebuilt mountain system:

| Field | Module | Output | What it is |
| --- | --- | --- | --- |
| `tectonics` | `TectonicsModule` | −1..1 signed | plate regions, boundary distance, convergent / divergent / transform character |
| `archipelago` | `ArchipelagoModule` | 0..1 | where island groups and lone islands belong (offshore only) |
| `coast_detail` | `CoastModule` | −1..1, shore-masked | bays, peninsulas, crinkled shoreline |
| `landmass` | `LandmassModule` | −1..1 | the land signal every other module now reads |
| `plateaus` | `PlateauModule` | 0..1, terraced | plateau / tableland mask with stepped margins |
| `valleys` | `ValleyModule` | 0..1.6 carve | valley network, passes, basins |

`MountainModule` was rewritten to version 2 (structural bands plus noise relief,
ADR-0015) and `SurfaceModule` to version 2 (a six-step composition, ADR-0017).

**Evidence that it is real terrain, not only passing tests:** sections 10 and 11 —
including the ocean, which now renders as water in every capture because of defect 3
in section 7 —
plus the three generated maps in
`Documentation/Milestones/screenshots/m02_map_seed_{1337,90210,4242}.png`. The three
seeds have visibly different identities: seed 1337 is one continent with a western
archipelago and a northern range system; seed 90210 is a landmass split by a large
inland sea with scattered massifs; seed 4242 is a narrower continent with wide
lowlands and a much smaller plateau fraction (0.8% against 6.8% of land). Measured
land fraction per seed: 55.0% / 65.7% / 47.1%.

---

## 3. Systems and the mathematics

### 3.1 Tectonic influence (`tectonics`, ADR-0014)

A jittered lattice of plate sites, one per cell of `plate_cell_size` (default 520
voxels). A coordinate belongs to the plate of its nearest site. Sites are confined to
the central half of their cell (`JITTER_SPAN` 0.25), each carrying a drift vector and
an interior bias derived by hashing the cell coordinate.

```
edge      = (d2 - d1) / 2                      Voronoi bisector distance
proximity = 1 - smoothstep(0, boundary_width, edge)
v         = drift(second) - drift(nearest)
n         = unit(second_site - nearest_site)
along     = v . n       across = v x n
stress    = (smoothstep(0, s, -along)                     uplift
             - 0.85 * smoothstep(0, s, along)             rift
             + 0.16 * smoothstep(0, 1.1s, |across|))      shear
            * proximity * rate
field     = clamp(stress + 0.12 * (interior - 0.5) * (1 - proximity), -1, 1)
```

Cost: one bounded dictionary lookup per node; the nine cell records are built once
per plate cell crossed (needs 18 `hash_coords` calls, about 41 us, amortised over
tens of thousands of nodes).

### 3.2 Mountain systems (`mountainness`, ADR-0015)

```
band       = smoothstep(0.02, 0.55, tectonics)         structural uplift
spine      = ridged fBm @ 0.006, domain-warped by 120 voxels
ribs       = ridged fBm @ 0.0192, weighted by spine height
ridge      = max(spine, ribs)
structural = band * (0.42 + 0.58 * ridge)              long, continuous, raised line
massif     = smoothstep(0.30, 0.78, belt)^2 * ridge    noise province
apron      = smoothstep(0.06, 0.60, raw_spine) * 0.26  foothills
relief     = max(structural, massif, apron * (0.35 + 0.65 * belt))
mountain   = relief * inland * (1 - 0.55 * rift) * variation
```

Six noise lookups per node, no allocations.

### 3.3 Valleys, passes and basins (`valleys`)

Ridged fields at 0.0022 (broad network), 0.0068 (tributaries, weighted by the broad
network) and an fBm at 0.0012 (basins). The carve amount is scaled by `1 + 0.45 *
mountainness`, which is what turns a valley crossing a range into a pass, and basins
are squared so the middle is deeper than the rim. No flow routing, no accumulation,
no water — the hierarchy is a frequency ratio, not a drainage calculation.

### 3.4 Plateaus (`plateaus`, ADR-0017)

A warped fBm at 0.0016 is sharpened into a mask (`0.60..0.78`) with a high-frequency
edge jitter, then **terraced** into `plateau_steps` (default 3) shelves:

```gdscript
terrace(mask, steps) = (floor(m*steps) + smoothstep(0.34, 0.66, frac(m*steps))) / steps
```

Every shelf boundary reproduces the unquantised value exactly, so the function is
continuous and only its gradient changes: the surface steps without ever jumping.
Measured: 190 of 283 margin columns sit on a shelf level, and the terrace's largest
per-sample step is 0.0023 against a jump of 0.333.

The plateau **level** is `base + plateau_uplift` and the surface blends towards it,
removing relief rather than displacing it. Measured interior relief: 1.52 voxels per
16 against 6.04 on open land.

### 3.5 Archipelagos and coastline (ADR-0017)

```
archipelago   = max(smoothstep(0.50,0.76, group) * smoothstep(0.44,0.74, cluster),
                    smoothstep(0.72,0.88, lone) * 0.70) * offshore_gate
coast_detail  = (fine * 0.62 * tight_mask + shape * 0.38 * wide_mask) * wide_mask
```

Islands are islands *because they are pushed up*, not because the continent was
moved: `landmass = continentalness + archipelago * 0.55 + coast_detail * 0.14`.
Correlation of `landmass` with `continentalness` is 0.9623 over 2304 samples, and
only 7.8% of columns change side of the waterline — the layout is preserved and only
the shoreline and the open ocean change.

### 3.6 Surface composition (`surface`, ADR-0017)

Seafloor → land base → relief → plateau blend → valley carve → coastal softening,
each step documented in the module and enforced by a test.

---

## 4. Research references and the licence review

Research was time-boxed and used for **algorithmic study only**. No source code was
copied from any project. Licence positions were checked before reading code, not
after.

| Source | Licence | Use in M2 |
| --- | --- | --- |
| `Guy-Shalev/terrain-generator` | **MIT** | M1's main algorithmic reference; the falloff-masked uplift idea survives as `proximity` |
| `Auburn/FastNoiseLite` | **MIT** | reached only through Godot's built-in `FastNoiseLite`, as in M1 |
| `LibreTerrain` (EllisonDigital) | **MIT / Apache-2.0** dual | conceptual: a plateau is a *terrace* of a shaped mask, ridge and mountain are distinct operations, distance is a first-class mask. It is a node-graph authoring tool, not a streaming generator, so nothing transfers structurally |
| `jcksncllwy/planet_heightmap_generation` ("World Orogen") | **GPL-3.0** | concepts only — its pipeline order (plates → collisions and stress → distance fields → elevation, with rift valleys, island arcs and coastal roughening) informed the shape of ADR-0014. Copyleft: no code was read line by line or reproduced |
| `weigert/SimpleHydrology` | **no licence file** | conceptual only; hydrology is out of scope in M2 anyway |
| `James-Blackburn/FractalErode` | **no licence file** | conceptual only; erosion is out of scope |
| `louis-e/arnis` | Apache-2.0 | rejected: real-world-OSM-driven, not procedural |
| `azgaar/fantasy-map-generator` | `NOASSERTION` | conceptual only; not used |
| Goslin, *InfiniteDiffusion / Terrain Diffusion*, SIGGRAPH 2026 | paper | informed the *hierarchy* idea already present in the M1 pipeline (coarse continental structure refined by regional ranges then local relief). Not implementable here: it needs a trained diffusion model and a GPU, and the Android target has neither |
| Colton Hash, *Structured Terrain Generation* (article) | article | concept: accumulate distance to neighbouring Voronoi cells to get ridges between mountains; our equivalent is the bisector-distance `proximity` |
| brashandplucky, *Procedural Island Generation III* (article) | article | concept: mountain distance field with a jaggedness parameter; informed the irregular-silhouette warp |
| Voronoi-plate terrain demos (reddit / public posts) | mixed | concept: Voronoi cells as plates with velocities, boundary type from relative motion |

**Selected approaches, and what was rejected:**

- Voronoi regional structure — *accepted* (tectonics), but on a jittered square
  lattice rather than a point set, because a point set needs a bounded neighbour
  search and the field must be sampleable at any coordinate.
- Distance fields — *accepted* as the basis of boundary proximity.
- Domain-warped ridge fields — *accepted* for range shape and coastline crinkle.
- Directional ridge functions (explicit per-range axes) — *rejected*: a range axis
  per region needs a per-region table, which is a persistent map by another name;
  the tectonic band supplies direction instead.
- Full plate simulation, hydraulic erosion, flow-based valley routing, climate — all
  out of scope for M2 and deferred.

---

## 5. Architecture changes

Nothing in the M1 architecture changed shape. The additions are within it:

```
detail          (independent, per-column)
continentalness (independent)                       raw continental layout
tectonics       (independent)                       NEW  plate regions and boundaries
archipelago     <- continentalness                  NEW  island groups
coast_detail    <- continentalness                  NEW  bays and peninsulas
landmass        <- continentalness, archipelago, coast_detail   NEW  composed land signal
elevation       <- landmass                         (was: continentalness)
mountainness    <- landmass, tectonics              (v2, was: continentalness)
hills           <- landmass, mountainness           (was: continentalness)
plateaus        <- landmass                         NEW
valleys         <- landmass, mountainness           NEW
surface         <- landmass, elevation, mountainness, hills, plateaus, valleys   (v2)
```

- One registration site (`TerrainGenerationStack._register_modules`), unchanged
  pattern. Registry resolves the order; the resolved order is asserted by a test.
- Every module still owns exactly one field, so the one-field-per-module limit
  recorded in M1 still holds and was not exceeded: no module needed a second output,
  because the composed `landmass` field carries the island and coast corrections for
  everyone.
- `GeographicSurface` grew no new pipeline knowledge. `classify_at` and
  `describe_at` report the M2 fields, and `SurfaceModule.classify` gained `plateau`
  and `valley` categories next to `mountains` / `hills` / `plains`.
- `WorldConfig` gained eleven parameters (section 9) and `generation_version` moved
  to 2. `duplicate_config()` and `to_dictionary()` were extended in the same order.
- The debug panel reports two field lines instead of one, so the owner can read
  `land`, `mtn`, `tec`, `plt` and `val` while testing in the editor.
- `scenes/main.tscn` title is now "Procedural World — M2".
- `VoxelWorld` gained one per-frame behaviour: it keeps the sea plane under the
  streaming viewer. Nothing in the pipeline changed; this is a visual ownership fix
  (defect 3 in section 7).

---

## 6. Determinism decisions

Unchanged from M1 and re-verified for every new field:

- No `RandomNumberGenerator`, no global state, no clock. A value is
  `f(world seed, FNV-1a of module id, module version, generation version, absolute
  x, z)`.
- The tectonic plate layout is itself derived by hashing cell coordinates, so the
  plates are the same on every run, in every chunk, in any order, on any thread.
- The per-cell and per-neighbourhood caches are pure memos: clearing them changes
  nothing (tested), and the node cache on/off comparison covers the new fields.
- New in M2: `TerrainHash.unit_from_hash`, `unit_slice` and `combine_pair` (an
  order-independent mix, for edges described identically from both sides).
- `generation_version = 2` is deliberate: the land signal the pipeline reads changed,
  so M1 terrain is not reproduced by design. Reverting to 1 does not restore M1
  terrain either, because the module set changed — this is recorded rather than
  glossed.

**Measured:** two builds of the same seed agree on 1008 of 1008 field samples; a
different seed differs on 95–99% of active samples in every field; reversing the
sample order changes nothing; the cache on/off comparison is identical over 144
columns.

---

## 7. Three real defects found and fixed

The first two were found by measurement, produced visible cliffs, and are documented
in ADR-0016 so they are not rediscovered. The third is the reason every earlier M2
capture showed terrain floating over a grey background with a blue band at the
horizon, and it is the one that changed the visual evidence most.

1. **Triple-point swap (Voronoi medial axis).** At a point equidistant from three
   plate sites, the second-nearest site swaps sides and the boundary normal flips.
   Distance to the bisector stays continuous; the drift decomposition does not.
   *Symptom:* a one-voxel cliff through the middle of a range — `tectonics` jumping
   0.024 → 0.665 and the surface 43.8 → 68.8 voxels between adjacent columns.
   *Fix:* track the third-nearest site and blend the two candidate pairs over a
   30-voxel tie window.
2. **Near-coincident sites.** With full-cell jitter two neighbouring sites could land
   a few voxels apart, where a bisector normal is meaningless. *Symptom:* a 0 → 0.41
   step. *Fix:* confine sites to the central half of each cell, which makes the
   degeneracy impossible rather than tolerated.

3. **The sea plane was pinned to the world origin.** Not a continuity defect but
   the same class of mistake — a value that is right near the origin and wrong
   everywhere else. The water plane is 2048 voxels across and was built at
   `Vector3(0, sea_level, 0)`, so a viewer more than ~1000 voxels from the origin —
   including every capture taken on a landmark out at z = -1400 — saw terrain
   floating over the background with a sliver of blue at the horizon. This is why
   earlier M2 captures showed no water: the capture scene was fine, the water was
   somewhere else. `VoxelWorld._process` now keeps the plane under the streaming
   viewer (one `Vector3` write per frame, viewer cached on first resolve). Every
   screenshot in section 10 was retaken afterwards, and the sea is visible in all of
   them.

Final measured continuity (max adjacent-voxel step, 6000 random samples over
±2000 voxels):

| Field | Max step |
| --- | --- |
| `continentalness` | 0.023 |
| `landmass` | 0.084 |
| `tectonics` | 0.148 |
| `archipelago` | 0.159 |
| `coast_detail` | 0.059 |
| `mountainness` | 0.175 |
| `plateaus` | 0.271 |
| `valleys` | 0.416 |
| `hills` (M1, for scale) | 0.362 |
| composed surface | 4.61 voxels (limit 8) |

Cross-block-border continuity: 2.84 voxels. Scattered single-coordinate sampling
against block sampling: identical. Plate-cell borders: no seam (largest step 0.172).

---

## 8. Landform interaction (what happens where two landforms overlap)

Recorded because overlap is where naive compositions fail:

- **Plateau over range** — the plateau mask is faded by up to 85% where
  `mountainness` is high, so the range is not levelled. Without this, the plateau
  (composed after relief) erased every peak it covered.
- **Valley through range** — carving is scaled *up* inside mountains (that is the
  pass) but limited to `base - 3` voxels, so a deep valley cuts a notch instead of
  removing the range. Without the limit, a 24-voxel carve turned a 30-voxel range
  into a plain.
- **Valley across a plateau** — carving is faded by 90% on a plateau top, so the
  plateau stays level and only its margin is dissected.
- **Rift through a mountain province** — tectonic rift suppresses mountainness by up
  to 55%, so a province does not cross its own rift.
- **Island in mountain country** — the inland gate was lowered so islands carry
  relief; the surface composer's own squared inland ramp still keeps the shoreline
  gentle (worst waterline slope 0.72 voxels/column, mean 0.18).

---

## 9. Configuration added in M2

| Parameter | Default | Effect |
| --- | --- | --- |
| `plate_cell_size` | 520 | plate size, and therefore the spacing of structural ranges |
| `plate_boundary_width` | 110 | width of the band tectonic influence acts over |
| `archipelago_frequency` | 0.0011 | island-group size and spacing |
| `coast_frequency` | 0.008 | shoreline detail scale |
| `island_strength` | 0.55 | how hard islands push the seafloor up |
| `coast_strength` | 0.14 | how far coastline detail may perturb the land signal |
| `valley_frequency` | 0.0022 | valley length and spacing |
| `valley_depth` | 0.26 | depth of a full-strength valley, × `terrain_height` |
| `plateau_frequency` | 0.0016 | plateau size |
| `plateau_uplift` | 26 | height of a plateau above the base surface, in voxels |
| `plateau_steps` | 3 | shelves in a plateau margin (1 disables terracing) |

`plate_boundary_width` was the one tuning value left open at the end of
development. 110 is delivered: a 150-voxel band was tried and widened each range
until the structural band and the noise-province term stopped being separable, which
is the opposite of what ADR-0015 is for. Every number in section 11 was measured at
110.

Changed defaults from M1: `mountain_scale` 1.5 → 1.8. Unchanged: `terrain_height` 26,
`sea_level` 20, `base_height` 24, `hill_scale` 0.60, `detail_scale` 0.09, all M1
frequencies, `sampling_stride` 8, `view_distance_voxels` 128.

Internal constants that were deliberately *not* exposed are listed with their
reasoning in the module headers (for example `BAND_BASE`, `APRON_WEIGHT`,
`TIE_WIDTH`, `PLATEAU_VALLEY_FADE`): exposing another ten knobs would multiply the
tuning space without adding a capability.

---

## 10. Visual evidence

All captures were made with `tests/capture_screenshot.tscn` against the real scene,
and are in `Documentation/Milestones/screenshots/`:

| File | Shows | Field readings under the camera |
| --- | --- | --- |
| `m02_mountains_seed_1337.png` | a mountain system: a connected massif with several summits, a col between them, valley notches, and sea on both sides | `mtn 0.51 tec +0.60 val 0.44` |
| `m02_plateau_seed_1337.png` | terraced upland with brows and a broad level shoulder — the *approach* to a plateau, not its top | `plt 0.00 val 1.01` |
| `m02_highland_coast_seed_1337.png` | plateau-top terrain descending to a coast with the sea behind it; the stepped margin is visible in the left foreground | `plt 0.67 mtn 0.09`, terrain `plateau @ 50.1` |
| `m02_island_seed_1337.png` | a hilly island standing in open sea with its shelf visible through the water | `land +0.14 mtn 0.24` |
| `m02_shelf_and_offshore_island_seed_1337.png` | deep ocean → shelf → land, with an offshore island and a lone stack; the translucent sea over the seafloor is the shelf model | `land -0.35`, terrain `deep_ocean @ 4.6` |
| `m02_map_seed_1337.png` | 1024² hillshaded map: continent, western archipelago, northern ranges, valley network |
| `m02_map_seed_90210.png` | a completely different identity: landmass split by an inland sea, scattered massifs |
| `m02_map_seed_4242.png` | a third identity: narrow continent, wide lowlands, small plateau fraction |

**What the screenshots do and do not prove.** They prove the formations exist in the
rendered voxel terrain, are visible from the game camera at the default view
distance, and that the ocean reads as water once the plane follows the camera (see
defect 3 in section 7). Captions above quote the debug panel in each image, so the
claim can be checked against the pixels rather than trusted. They do not prove appearance on a device, and they are Linux software-rendered
(llvmpipe) at 7–9 fps, which says nothing about Android frame rate.

**A capture-tool caveat discovered in M2.** `VoxelViewer.view_distance_vertical_ratio`
is 0.5, so terrain streams within roughly ±64 voxels vertically of the viewer. A
capture whose camera orbits 100+ voxels above the ground renders sky and sea and no
terrain at all, which is what several early M2 captures showed. Captures must keep
the camera within about 50 voxels of the local surface (`--distance` 110–130 with
`--pitch` −13° to −16° works at the default view distance). This affects *capture
framing only*: an in-game camera sits near the ground, and M1's screenshots were taken
the same way.

---

## 11. Automated tests executed

Full suite, Linux, Godot 4.7.2-stable, `DISPLAY=:99 ./tests/run_tests.sh`:
**274 checks, 0 failures, 0 script errors, exit 0.**

| Suite | Checks | Result |
| --- | --- | --- |
| core | 17 | PASS |
| generation (M1) | **57** (was reporting 45) | PASS |
| **m2 (new)** | **63** | **PASS** |
| voxel | **27** (was 24) | PASS |
| reliability | 24 | PASS |
| perf | 41 | PASS |
| ui input (windowed, real display) | 45 | PASS |

Every number below is printed by the run itself.

**M2 determinism (7 checks).** Identical fields across two builds (1008 samples);
every field differs between seeds (95–99% of active samples); sample order does not
matter; repeat stability; node cache cannot change terrain; generation-version bump
reshuffles the tectonic layout (91/100); the twelve modules execute in dependency
order and every one is registered exactly once.

**M2 continuity (6 checks).** Tectonic field has no discontinuity (worst 0.181);
every field continuous at voxel resolution (`tectonics` 0.112, `archipelago` 0.143,
`coast_detail` 0.048, `landmass` 0.080, `mountainness` 0.176, `valleys` 0.334,
`plateaus` 0.256); no seam across plate cell borders (0.172); no surface cliff (worst
3.03 voxels, limit 8); block borders continuous (2.84); isolated sampling matches
block sampling.

**M2 geography (18 checks).** Mountains stand 20.3 voxels above lowland and 14.6
above hills; mountain regions are connected (693 cells, largest component 26%, only
12 components of ≥12 cells); tile peaks span 45.1 voxels (ranges differ in height);
convergent boundaries carry 2.4× the mountain mass of plate interiors; rift
boundaries sit 2.6 voxels lower than interiors; valley floors are 6.0 voxels below
their surroundings; valleys form a network (1363 cells, largest component 31%);
enclosed depressions occur (188 in 1614 land columns); plateau interiors are 4×
flatter than open land (1.52 vs 6.04); 190 of 283 plateau margin columns sit on a
shelf level; the terrace is monotonic, never jumps, reproduces shelf boundaries
exactly (>0.000000 error) and is 68% flat; the archipelago field creates islands (520
cells) grouped into components (largest 7% of island cells); islands carry relief (up
to 55.6 voxels); the shoreline is a beach (worst 0.72, mean 0.18 voxels/column);
shelves exist between land and deep water; `landmass` correlates 0.9623 with
`continentalness` and only 7.8% of columns change side of the waterline; deep ocean
is below sea level and inland is above it (0 wrong of 389 and 667); every seed has
both ocean and land (56% / 66% / 46%).

**M2 integration and configurability (8 checks).** Each module resolves and evaluates
in isolation with synthetic inputs; valleys and plateaus vanish under the ocean;
landmass equals the documented sum exactly; uplift builds more mountain than a rift
at the same coordinate; island strength, valley depth and mountain scale are each
independently configurable (zeroing island strength restores
`landmass = continentalness + coast`; zeroing valley depth raises 267 columns and
lowers none; zeroing mountain scale drops the peak from 71.1 to 57.2); the block
height array matches the surface in mountain terrain (68.7-voxel peak).

**M2 performance (3 checks).** Warm block time, per-node cost and cache activity —
numbers in section 12.

**A defect in the M1 suite itself, found while closing M2 — recorded because it
changes an earlier number.** `report.check_equal()` took exactly three arguments,
but six call sites in `tests/suites/generation_suite.gd` passed a fourth. In GDScript
an over-argumented call raises at runtime and *does not fail the run*: each of those
checks was silently skipped, and so was the remainder of the test function it sat in.
The suite therefore printed `RESULT: PASS (45 checks)` while executing fewer than 57.
`check_equal` now takes an optional `detail` argument (the fix that cannot be
forgotten), all 57 checks execute, all 57 pass, and the run asserts **zero
`SCRIPT ERROR` lines**. The M1 milestone document carries a correction note. This is
also why the M2 section above distinguishes executed from written.

**New in M2, the sea-plane regression (3 checks, voxel suite).** The world puts a
`SeaPlane` in the scene; it is centred under the streaming viewer to within a voxel;
it sits exactly at `sea_level + 0.02`. These fail outright on the pre-fix code, which
is what makes defect 3 in section 7 a fixed defect rather than a claim.

**M1 and earlier, still passing unchanged.** core 17, generation 57, voxel 27
(including Voxel Tools integration and the block generator), reliability 24, perf 41,
ui 45 — all 196 M1-era checks pass with the M2 pipeline in place, which is the
integration requirement: Voxel Tools, streaming, seeding, the debug panel and the
four numeric fields were not disturbed.

**Additional measurement runs (tools, not tests):**

- `tests/benchmark.gd`: 38.2 µs/block (best of three passes, 250 blocks), streaming
  region meshed in 0.13 s.
- Continuity sweeps and range-statistics sweeps were run during development with
  throwaway probe scripts. Those scripts were **deleted before hand-off**; the same
  measurements now live inside the M2 suite (section 7 and section 11 are what the
  suite prints), so nothing depends on a tool that is no longer in the tree.

---

## 12. Tests written but not executed

Written and executed are separated deliberately.

**Executed:** everything in section 11 (274 checks, plus the benchmark and the
generated maps).

**Not executed, and why:**

- **Android device tests** — none. No APK was built, by instruction. The Android
  Editor checklist is in section 15; behaviour on the device is *unknown* until the
  owner runs it.
- **Windows** — none. Nothing in M2 changes Windows-specific behaviour, but nothing
  was run on Windows either, so no claim is made.
- **Cross-platform bit-identical determinism** — not demonstrated. The M2 fields add
  no floating-point structure that M1 did not already have (all noise comes from the
  same `FastNoiseLite`, all hashing is integer), but "intended to be identical" is
  not "demonstrated identical", so it stays unverified.
- **Multi-threaded tearing under real streaming** — the M1 test samples four threads
  concurrently through the shared node cache and passes; the M2 additions add one
  more mutex-guarded cache (tectonic neighbourhoods) that was exercised single- and
  multi-threaded only through that same test shape, not under sustained streaming
  load.
- **Long-run memory behaviour** — the tectonic cache is bounded at 256
  neighbourhoods and clears wholesale, but no soak test measured resident memory over
  a long flight.

---

## 13. Performance findings

Measured on the development container (2 vCPU, software rendering). Device numbers
will differ; these are relative findings and absolute upper bounds.

| Measurement | M1 | M2 | Note |
| --- | --- | --- | --- |
| `tests/benchmark.gd`, best of 3 | 43.9 µs/block | **38.2 µs/block** | identical method and block shape (5x5x2, node cache warm): no regression |
| streaming region meshed (view distance 128, vertical ratio 0.5) | 0.18 s | **0.13 s** | machine variance between milestones is larger than any real difference |
| block over a **fresh, contiguous** region | 126 µs warm, 152 µs cache-disabled | **107 µs warm, 196 µs cold** | different probe shapes, so not a like-for-like comparison; see below |
| cost per node, full field set | ~3.3 µs (attribution estimate from a profile) | **16.6 µs (measured directly)** | 12 modules now against 6; the M1 figure was inferred, the M2 figure is timed |

The apparent contradiction between 38 µs in the benchmark and 107 µs on fresh
ground is a measurement artefact worth recording: `tests/benchmark.gd`
re-generates the *same* 25 block columns three times, so almost every node it
touches is already cached. A fresh 144-block region is the pessimistic and more
realistic streaming case. Both are reported; neither is presented as the other, and
the M1 numbers in the third row came from a differently shaped probe, so comparing
them line by line would be dishonest. What the comparison *does* support is that the
end-to-end measurement the project has always used - the benchmark and the streaming
time - did not get worse.

The per-node cost rising from an estimated 3.3 µs to a measured 16.6 µs is the
honest headline of this milestone: six new fields cost real time. Two caveats keep it
inside budget. First, the figure is per *node*, and there are only nine nodes per
block with most of them cached - the fresh-region measurement of 107 µs per block,
which is what streaming actually pays, includes all of that cost already and is lower
than M1's differently-shaped 126 µs warm probe. Second, the M1 figure was inferred
from a profile line ("9 nodes, ~15 noise lookups each: ~30 µs"), not timed the way
the M2 suite times it, so the ratio is not as clean as it looks. What is unambiguously
true is that the pipeline now performs roughly 34 noise lookups per node against
about 15.

**Why the extra node cost is acceptable.** Nine nodes per block, about three of them
new when streaming, gives roughly 50 µs of node work per block on one thread, inside
the 107 µs warm measurement. Voxel Tools streams on its own threads and the measured
end-to-end streaming time did not change. The cost that *was* avoided is the one that
mattered:

- **Hashing.** One `hash_coords` costs 2.3 µs, one dictionary lookup 0.17 µs, one
  noise sample 0.1 µs (all measured). Recomputing the nine tectonic cells per node
  would be 41 µs per node — twenty times the whole node budget. Hence the
  neighbourhood cache, justified by measurement rather than by intuition, bounded at
  256 entries (45 floats each) and guarded by a mutex.
- **No per-voxel work was added.** Every new field is a node-grid field. The only
  per-column path is still the M1 detail term. No new allocations occur in ordinary
  sampling: the tectonic module reuses one cached array, and the new modules allocate
  nothing per node.
- **No new cache was added anywhere else.** Plateaus, valleys, mountains, islands and
  coast detail are pure arithmetic on noise and inputs.

**Honest caveat:** 16.6 µs per node for twelve modules is dominated by GDScript call
overhead (~19 `FastNoiseLite` calls per node) rather than by arithmetic. If M3 adds
more per-node fields, the right next step is to reduce *calls* (share a noise sample
between terms, or merge two fields) rather than to add caches.

---

## 14. Known limitations and unresolved issues

1. **Ranges can be straight.** Where a plate boundary dominates, a range follows a
   straight Voronoi bisector. The domain warp bends it, but some seeds show it.
2. **Mountain fill ratio is still high** (0.65–0.92 of the bounding box in sampled
   seeds). Ranges read as ranges inside a province rather than as thin chains.
3. **Plateau coverage varies a lot by seed** (6.8% / 3.9% / 0.8% of land). The
   plateau field is a thresholded noise field, so some seeds have almost none.
4. **Scattered single-cell seafloor dips** are visible in the hillshaded maps as
   isolated dark specks in open water — small negative spikes where coastline detail
   and the depth model interact. Cosmetic, not a discontinuity (continuity is
   tested).
5. **No water simulation.** The sea is a flat translucent plane that now follows the
   camera; a carved basin is held above sea level so it cannot fill. The plane has no
   depth, foam, refraction or shoreline interaction — it is a visual placeholder.
6. **Terracing on gentle slopes** (inherited from M1's blocky mesher) is more visible
   in M2 because ranges are steeper: a 1-voxel step across a shallow slope reads as
   corduroy.
7. **`generation_version` bump means M1 terrain is not reproducible** with M2 code.
8. **Voxel count grows with height.** `MAX_HEIGHT` is 96 and peaks reach 75;
   raising `mountain_scale` further will increase meshed voxels per column.
9. **Android and Windows untested.** No claim is made about either.
10. **The tectonic field saturates** at ±1 near strong boundaries (`clampf`), so
    intensity variation is compressed at the strongest margins.
11. **One field per module** still holds; a future module that genuinely needs two
    outputs would require an ADR, not a workaround.

---

## 15. Deferred features (explicitly out of scope for M2)

Rivers, hydraulic and thermal erosion, waterfalls, sea arches, caves, volcanoes,
biomes, climate, precipitation, weather, clouds, vegetation, structures, NPCs and
gameplay. None of them were implemented, and no partial scaffolding for them was
added. Also deferred: layered strata in plateau edges (the terraces are geometric,
not geological), and a water surface that follows carved terrain.

---

## 16. Continuation instructions

**To continue from here:**

1. Provision the tool chain: Godot 4.7.2-stable Linux binary, `Xvfb :99`,
   `--headless --import`, then `./tests/run_tests.sh` (needs `chmod +x` after a
   workspace restore). Baseline to beat: **274 checks, exit 0, zero `SCRIPT ERROR` lines**.
2. Read ADR-0014 through ADR-0017 before touching the pipeline. ADR-0016 in
   particular: any field that depends on a discrete regional choice must be
   continuous across that choice.
3. `_probe_*.gd` tools used during M2 tuning were removed before hand-off. If you need
   them again, the measurement code survives inside the M2 suite
   (`tests/suites/m2_generation_suite.gd`) and in `tests/benchmark.gd`.
4. For a new landform: add one module, one field, one line in
   `TerrainGenerationStack._register_modules`, one row in the `surface` dependency
   list if it changes height, and extend the M2 suite with a geography assertion
   that would fail if the landform were removed.
5. **A capture with no terrain in it is usually the camera, not the pipeline.** Check
   `viewer_vertical_ratio`: the camera must be within ~50 voxels of the ground at the
   default view distance.

**Android testing (owner, in the Godot editor, as instructed — no APK):**

1. Open the project in Godot 4.7.2 with the Android export configured as in
   `M00_02_ANDROID_TESTING_CHECKLIST.md`.
2. Deploy to the device from the editor.
3. Expect, on launch: ocean on one side, land on the other, the panel showing
   `land`, `mtn`, `tec`, `plt`, `val`.
4. Fly or walk inland until `mtn` rises above ~0.45 — the terrain should climb into
   ridges, not blobs. Look for a col between two high areas (that is a belt saddle).
5. Follow a green valley line (`val` > 0.4) into high ground: it should notch
   through, not stop.
6. Look for a plateau (`plt` > 0.6): a level top with a stepped margin.
7. Look seaward for an island group: several islands within sight of each other,
   with shallow water around them.
8. Regenerate, then use Random seed a few times: each seed should be a different
   landscape, not the same one shifted.
9. Turn the four numeric fields (terrain height, frequency, view distance, seed):
   they must still work exactly as in M1.
10. Report frame rate, any missing-chunk artefacts and any visible seam to the
    milestone owner. Do not report a device test as passed unless it was run.

**Recommended next milestone:** M3 — hydrography and materials on top of this
foundation: sea-level-aware water in carved basins and valley floors, a river
network derived from the existing valley field (drainage direction from the composed
surface gradient, not a full simulation), and biome/strata colouring driven by the
fields that now exist. The M2 fields were designed to be that substrate: `valleys`
already marks the network, `mountainness` the exposure, `plateaus` the flat ground,
and `tectonics` the geological regions.
