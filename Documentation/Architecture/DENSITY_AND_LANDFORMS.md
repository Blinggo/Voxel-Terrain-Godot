# Shared density and blended landforms — M5

## Pipeline and ownership

`WorldConfig snapshot → existing geographic fields → blended landform parameters / SurfaceModule composition → engine surface detail → M4 hydrology carving → TerrainDensity → TYPE or SDF adapter → native mesher`

`VoxelWorld` owns one `GeographicSurface` and one `TerrainDensity` per rebuild and explicitly passes the density object to its active adapter. No autoload, scene lookup or Voxel Tools class is used by the density/profile implementation. The field, profiles, noise instances and deep-copied configuration are read-only after construction. Mutex-protected caches contain reconstructible coordinate-derived values only.

Both scenes inherit the same configuration and geography. The blocky scene remains the project default. There is no smooth-only noise/geography branch.

## Two modes

- `density_mode=0`: original M2/M4 composition and exactly `D(x,y,z)=y-H(x,z)`.
- `density_mode=1`: blended landform composition before carving, then bounded 3D modifications of the same carved base.

`WorldConfig.new()` retains mode 0 for legacy callers. The shipped `main.tscn` configuration selects mode 1; the inherited smooth scene uses it too. The Terrain button switches modes while restoring the camera target. The M4 lake button explicitly restores legacy mode, seed 1337, height 26 and hydrology enabled, because a different base surface legitimately changes drainage and the old lake landmark.

A configuration/mode change is a different generated world even when `world_seed` is unchanged. `generation_version=2` is retained for the existing macro streams; density uses its own versioned `density` substreams 1–3. Save/reproduction identifiers must include the full configuration, not just seed/version.

## Sign and sampling

Negative or zero density is solid, positive density is air. This matches Voxel Tools v1.7, not the opposite sign in the inspected Primitive Voxels implementation. The field is a shaped/approximate SDF, **not an exact Euclidean distance**.

`sample_density(Vector3)` bilinearly interpolates integer-column heights and controls. `sample_block(origin,size)` returns float32 data with index `(z*size.x+x)*size.y+y`. Integer point/block values agree within float32 tolerance. Absolute coordinates, floor division at negative positions, shared noise streams and interpolated controls avoid chunk-local phases.

A continuous field does not guarantee that low-resolution meshing preserves every sub-voxel feature, or that disconnected solids cannot occur. There is no connectivity cleanup pass or full cave topology system.

## Profiles

`LandformProfile` resources configure broad elevation, relief, slope sharpness, ridge/valley influence, transition width and geological/structural/fine influences. Optional resources in `WorldConfig.landform_profiles` replace matching default IDs and are deep-copied. `LandformProfiles` contains one evaluator for all types—not ten generators.

| ID | Elevation offset | Relief | Ridge | Valley | Geological | Structure | Fine |
|---|---:|---:|---:|---:|---:|---:|---:|
| plains | -1 | .30 | 0 | 0 | .1 | 0 | .15 |
| rolling_hills | 1 | .75 | 0 | 0 | .2 | .1 | .3 |
| highlands | 8 | 1.05 | 0 | 0 | .4 | .3 | .4 |
| foothills | 3 | 1.10 | 1 | 0 | .3 | .4 | .4 |
| mountain_ranges | 8 | 1.65 | 6 | 1 | .6 | 1 | .7 |
| alpine_mountains | 15 | 2.20 | 12 | 2 | 1 | 1.4 | 1 |
| plateaus | 3 | 1 | 0 | 0 | .1 | .05 | .2 |
| mountain_basins | -5 | .45 | 0 | 4 | .1 | .03 | .15 |
| coastal_lowlands | 0 | .5 | 0 | 0 | 0 | 0 | 0 |
| steep_rocky | 5 | 1.5 | 5 | 1 | .5 | 1.5 | .9 |

Default transition width and slope sharpness are 1. Weights derive from landmass, mountainness, hills, plateaus, valleys and elevation; nonnegative weights are normalized to sum to one. Wider transition widths soften dominance. No nearest-profile switch is used in generation. Highlands and steep-rocky profiles may be contributions rather than the dominant profile at a sampled location.

