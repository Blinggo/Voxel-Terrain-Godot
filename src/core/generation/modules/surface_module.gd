class_name SurfaceModule
extends GenerationModule

## Composes the geographic fields into a surface height in voxels.
##
## This is the only module that knows about world units. Everything upstream is a
## dimensionless signal, which is what lets the fields be tested on their own and
## recombined later without touching the modules that produce them.
##
## Output: surface height in voxels, before the detail term the engine adds per
## column. Rounded down, it is the y of the topmost solid voxel of the column.
##
## [b]Composition, in order.[/b]
## 1. [i]Depth model.[/i] Seafloor height falls off from the shelf towards the
##    abyssal plain as the land signal drops, so the ocean has a visible shelf and
##    slope instead of a flat bottom. The shelf depth is modulated by the elevation
##    signal, so the offshore transition is not the same ramp everywhere.
## 2. [i]Land base.[/i] Base height plus an inland rise plus the multi-scale
##    elevation signal. The sign convention puts the waterline exactly at
##    [member LandmassModule]'s field value [constant OCEAN_EDGE]: at that value the
##    interpolated base is the sea level by construction, which is what makes
##    coastlines follow a smooth contour rather than a chosen voxel row.
## 3. [i]Relief.[/i] Hill and mountain amplitudes, scaled by
##    [member WorldConfig.terrain_height] and gated by the land factor so relief
##    cannot lift the seafloor.
## 4. [i]Plateaus.[/i] Where [member PlateauModule] says a plateau is, the composed
##    height is blended towards a level. Blending [i]towards a level[/i] rather than
##    adding a lift is what makes a plateau interior flat: the relief from step 3 is
##    removed rather than displaced. The level carries a fraction of the elevation
##    signal, so plateau interiors roll gently across hundreds of voxels while
##    staying flat locally.
## 5. [i]Valleys and basins.[/i] The carve field removes material last, so a valley
##    cuts through hills, a mountain range and a plateau alike instead of being
##    buried under them. Carving is scaled up inside mountains, which is what makes
##    a valley crossing a range read as a pass. Carved land is held just above sea
##    level: without hydrology there is nothing to drain an inland depression, and a
##    basin floor that was below the sea plane would fill with water it cannot have.
## 6. [i]Coastal softening.[/i] Any height within [constant COAST_BAND] voxels of
##    sea level is pulled towards it, which is what prevents a shear cliff at the
##    shoreline where a mountain belt happens to reach the coast.
##
## [b]Why the softening is a pure function of height.[/b] It must not depend on
## which direction the coast runs, otherwise the transition would look correct from
## one side and like a step from the other. Compressing the vertical distance to sea
## level is direction-agnostic and continuous.

const MODULE_ID := &"surface"
const OUTPUT_FIELD := &"surface_height"

## Land signal value at which the land base equals the sea level.
##
## These edges are calibrated against the actual distribution of the land signal
## (its median is near 0 and its 10th/90th percentiles are roughly -0.3/+0.3), not
## chosen as round numbers. A band that is too wide turns every piece of land into
## "coast" and never lets relief develop inland.
const OCEAN_EDGE := -0.02
## Land signal value at which the land base stops rising away from the shore.
const LAND_EDGE := 0.14
## Land signal value at which full relief is allowed. Between [constant OCEAN_EDGE]
## and here, relief ramps in with distance inland, which is what keeps the shoreline
## gentle instead of letting a mountain belt end in a scarp at the water. Wider than
## [constant LAND_EDGE] on purpose: the land base settles quickly, the relief takes
## much longer.
const RELIEF_EDGE := 0.34
## Land signal value at which the seafloor stops deepening.
const ABYSS_EDGE := -0.35
## Fraction of relief that still applies at the waterline. Zero would make every
## coastal plain perfectly flat, which reads as a manufactured plateau.
const RELIEF_FLOOR := 0.25

## Vertical band around sea level that is compressed, in voxels.
const COAST_BAND := 3.5

