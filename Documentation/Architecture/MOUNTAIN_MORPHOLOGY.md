# M5.1 mountain morphology and configuration

## Position in the existing pipeline

`tectonics/landmass → MountainModule (optional MountainMorphology) → SurfaceModule / LandformProfiles → surface detail → DrainageNetwork carving → TerrainDensity → existing TYPE/SDF adapters`

There is no new generator registry branch and no second smooth geography. MountainModule remains the registered `mountainness` module and retains the existing tectonic uplift/rift/province fields. TerrainDensity, its noise substreams, bounded caches, material classification and both voxel adapters are unchanged by M5.1.

`mountain_morphology_enabled=false` reproduces the M5 mountain path. `true` activates refinement **only when density_mode=1**. Legacy density mode remains the M2/M4 height representation. WorldConfig.new() defaults the refinement flag off for old callers; the shipped main scene enables it, and smooth inherits that scene. Reproduction identity includes the full configuration and profile resources, not only the seed.

## Why the old summits were pointed

See Research/M51_MOUNTAIN_DIAGNOSIS.md, written before implementation and extended with measured transect findings before changing composition. Narrow multi-octave ridges and eight-voxel interpolation were amplified by M5's mountain-dependent post-carve profile gains. Plateau masks and amplified valley removal could isolate a high node even when the underlying mountain signal was broad. Width-only tuning did not resolve that second mechanism.

The refined path establishes calibrated mountain mass **before** valley/plateau shaping and does not apply the old peak-dependent gain again. A 2.35 relief calibration replaces M5's former 1.65–2.2 relief gain plus elevation/ridge bonuses; it is not a new world-height ceiling. Low/nonmountain terrain retains the ten-landform composition. Smooth mountainness gates blend between the paths; established mountain cores are not flattened by an unrelated plateau mask. The final shared hydrological carving still follows this composition.

## Shared evaluator

`MountainMorphology` snapshots an array of `LandformProfile` resources and precompiles their vertical curves. Its evaluator receives:

- absolute primary-noise value as an implicit distance from a wandering zero-contour crest;
- the existing secondary ridge signal for cols, flank ridges and gullies;
- secondary detail and the low-frequency province selector, without additional noise calls.

Three smooth cross-sections establish summit, shoulder and foothill mass. A nonzero crest floor retains connecting cols; smoothly added secondary ridges break up the skyline without a hard max between independent mountains. Gully modulation is analytical shaping, not hydraulic or thermal erosion. The existing tectonic/province envelope and rift suppression locate the system geographically.

The primary field changes from three-octave ridged noise to one octave of smooth Simplex. Existing warp amplitude/frequency are reduced from 120 / 1.3×base to 60 / .55×base. Existing secondary frequency changes from 3.2×base to 1.4×base. There are still six FastNoiseLite API calls per node, fewer primary octaves, and no added per-voxel 3D noise.

The profile selector reuses the existing low-frequency variation field. All configured profiles receive positive reciprocal-quartic weights around their `morphology_position`, normalized to sum to one. There is no nearest-style switch. The same resources can also be used one at a time for controlled showcases.

## Resource controls

All six styles use **LandformProfile**, not six generator classes. The original ten-landform fields remain in that resource for backward compatibility. The following Mountain morphology group is consumed by the new evaluator:

| Property | Meaning / measurable effect |
|---|---|
| `overall_elevation` | Relative mountain relief scale; not absolute sea-level elevation |
| `mountain_width` | Scales the entire crest-relative cross-section |
| `summit_width` | Width of the upper cap independently from the skirt |
| `summit_sharpness` | Higher values sharpen the upper cap; exponent stays above 1, retaining a continuous apex derivative |
| `ridge_width` | Width/occupancy of secondary ridge and col modulation |
| `mountain_ridge_influence` | Contrast of connected peaks/cols and flank ridges |
| `shoulder_width` | Independent middle-slope mass |
| `foothill_width` | Extent of the low outer skirt |
| `mountain_valley_influence` | Depth of analytical gullies between secondary ridges |
| `surface_roughness` | Profile-specific secondary 2D perturbation; not a replacement for global fine-detail/density controls |
| `geological_detail` | Broad province-dependent modulation, separate from secondary roughness |
| `transition_width` | Breadth of this resource's blend in style-selector space |
| `morphology_position` | Resource's centre in the continuous regional style-selector coordinate |