Existing tectonic/ridged fields supply range organization and plateaus/valleys keep their existing geography. M5 changes their blended expression, not the underlying plate network. Plateau interiors retain the original flattened height plus profile uplift. Coastal modifications fade in on established land. Profile slope sharpness reshapes relief relative to the base; a separate macro-slope gate limits structural density effects.

## Scale hierarchy

- Macro geology/landforms: existing plate size/boundary width, continent/elevation/mountain/hill/valley/plateau frequencies and amplitudes remain independently configurable.
- Geological 3D band: amplitude 2, frequency .008.
- Structural 3D band: amplitude 14, frequency .055; y coordinates scaled by 1.8 to favour undercut/layer structure.
- Fine 3D band: amplitude .8, frequency .18.

All three new bands use built-in FastNoiseLite, one octave, deterministic independent seeds. Profile influences multiply their amplitudes. Zero amplitude skips its noise call. Global frequencies do not vary with profile weight, avoiding phase discontinuities. Optional structural domain warp is disabled by default; no additional warp layer is needed for the default terrain.

Let `d=y-H`. Geological and fine terms are bounded signed noise. The structural term is a nonnegative, smooth-thresholded 3D noise multiplied by a recess window that fades in from depths 1–4 and fades out from 12–24. It carves rather than adds separate masses above the surface. All modifiers fade to zero at the outer band boundary `max(24,2*sum(effective_amplitudes))`. The 32-unit control grid interpolates profile influences and a slope gate estimated from the pre-carve surface at ±16 units.

This permits multiple solid intervals in a vertical column: genuine volumetric undercuts rather than another height-displacement function. It is not unrestricted signed blobby noise and not a cave network. Local enclosed cavities or detached caps remain possible; topology is not globally solved.

## Hydrology integration and migration

Hydrology sees the profile-shaped base, so mode 1 may reroute sources, reaches and lakes relative to mode 0. Deterministic routing algorithms, query format, separate water levels/geometry, width and waterfall metadata remain in the existing M4 module.

Density protects river corridors with a smooth width-dependent mask and protects a conservative 128-unit lake envelope, fading to 160 units. Ocean/coast modifiers fade between sea level +4 and +14. Integer masks are interpolated for fractional queries. Tile query support was extended from 48 to 64 units to cover the expanded river protection support; lake support includes the lake radius. This is deliberately conservative and can suppress otherwise interesting nearby rock detail.

`get_surface_height()` continues to mean the **carved base H**, not the top of every final volumetric solid. Collision/raycast/gameplay systems must use density or final terrain geometry when they need the true solid boundary. Water queries retain their ground-height/base semantics.

M4's missing routed lake outlets/chains, dedicated terraces, fine shoreline guarantee, cold-latency, Android and long-streaming validation remain open. The blue diagnostic water mesh is not a fluid solver and is not polished to hide those limitations.

## Adapters and materials

The blocky adapter writes TYPE only. `TerrainDensity.material_block` owns solid/air and grass/dirt/stone decisions; upper-Y halo sampling classifies exposed top faces across blocks. Run-length writes reduce native API calls. Legacy mode retains an exact source-generated span fast path.

The smooth adapter writes SDF only, saturated at ±32 into a 32-bit channel. Saturation does not alter the zero surface and supplies enough nearby samples for native gradients. Transvoxel transitions remain disabled. Smooth terrain still uses its existing single visual material; it does **not** render the blocky's grass/dirt/stone material palette. Both adapters nevertheless use the same solid field. Smooth material blending is deferred, not claimed complete.

Conservative density intervals allow uniform air/stone TYPE fills and exactly saturated uniform SDF fills without per-voxel noise. The interval accounts for normalized profile maxima; the structural term only increases density. These are encoding optimizations, not alternate geography.

## Cost and caches

Existing geography/hydrology caches remain bounded. A measured repeated-control hotspot justified a 256-entry cache of standard 16×16 PackedVector3Array controls: at most 768 KiB payload, plus dictionary/object overhead. Arbitrary rectangles are not retained. Cache eviction affects cost, not output. The final-carved-column cache is still 512 entries / approximately 512 KiB payload. No whole-world preprocessing or dependency on previously generated neighbouring chunks is introduced.

See the milestone report and evidence logs for measured costs. Cold drainage construction remains expensive. Software-rendered Linux frame timings are not Android FPS predictions, and Godot static-memory counters are not total RSS/GPU memory.