## Carved land is held this far above sea level, so no basin is silently flooded by
## the sea plane.
const DRAINAGE_FLOOR := 1.0

## How much of a plateau mask is cancelled where a mountain range is. A plateau
## that overlapped a range would flatten the range; fading the mask out under
## mountains keeps the two landforms distinct instead of letting whichever module
## runs second win.
const PLATEAU_MOUNTAIN_FADE := 0.85

## How much valley carving is suppressed on a plateau top. A plateau interior is
## meant to be a level surface with rolling relief; letting the valley network cut
## it at full depth turns every plateau into a set of mesas separated by canyons,
## which is a different landform. Carving still reaches the margin, where the mask
## is partial, so plateau edges stay dissected.
const PLATEAU_VALLEY_FADE := 0.90

## How far below the regional base a valley may cut, in voxels. Without a limit a
## deep valley in a high range removes the range instead of cutting through it: the
## carve is applied last, so it can take away everything the relief added. The base
## land surface is the level a valley bottoms out towards, which is also what makes
## valley floors line up across a region instead of following the mountains.
const VALLEY_FLOOR_MARGIN := 3.0

## No fixed altitude bounds: streaming, not geographical clipping, bounds work.

## Classification thresholds, shared with [method classify].
const DEEP_OCEAN_EDGE := -0.30
const MOUNTAIN_THRESHOLD := 0.45
const HILL_THRESHOLD := 0.42
const PLATEAU_THRESHOLD := 0.60
const VALLEY_THRESHOLD := 0.45

var _profiles: LandformProfiles
var _hybrid := false

var _sea_level := 20.0
var _base_height := 24.0
var _terrain_height := 26.0
var _elevation_gain := 8.0
var _inland_rise := 4.0
var _ocean_depth := 16.0
var _mountain_scale := 1.5
var _hill_scale := 0.35
var _plateau_uplift := 26.0
var _valley_depth := 0.34

var _landmass_index := -1
var _elevation_index := -1
var _mountains_index := -1
var _hills_index := -1
var _plateaus_index := -1
var _valleys_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([
					&"landmass",
					&"elevation",
					&"mountainness",
					&"hills",
					&"plateaus",
					&"valleys",
			]),
			2
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_hybrid = config.density_mode == 1
	_profiles = LandformProfiles.new(config.landform_profiles)
	_landmass_index = dependency_index(&"landmass")
	_elevation_index = dependency_index(&"elevation")
	_mountains_index = dependency_index(&"mountainness")
	_hills_index = dependency_index(&"hills")
	_plateaus_index = dependency_index(&"plateaus")
	_valleys_index = dependency_index(&"valleys")

	_sea_level = config.sea_level
	_base_height = config.base_height
	_terrain_height = config.terrain_height
	_elevation_gain = config.elevation_gain
	_inland_rise = config.inland_rise
	_ocean_depth = config.ocean_depth
	_mountain_scale = config.mountain_scale
	_hill_scale = config.hill_scale
	_plateau_uplift = config.plateau_uplift
	_valley_depth = config.valley_depth


## The world-unit limits of the composed surface, in voxels.
func get_output_bounds() -> Vector2:
	return Vector2.ZERO # GenerationEngine sentinel: no output clamp.