Widths are dimensionless noise-coordinate widths, **not literal metres/voxels**. Physical widths also depend on mountain_frequency, warp and the local gradient of the primary field. Increasing them expands the corresponding cross-section rather than lowering its ideal peak. Other existing WorldConfig relief/frequency controls and M5 density-band controls remain available.

## Default resources

`resources/mountains/{alpine,massif,rounded,rugged,eroded,highland}.tres`

Alpine retains intentionally sharper crests. Massif widens both the summit and large skirt; rounded reduces cap sharpness; rugged strengthens ridge contrast; eroded strengthens analytical gullies; highland favours broad, lower-relief forms. "Eroded" is an appearance label, not an erosion simulation. Different resources also carry different vertical key positions.

`WorldConfig.mountain_profiles` empty means the six defaults. A nonempty list supplies the complete catalogue, including custom IDs; null entries are ignored and an all-null list falls back to defaults. It is separate from `landform_profiles`, the original ten-landform override list.

### Add a seventh style without unrelated code changes

1. Duplicate a mountain `.tres` (or create a Resource using `landform_profile.gd`). Give it a descriptive ID.
2. Set the morphology controls, `morphology_position`, `transition_width` and vertical key pairs.
3. In the World node's configuration, populate `mountain_profiles` with the six existing resources plus the new resource. Alternatively supply only the new resource to inspect it in isolation.
4. Enable Hybrid and mountain morphology, regenerate, and compare the same seed/camera. Resource changes are picked up on rebuild because the running world uses snapshots.
5. Run the M5.1 tests and add a fixed comparison pose for the new style if needed.

No change to GenerationRegistry, SurfaceModule, MountainModule, TerrainDensity or either adapter is necessary. A test constructs a previously unknown resource ID and verifies real geometric output.

## Vertical landform shaping

`terrain_y_positions` describes normalized elevation from base (0) to summit (1). `terrain_y_thresholds` describes the signal required to reach each elevation. Both arrays must have equal length 2–16, start at 0, end at 1, and be strictly increasing. Invalid keys warn and fall back to the identity curve rather than producing discontinuities.

The evaluator inverts threshold(height) into height(signal) and uses monotone cubic Hermite interpolation. Interior tangents are harmonic means of adjacent positive secants; each tangent is at most twice either neighbouring secant. Thus the interpolant stays monotone without overshoot and has matching derivatives at its keys. Unlike independent smoothstep segments, it does not force the derivative to zero at every key, which would introduce shelves. Ordinary mountain resources cannot request flat threshold intervals; explicit plateau/terrace behaviour remains with the existing plateau system.

Keys distinguish lower, middle, upper and summit regions independently from width/sharpness. The key convention is an independent adaptation of configurable vertical landform ideas, not an assertion that Vintage Story uses this exact inverse or sign convention.

## Hydrology and constraints

Broader mountain mass changes the base surface, so rivers, sources, lake occupancy and waterfall candidates can reroute. The algorithms, query contracts, width/level data and density water-protection masks are unchanged. Some former summit basins are filled by the new mass; this is a world-generation change, not silent deletion of the hydrology subsystem. Tests and surveys verify rivers/tributaries, descending levels, widths, waterfalls and multiple lakes in refined terrain.

No new cache, mutable RNG, neighbour-generated dependency, full-world preprocessing or runtime dependency was added. Resources/compiled curves are immutable snapshots. Existing field/density caches remain bounded and mutex-protected. Sampling remains C0 across grid/chunk boundaries; C1 vertical keys do not turn the eight-voxel bilinear geographical grid into a globally C1 surface.

M4 lake outlets/chains, dedicated river terraces and fine-shoreline guarantees remain unresolved. M5 local detached solids/cavities, single smooth material, coarse macro facets and finite streaming edges also remain. Broader summits do not by themselves solve distant LOD or Android cold-generation latency.
