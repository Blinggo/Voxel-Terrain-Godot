# M1 — Deterministic Terrain Foundation

**Status:** implemented, awaiting review
**Date:** 2026-11-07
**Engine:** Godot 4.7.2-stable, Voxel Tools 1.7 GDExtension
**Verified on:** Linux x86_64 (software Vulkan, 2 vCPU). Android and Windows were
**not** re-tested in this milestone — see [§12](#12-known-limitations).

---

## 1. What this milestone delivers

M0.2 proved a pipeline: one band of noise, a voxel adapter, streaming, a touch
camera, a debug overlay. M1 replaces the single noise band with a **geographic
generation architecture** and drives the live Voxel Tools terrain from it.

Concretely:

- a module pipeline (registration, dependency-ordered execution, per-module
  random streams, configuration snapshots, independent testability);
- five geographic fields — **continentalness, multi-scale elevation, mountains,
  hills** and a **surface composer** — plus a full-resolution **detail** term;
- deterministic coordinate hashing that does not rely on any global RNG;
- a two-resolution sampling scheme (regional node grid + per-column detail) with
  a thread-safe node cache;
- real 3D terrain that shows oceans, coasts, plains, hills and continuous
  mountain ranges, streams around the existing camera, and regenerates
  identically from the same seed;
- 45 new automated checks; 196 checks in total, all passing.

Deliberately **not** in M1: climate, hydrology, rivers, erosion, volcanoes,
structures, vegetation, caves, multiplayer. The architecture leaves room for
each; nothing is stubbed.

---

## 2. Files created

| File | Role |
|---|---|
| `src/core/generation/terrain_hash.gd` | Deterministic coordinate hashing (32-bit lanes, §5). |
| `src/core/generation/generation_context.gd` | Seed + generation version + frozen config; per-module noise seeds. |
| `src/core/generation/generation_module.gd` | Module contract: id, version, dependencies, one output field, `evaluate_node`, optional `add_columns`. |
| `src/core/generation/generation_registry.gd` | Registration, dependency resolution (Kahn), field-slot assignment, loud failures. |
| `src/core/generation/generation_engine.gd` | Executes modules on a node grid, caches nodes, interpolates, adds column terms, clamps to bounds. |
| `src/core/generation/terrain_generation_stack.gd` | The one place modules are registered; builds context → registry → engine. |
| `src/core/generation/geographic_surface.gd` | The surface the voxel layer sees: heights, raw fields, classification. |
| `src/core/generation/modules/continentalness_module.gd` | Domain-warped low-frequency continent field. |
| `src/core/generation/modules/elevation_module.gd` | Three-band broad elevation signal. |
| `src/core/generation/modules/mountain_module.gd` | Ridged fractal × tectonic belt mask × inland gate. |
| `src/core/generation/modules/hills_module.gd` | Shaped hills field, damped where mountains dominate. |
| `src/core/generation/modules/surface_module.gd` | Depth model, land base, relief ramp, coastal softening, classification. |
| `src/core/generation/modules/detail_module.gd` | Per-column fine roughness (the only per-column cost). |
| `tests/suites/generation_suite.gd` | 45 checks: determinism, fields, module system, integration. |
| `tests/render_map.gd` | Tool: hillshaded top-down map of the surface, for judging geography. This is what the field tuning was actually judged on (§10). |
| `Documentation/Milestones/M01_DETERMINISTIC_TERRAIN_FOUNDATION.md` | This document. |
| `Documentation/Decisions/ADR-0011-modular-generation-pipeline.md` | Pipeline architecture decision. |
| `Documentation/Decisions/ADR-0012-deterministic-coordinate-hashing.md` | Hashing decision. |
| `Documentation/Decisions/ADR-0013-two-resolution-sampling-and-node-cache.md` | Sampling and caching decision. |
| `Documentation/Milestones/screenshots/m01_*.png` | Four captures (§10). |

## 3. Files modified

| File | Change |
|---|---|
| `src/voxel/terrain_block_generator.gd` | Consumes `GeographicSurface`; one `sample_block_heights()` call per block instead of a noise call per column. |
| `src/world/voxel_world.gd` | Builds a `GeographicSurface` instead of a height field; adds the sea plane; status now reports terrain type and fields under the viewer. |
| `src/world/world_config.gd` | 15 new parameters (amplitudes, field frequencies, stride, sea level, generation version); all copied by `duplicate_config()`/`to_dictionary()`. |
| `src/world/main_scene.gd` | Startup camera searches outward for land instead of parking on the origin column. |
| `src/debug/debug_panel.gd` | Two new status lines: terrain type + height, continentalness/mountainness. |
| `scenes/main.tscn` | Title → "Procedural World — M1"; removed the embedded config overrides that duplicated defaults (see §11). |
| `tests/suites/core_suite.gd` | Retargeted from `TerrainHeightField` to `GeographicSurface`; same seam/order/concurrency guarantees. |
| `tests/suites/reliability_suite.gd`, `tests/benchmark.gd` | Build a surface instead of a height field. |
| `tests/test_runner.gd`, `tests/run_tests.sh` | New `generation` suite wired in (also part of `all`). |
| `tests/capture_screenshot.gd` | Optional `--center=x,z` so a capture can be framed on a landform. |

## 4. Files deleted

| File | Why |
|---|---|
| `src/core/terrain/terrain_height_field.gd` | Replaced by the module pipeline. Its contract (`get_surface_height(x, z)`, pure, coordinate-only) survives on `GeographicSurface`. |
| `src/core/noise/noise_source.gd`, `src/core/noise/fast_noise_lite_source.gd` | The `NoiseSource` indirection existed to keep the height field off `FastNoiseLite`. Modules now need fractal **type** configuration (ridged vs fBm) and domain warping, which the indirection never exposed, so it had become a wrapper that only added a virtual call per sample. Noise construction is centralised in `GenerationContext.make_noise()`, which is the new single point where an unseeded noise object could otherwise slip in. |

No working feature was removed. The terrain, streaming, camera, regenerate, random
seed, numeric fields, performance overlay and screenshot capture all still work,
as §11 records.

---

## 5. Determinism

### 5.1 The rule

Every generated value is a pure function of:

```
world seed  +  module id  +  module version  +  generation version  +  (x, z)
```

No global RNG, no `RandomNumberGenerator` instance, no clock, no accumulating
caches that feed back into values. Consequence: **generation order cannot affect
terrain**, chunk boundaries cannot differ from interior samples, and two threads
racing on the same node compute the same number.

### 5.2 Coordinate hashing

`TerrainHash` is hand-written. Godot's built-in `hash()` is not guaranteed stable
across engine versions, and a terrain world that silently changes when the engine
is upgraded is worse than one that fails loudly.

The hash is FNV-1a over the UTF-8 bytes of the module identifier, then MurmurHash3
`fmix32` mixing of:

- the world seed, split into two 32-bit words;
- the module key;
- the module version and the pipeline generation version;
- x and z, each split into two 32-bit words.

**Why 32-bit lanes.** GDScript integers are 64-bit and wrap on overflow, but
literals at or above 2^63 cannot be written (`0x9E3779B97F4A7C15` is a parse
error) and right-shifting a negative value is a parse error too. Staying inside
32-bit unsigned lanes keeps every intermediate value positive (so `>>` is legal)
and every product within `int64` before masking. The 64-bit split uses
`low = v & 0xFFFFFFFF` and `high = (v - low) / 2^32`, which is exact for negative
values as well — integer division truncates towards zero but `v - low` is an exact
multiple of 2^32 for both signs.

Verified by `tests/suites/generation_suite.gd`: 2000 hashed coordinates in
`[0, 1)`, negative and ±1e9 coordinates accepted, adjacent coordinates and
different seeds/modules/versions all producing different streams (500/500 each).

### 5.3 Independent streams

`GenerationContext.module_seed()` mixes the world seed with the module key and
both versions. Two modules never share a noise stream; bumping one module's
version reshuffles only that module; bumping `WorldConfig.generation_version`
deliberately reshuffles everything, which is how a breaking change is signalled.

A bug was caught here during development: `generation_version` was being stored
in the context but not folded into the seeds, so bumping it changed nothing. The
test `bumping the generation version changes the world` failed at 0 % and the
seed mix was fixed (now 99.6 % of columns differ).

### 5.4 What is *not* guaranteed

- **Cross-platform bit-identical output is not claimed.** Module maths uses
  `FastNoiseLite` (float32) and float arithmetic in GDScript; different CPU
  architectures or maths libraries may differ in the last bits. Reproduction is
  verified on the same machine and build. This is stated rather than glossed over
  because the project has never tested Android against Linux output.
- **Precision degrades far from the origin.** At |x| ≈ 1e9 the float32 noise
  lattice has ~0.125 units of resolution, so terrain is still valid, bounded and
  deterministic but coarse. Tests assert validity and determinism there and print
  the observation rather than pretending quality is unchanged.
- Within those limits, determinism is exact: the suite compares floats with `==`.

---

## 6. Module system

### 6.1 Contract

A module (`GenerationModule`) owns **one scalar field**. It declares:

- `id` — stable, participates in the random stream (renaming changes terrain);
- `version` — bumping reshuffles only this module;
- `dependencies` — ids it reads;
- `output_field` — the name it writes.

and implements `configure(context)` (build noise once, freeze configuration) and
`evaluate_node(x, z, values)` (write this module's slot). A module that needs
full-resolution output sets `contributes_columns` and implements
`add_columns(heights, origin, size)` — bulk, because 256 scripted calls per block
would cost more than the arithmetic inside them.

The composer publishes world-unit limits via `get_output_bounds()`; the engine
clamps to them after every column term, so no module can push the surface outside
the range the mesher, camera and tests assume. (This was also a real bug: at
|x| ≈ 1e9 unclamped detail noise produced a surface height of 519 voxels.)

### 6.2 Registration and ordering

Registration happens in exactly one place — `TerrainGenerationStack._register_modules()`:

```gdscript
detail, continentalness, elevation, mountainness, hills, surface
```

Execution order comes from the declared dependencies, not from that list:

```
detail          (independent; per-column)
continentalness (independent)
elevation       <- continentalness
mountainness    <- continentalness
hills           <- continentalness, mountainness
surface         <- continentalness, elevation, mountainness, hills
```

`GenerationRegistry.resolve()` runs Kahn's algorithm with registration order as
the tie-break, so the order is deterministic across platforms. It fails loudly
(with the module named) on a duplicate id, a duplicate output field, an unknown
dependency or a cycle. `GenerationEngine` refuses to run against an unresolved
registry.

### 6.3 Adding a module later

1. Write a subclass; give it a new id and declare what it reads.
2. Add one line in `_register_modules()`.

Nothing else changes, and modules that do not depend on it produce **bit-identical**
values. That is tested, not asserted: `_test_adding_a_module_disturbs_nothing`
registers an extra module and compares 100 continentalness samples before and
after (0 differences).

### 6.4 Configuration snapshots

`GeographicSurface` duplicates the `WorldConfig` it is given, and
`VoxelWorld.rebuild()` passes its own snapshot to both the surface and the
palette. Editing the inspector resource mid-generation cannot change terrain that
is already being produced. `_test_configuration_is_snapshotted` edits the live
resource after building and confirms 100 heights are unchanged.

---

## 7. Geographical algorithms

All fields are dimensionless (except the composer), sampled on a node grid 8
voxels apart, and combined only by the surface module.

### 7.1 Continentalness — `[-1, 1]`

Low-frequency fractal simplex (frequency 0.0014, 3 octaves), **domain-warped** by
two independent noise fields at 1.7× the base frequency with an amplitude of 260
voxels. The warp is what prevents a visible lattice: continent shapes bend and
pinch instead of repeating on the noise period.

Measured distribution over 1024²: min −0.517, p10 −0.279, median 0.030, p90 0.321,
max 0.633. The thresholds in the composer and classifier are calibrated to *this*
distribution rather than to round numbers — an earlier version used `0.30` as the
"inland" edge and turned 39 % of the map into "coast", so relief never developed.

### 7.2 Elevation — `[-1, 1]`, multi-scale

Three independent bands at 1×, 2.7× and 7× the base frequency (0.0025), weighted
0.60 / 0.28 / 0.12 so the output stays in range: broad regional tilts, medium
basins, small swells. Damped under deep ocean (it depends on continentalness),
because the seafloor's shape comes from the depth model instead.

### 7.3 Mountains — `[0, 1]`

Three multiplied terms, each earning its place:

1. **Ridged fractal** (frequency 0.006, 3 octaves, `FRACTAL_RIDGED`) — ridged noise
   builds crests along continuous lines instead of isolated bumps, which is the
   difference between a range and a field of spikes. Mapped through
   smoothstep(0.38, 0.88) so only real crests read as mountains.
2. **Belt mask** — a low-frequency field (0.35× mountain frequency) that decides
   which parts of a continent are tectonically active, giving mountain *provinces*
   separated by wide lowlands instead of mountains sprayed everywhere.
3. **Inland gate** — smoothstep(0.10, 0.30) on continentalness, so ranges begin well
   behind the shoreline.

Measured: 9.7 % of a 1024² area at or above the mountain threshold; **0.08 %
isolated cells** on a 4-voxel cell grid (connectivity test threshold: 5 %).

### 7.4 Hills — `[0, 1]`

fBm at 0.02, shaped by `smoothstep(0.28, 0.84)` then `pow(·, 1.9)`. The power curve
is what makes plains genuinely flat rather than "slightly less hilly": the typical
cell (raw ≈ 0.5) lands near 0.1, while the upper tail reaches real relief. Damped
by `1 − 0.55·mountainness` so ranges are not decorated with unrelated bumps.

Measured separation over 384² (mean |Δh| per adjacent column):

| terrain | roughness | mean height |
|---|---|---|
| plains | 0.44 | 37.3 |
| hills | 0.63 | 42.2 |
| mountains | — | 61.2 |

Hills are 1.44× rougher than plains and 4.9 voxels higher; mountains rise 19 voxels
above hills. Mountains are **not** rougher than hills at one-voxel scale — their
slopes are long and smooth — which is why the test asserts height separation there
rather than a roughness ratio.

### 7.5 Surface composition (the only world-unit module)

```
land      = smoothstep(-0.02, 0.14, c)
seafloor  = sea − ocean_depth · (1 − smoothstep(-0.35, -0.02, c))
land_base = base_height + inland_rise·land + elevation_gain·(e·0.5 + 0.5)
base      = lerp(seafloor, land_base, land)
relief    = (hills·hill_scale + mountains·mountain_scale) · terrain_height · ramp(c)
ramp(c)   = 0.25 + 0.75 · smoothstep(-0.02, 0.34, c)^1.5
height    = clamp(soften_coast(base + relief), 2, 96)
```

Three deliberate properties:

- **The waterline is at a continentalness contour, not a chosen voxel row.** At
  `c = OCEAN_EDGE` the land base equals sea level by construction, so coastlines
  follow a smooth contour.
- **Relief ramps in with distance inland** (and keeps a 25 % floor so coastal
  ground is gently undulating, not a dead plate). Without the ramp a mountain belt
  reaching the shore produced a 33-voxel drop over 24 voxels — a scarp, which the
  milestone forbids.
- **Coastal softening** compresses height towards sea level inside a 3.5-voxel
  band: `d' = B·sign(d)·(|d|/B)²`. Value and slope match the untouched function at
  the band edge and the slope is exactly zero at sea level, so a shoreline always
  starts with an apron and steepens inland — in both directions, which a
  direction-dependent rule could not guarantee.

Measured over 512²: mean |Δh| at the waterline **0.32 voxels/column**; steepest
column-to-column step **2.83 voxels** (limit 8.0); height range 2.8 – 77.0.

### 7.6 Detail — `[-1, 1]`, per column

fBm at `terrain_frequency`, amplitude `terrain_height · detail_scale`. One noise
lookup per column: the only per-voxel-column cost in the pipeline. Clamped to
±1 so extreme coordinates cannot inflate the surface.

---

## 8. Two resolutions, and why

Regional fields vary over hundreds of voxels; evaluating them per column repeats
almost the same answer 64 times inside one 16×16 block. The engine therefore:

1. evaluates all node-based modules on a grid spaced `sampling_stride` (8) voxels,
   snapped to absolute multiples of the stride;
2. bilinearly interpolates the composed surface for every column;
3. adds the per-column detail term in bulk;
4. clamps to the composer's bounds.

Node positions and interpolation weights are derived from **absolute** coordinates,
so a column shared by two blocks is computed through the same nodes and weights:
seams are impossible by construction, not patched up.

The node cache is a `Dictionary<Vector2i, PackedFloat32Array>` guarded by a
`Mutex`, capped at 8192 entries with approximate (clear-on-overflow) eviction.
Racing threads may both compute the same node; they produce the same value, so
the outcome equals a serial run. `_test_cache_does_not_change_terrain` compares
2304 heights with the cache on and off (0 differences), and the concurrency test
runs 4 threads × 512 columns through the shared cache.

---

## 9. Open-source research

Research was done before implementation, as required. Licence checked for every
project before any code was read for ideas.

| Project | Licence | Language | Verdict |
|---|---|---|---|
| [Guy-Shalev/terrain-generator](https://github.com/Guy-Shalev/terrain-generator) | **MIT** | Python/NumPy | **Selected as the main reference.** Plate-tectonics model: elevation = amplitude × falloff from the nearest plate boundary; collision → broad high range, subduction → trench + volcanic arc, rift → valley/mid-ocean ridge, transform → shear scar. Helpers `_ramp(d,w)=exp(-d/w)` and `_band` gaussian falloffs. Also: Perlin fBm with a ridged variant and `warp(field,…)`. |
| [Auburn/FastNoiseLite](https://github.com/Auburn/FastNoiseLite) | **MIT** | C/C++/C#/JS/Rust/… | **Used directly** — it is already inside Godot as `FastNoiseLite`. No porting: `FRACTAL_FBM`, `FRACTAL_RIDGED`, simplex types and seeding are all engine-native. |
| [weigert/SimpleHydrology](https://github.com/weigert/SimpleHydrology) | **no licence file** | C++ | **Reference only, no code.** Useful conceptual model for a future hydrology milestone; unusable legally until a licence appears. |
| [James-Blackburn/FractalErode](https://github.com/James-Blackburn/FractalErode) | **no licence file** | C | **Reference only, no code.** Deferred to a future erosion milestone. |
| [louis-e/arnis](https://github.com/louis-e/arnis) | Apache-2.0 | Rust | **Rejected.** Generation is driven by real-world OSM data, not procedural fields; nothing applies. (Apache-2.0 would also add NOTICE/patent obligations.) |
| [azgaar/fantasy-map-generator](https://github.com/azgaar/fantasy-map-generator) | SPDX `NOASSERTION` | JavaScript | **Conceptual reference only.** Useful for the continent → climate layering idea; licence unclear, so no code. |

### Licence findings and what was actually taken

- **No source code was copied from any project.** The two MIT projects informed the
  *ideas*; the implementation is written against Godot's own noise resource.
- From *terrain-generator* (MIT): the concepts of (a) masking relief amplitude by a
  smooth falloff from a boundary — implemented as the **belt mask**, and (b)
  displacing a field's sample coordinate with another noise — implemented as the
  **domain warp**. Both are re-expressed on `FastNoiseLite`; the plate simulation
  itself was rejected as too expensive for a mobile target (it needs neighbour
  search over a cell grid), and because a believable result is achievable with
  ridged fractal noise at a fraction of the cost.
- From *FastNoiseLite* (MIT): nothing, because Godot already ships it. Attribution
  is not required for use, but the project is credited in this document.
- Two of the five mandated projects have **no licence at all**. They were read for
  architecture only and are explicitly marked as "no code may be taken" in the
  table above so a later milestone cannot quietly copy from them.

---

## 10. Actual 3D results

All four captures are in `Documentation/Milestones/screenshots/`. They were
rendered by the existing screenshot tooling on Linux with software Vulkan, at the
shipped defaults (seed 1337 unless stated).

| Capture | What it shows |
|---|---|
| `m01_terrain_seed_1337.png` | Default launch framing: plains in the foreground, a hill massif behind, coastline and open ocean. Terrain type `plains`, continentalness +0.29. |
| `m01_terrain_seed_90210.png` | A different seed: a low archipelago with lagoons and coastal plains — the same code, a genuinely different world. |
| `m01_range_seed_1337.png` | Low-angle view of the highest massif near the origin (peak 77.0 voxels at (−136, 32)), ocean behind it. |
| `m01_map_seed_1337.png` | Top-down hillshaded map of 1024², generated from the same surface: continents, shelf depth, sand coastlines and a connected mountain belt. This is the clearest single view of the geography, and it is how the field tuning was actually judged. |

Observed in the live scene (`get_status()`, shown in the overlay):

- `terrain` line reports the classified type and surface height under the viewer,
  `fields` line reports continentalness and mountainness — e.g. `plains @ 36.7`,
  `cont +0.29 mtn 0.09`.
- Streaming reaches `ready` at view distance 128 in **0.18 s**.
- 0 dropped block loads / 0 dropped meshes across all capture runs.
- Regenerating with the same seed reproduces the same world (checked by the voxel
  suite's hash comparison and by the screenshots below being re-renderable).

Known visual characteristics, stated plainly:

- Gentle slopes read as terraces. This is inherent to voxel terrain with column
  heights quantised to integers; the M1 detail term (frequency 0.022) breaks the
  terraces up so they are not long contour lines, but they are visible.
- Low-lying coastal plains are large on some seeds (90210 in particular). That is
  a consequence of the relief ramp that removes coastal scarps; the alternative
  was cliffs.
- Water is a flat translucent plane at sea level. There is no water simulation,
  no depth shading and no shoreline foam in M1 — hydrology is a later milestone.

---

## 11. Performance

Measured on the CI-equivalent machine: 2 vCPU, software Vulkan (llvmpipe), Linux
x86_64. **Not** measured on a phone in this milestone.

### 11.1 Project benchmark (`tests/benchmark.tscn`)

| Metric | M0.1 (single noise band) | M1 (module pipeline) |
|---|---|---|
| Generator, best of 3 passes | 36 µs / 16³ block | **43.9 µs / 16³ block** |
| Throughput, single thread | ~27,700 blocks/s | **22,800 blocks/s** |
| Streaming region meshed (view distance 128, vertical ratio 0.5) | 0.16 s | **0.18 s** |

The benchmark uses the same shape as M0.1 (5×5×2 blocks), so node-cache reuse is
included. For an honest worst case, a standalone probe generating 400 blocks
spread over 256×256 voxels measured **126 µs/block with the cache warm** and
**152 µs/block with the cache disabled** — the cost of a 256-column block is
dominated by the interpolation loop and the 256 detail-noise calls, which
together account for ~90 µs.

### 11.2 Where the time goes (per 16×16 block)

| Component | Cost |
|---|---|
| Node evaluation (9 nodes, ~15 noise lookups each) | ~30 µs, mostly amortised by the cache |
| Bilinear interpolation for 256 columns | ~50 µs |
| Detail noise, 256 columns | ~39 µs |
| Column-module dispatch (bulk) | ~1 µs |

### 11.3 Design consequences

- No per-voxel maths: the generator does array lookups and `fill_area` calls, and
  the surface is evaluated at 1/64 the column count for regional fields.
- No GPU compute, no shaders, no native code — the milestone's constraints are met
  without them. The measured cost did not justify a C++ path.
- Regional work is cached and reused (cache stats are exposed via
  `GeographicSurface.get_cache_stats()`).
- On-device cost is **unknown**: the numbers above are Linux/llvmpipe. The
  overlay's `rebuild` timing and the streaming line are the on-device signals to
  watch (see §13).

Format sanity check from the capture runs: `fps 7.5 / frame 133 ms` under
software rendering is the renderer, not generation — M0.2 measured the same on
the same machine.

---

## 12. Testing results

Full run, `DISPLAY=:99 ./tests/run_tests.sh` (windowed so the UI suite executes):

| Suite | Checks | Result |
|---|---|---|
| core | 17 | PASS |
| generation (new) | 45 | PASS |
| voxel | 24 | PASS |
| reliability | 24 | PASS |
| perf | 41 | PASS |
| ui input | 45 | PASS |
| **total** | **196** | **ALL SUITES PASSED** |

Baseline before M1 was 151 checks (17/24/24/41/45). No check was removed or
weakened; `core_suite`'s height-field checks were retargeted to the new surface
with the same guarantees.

### What the new suite covers

**Determinism (11 checks)** — hash purity (1000 coordinates); seed / module-id /
generation-version / adjacent-coordinate stream independence (500 samples each,
threshold 99.5 %); module seeds stable across instances and distinct per module;
same seed identical across independent pipelines (576 columns and 36 field
samples); different seeds differ (99.8 %); generation-version bump differs (99.6 %);
negative coordinates deterministic and bounded (256 columns) and well defined
across the origin; ±1e9 coordinates deterministic and bounded (160 columns);
block grouping irrelevant (4096 heights: one 64² request vs sixteen 16² requests
walked in reverse vs per-column queries); cache on/off identical (2304 heights);
4-thread concurrent sampling identical to serial.

**Fields (12 checks)** — continentalness ∈ [−1, 1], elevation ∈ [−1, 1],
mountainness ∈ [0, 1], hills ∈ [0, 1]; ocean and land both present; heights
bounded for 5 seeds including 0 and negatives (1280 columns); mountains continuous
(0 % isolated at the default seed, threshold 5 %); plains/hills/mountains all
present with hills 1.44× rougher than plains (+4.9 voxels) and mountains 19 voxels
above hills; waterline mean slope 0.32 voxels/column; no column-to-column step
above 2.83 voxels anywhere; both below- and above-sea-level terrain present.

**Module system (9 checks)** — all six modules registered; every module runs after
its dependencies; duplicate id and duplicate output field rejected; unknown
dependency rejected; cycle rejected; a module evaluated standalone (no engine) is
bounded and repeatable; configuration snapshot survives edits to the live
resource; adding a module leaves 100 existing field samples bit-identical.

**Integration (2 checks)** — 64 columns across 4 generated blocks match
`floor(surface_height)`; composed relief across a streamed 128² region spans 71
voxels (a collapsed pipeline would show much less).

### Regression coverage retained from M0.2

Block content independent of generation order; no seams across horizontal or
vertical block boundaries (reconstructed from voxel data, not from the field);
concurrent sampling equals serial; Voxel Tools statistics and streaming; touch
camera; all four numeric fields; regenerate/random-seed/default-seed behaviour;
screenshot exit codes.

---

## 13. Android Editor testing instructions

The milestone forbids exporting APKs, so Android verification is done by the user
in the Godot Editor. What to check, in order:

1. **Open the project** in Godot 4.7.2 with the Voxel Tools GDExtension for
   Android present in `addons/zylann.voxel/bin/` (`libvoxel.android.*.so`). ADR-0006
   removed them to save space; restore from the extension zip before running on a
   device.
2. **Run on device.** Expect a coastal landscape with plains, hills, ocean and —
   within a few hundred voxels — a mountain massif. The panel's `terrain` line
   should say something like `plains @ 36.7`; `fields` shows continentalness and
   mountainness under the viewer.
3. **Drag to orbit, wheel/pinch to zoom, middle-drag to pan.** Unchanged from
   M0.2; the camera now starts on the nearest land rather than the origin column.
4. **Edit all four numeric fields by touch** (seed, terrain height, frequency,
   view distance) and press **Regenerate**. Terrain must visibly respond: height
   scales relief, frequency changes the fine roughness.
5. **Random seed**, then **restore 1337** and confirm the original world returns.
6. **Same-seed reproducibility:** regenerate 1337 twice; the two worlds must be
   identical.
7. **Watch `rebuild` in the overlay** — it now includes building the module
   pipeline. Report the number. On this machine M1 measured **8.8 – 26.7 ms**
   across the capture runs (six modules plus their noise objects), against
   ~0.7 ms for M0.2's single height field. That difference is the main thing to
   watch on a phone.
8. **Watch streaming**: the `streaming` line should reach `ready` without the
   app becoming unresponsive. If it is slow, note `fps`, `frame` and the
   dropped-loads counter before reporting.

Please report device model, Android version, the overlay lines (`fps`, `frame`,
`rebuild`, `dropped`) and whether any landform type was missing.

---

## 14. Known limitations

1. **Android and Windows not re-tested.** All evidence in this document is Linux
   x86_64 with software rendering. Nothing here claims device behaviour.
2. **Cross-platform bit-identical determinism is not verified.** Same-machine
   reproducibility is verified exactly; cross-platform is not claimed.
3. **No water simulation.** A translucent plane at sea level only. No rivers, no
   lakes, no shoreline interaction.
4. **Terracing on gentle slopes** (see §10) — inherent to integer column heights.
5. **Mountain belts are noise-driven, not tectonic.** No plate simulation: the
   belt mask gives provinces and continuity, but ranges do not follow real
   collision geometry. Revisit if a later milestone wants physical plausibility.
6. **Far-from-origin precision** degrades at |x| ≈ 1e9 (float32 noise lattice).
7. **`rebuild()` is heavier** — 8.8–26.7 ms here versus ~0.7 ms in M0.2 — because
   it now constructs six modules and their noise objects. Still a one-off on the
   main thread, but it is the number most likely to matter on a slow device.
8. **Coastal relief is a tuning compromise**: flattening coasts removes scarps but
   creates large low plains on some seeds.
9. **The sea plane is 2048 voxels across** and does not follow the viewer; the
   camera's 1000-unit far plane clips it at the horizon, so it never shows an edge
   in practice, but a world larger than 1 km would reveal one if the far plane
   were raised.
10. **One field per module.** A module needing two outputs (e.g. temperature and
    humidity) must currently be split in two. Deliberate for M1, documented for
    M2's climate work.

---

## 15. Recommendations for M2

In rough order of value per unit of risk:

1. **Climate as modules, not a rewrite** — add `temperature` and `humidity`
   modules depending on `continentalness`, `elevation` and (for humidity)
   distance-to-water. One line each in `_register_modules()`. The one-field-per-
   module limit above is the thing to resolve first (either split into
   `temperature`/`humidity` modules, or extend the contract to multiple outputs).
2. **Biome/material mapping** — the palette currently colours by depth only. A
   biome module + palette lookup would make the existing terrain visibly richer
   without touching the voxel layer's structure (`BlockPalette.classify()` is the
   seam).
3. **Hydrology, if needed** — the researched licence-free implementations cannot
   be copied; a flow-accumulation pass over the surface height grid is the cheap
   path, and the node grid is a natural place to compute it once and cache it.
4. **Sample points, not everywhere** — `GeographicSurface.get_field_at()` already
   exposes raw fields; a "drop a marker, read the geography" debug feature is
   cheap and would make tuning conversations concrete.
5. **Performance pass with real device numbers** before adding cost. The Android
   Editor run should decide whether `sampling_stride` stays at 8 and whether
   detail keeps 4 octaves.
6. **Do not** add native code or GPU compute yet: the measured cost does not
   justify the build complexity, which is what ADR-0001/0006 exist to protect.