func evaluate_node(_x: int, _z: int, values: PackedFloat32Array) -> void:
	var land_signal := values[_landmass_index]
	var elevation := values[_elevation_index]
	var mountains := values[_mountains_index]
	var hills := values[_hills_index]
	var plateaus := values[_plateaus_index]
	var valleys := values[_valleys_index]

	var elevation01 := elevation * 0.5 + 0.5
	var land := smoothstep(OCEAN_EDGE, LAND_EDGE, land_signal)

	# 1. Seafloor: shallow on the shelf, deep off it, with the shelf depth varying
	# with the elevation signal so the offshore transition is irregular.
	var shelf := smoothstep(ABYSS_EDGE, OCEAN_EDGE, land_signal)
	var depth := _ocean_depth * (0.85 + 0.30 * elevation01)
	var seafloor := _sea_level - depth * (1.0 - shelf)

	# 2. Land base.
	var land_base := _base_height + _inland_rise * land + _elevation_gain * elevation01
	var base := lerpf(seafloor, land_base, land)

	# 3. Relief, ramped in with distance inland.
	#
	# The exponent makes the ramp leave the coast almost flat and reach full
	# strength well inland. Without it a mountain belt that happens to reach the
	# water produces a 30+ voxel wall over a few dozen voxels, which reads as an
	# artificial cliff - the thing the coastline requirement forbids. Relief is the
	# only thing this scales: the seafloor and the land base are unaffected.
	var inland_relief := pow(smoothstep(OCEAN_EDGE, RELIEF_EDGE, land_signal), 2.0)
	var relief := (
			(hills * _hill_scale + mountains * _mountain_scale)
			* _terrain_height
			* inland_relief
	)
	var height := base + relief

	# 4. Plateaus: blend towards a level, removing relief rather than lifting it.
	#    The mask is faded out under mountains so a range is not levelled.
	var plateau_mask := clampf(plateaus, 0.0, 1.0) * (1.0 - PLATEAU_MOUNTAIN_FADE * mountains)
	# The level follows the base land surface, which already rolls gently with the
	# elevation field, rather than adding another copy of that roll on top: doubling
	# it was enough to make plateau interiors as rough as the land around them.
	var plateau_level := base + _plateau_uplift
	height = lerpf(height, plateau_level, plateau_mask)

	# 5. Valleys and basins carve last, so they cut through everything above, but
	#    only down to the regional base level, and only faintly across a plateau top.
	var carve := (
			valleys
			* _valley_depth
			* _terrain_height
			* (1.0 + mountains)
			* (1.0 - PLATEAU_VALLEY_FADE * plateau_mask)
	)
	var valley_floor := base - VALLEY_FLOOR_MARGIN
	height = maxf(height - carve, minf(height, valley_floor))
	height = lerpf(height, maxf(height, _sea_level + DRAINAGE_FLOOR), land)

	if _hybrid:
		height = _profiles.shape(height,base,land_signal,mountains,hills,plateaus,valleys,elevation)
		height = lerpf(height,maxf(height,_sea_level+DRAINAGE_FLOOR),land)

	# 6. Coastal softening.
	values[get_output_index()] = soften_coast(height)


## Compresses the height towards sea level inside [constant COAST_BAND] voxels of
## it, leaving everything outside untouched.
##
## [code]d' = B * sign(d) * (|d| / B)^2[/code] for [code]|d| < B[/code]: at the
## edge of the band the value and its slope match the untouched function, and at
## sea level the slope is exactly zero. A shoreline therefore always starts with a
## gentle apron and steepens with distance, in both directions.
func soften_coast(height: float) -> float:
	var delta := height - _sea_level
	if absf(delta) >= COAST_BAND:
		return height
	var normalized := delta / COAST_BAND
	return _sea_level + COAST_BAND * normalized * absf(normalized)


## Human-readable terrain type at a sampled node.
##
## Kept next to the thresholds it depends on so the debug overlay and the tests
## cannot drift from the algorithm. Purely descriptive: nothing in the pipeline
## branches on it.
static func classify(
		land_signal: float,
		mountainness: float,
		hills: float,
		plateaus: float = 0.0,
		valleys: float = 0.0
) -> StringName:
	if land_signal < DEEP_OCEAN_EDGE:
		return &"deep_ocean"
	if land_signal < OCEAN_EDGE:
		return &"shallow_ocean"
	if land_signal < LAND_EDGE:
		return &"coast"
	if mountainness >= MOUNTAIN_THRESHOLD:
		return &"mountains"
	if plateaus >= PLATEAU_THRESHOLD:
		return &"plateau"
	if valleys >= VALLEY_THRESHOLD:
		return &"valley"
	if hills >= HILL_THRESHOLD:
		return &"hills"
	return &"plains"
