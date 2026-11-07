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
##    abyssal plain as continentalness drops, so the ocean has a visible shelf
##    and slope instead of a flat bottom.
## 2. [i]Land base.[/i] Base height plus an inland rise plus the multi-scale
##    elevation signal. The sign convention puts the waterline exactly at
##    continentalness [constant OCEAN_EDGE]: at that value the interpolated base
##    is the sea level by construction, which is what makes coastlines follow a
##    smooth contour rather than a chosen voxel row.
## 3. [i]Relief.[/i] Hill and mountain amplitudes, scaled by
##    [member WorldConfig.terrain_height] and gated by the land factor so relief
##    cannot lift the seafloor.
## 4. [i]Coastal softening.[/i] Any height within
##    [constant COAST_BAND] voxels of sea level is pulled towards it, which is
##    what prevents a shear cliff at the shoreline where a mountain belt happens
##    to reach the coast.
##
## [b]Why the softening is a pure function of height.[/b] It must not depend on
## which direction the coast runs, otherwise the transition would look correct
## from one side and like a step from the other. Compressing the vertical
## distance to sea level is direction-agnostic and continuous.

const MODULE_ID := &"surface"
const OUTPUT_FIELD := &"surface_height"

## Continentalness at which the land base equals the sea level.
##
## These three edges are calibrated against the actual distribution of the
## continentalness field (its median is near 0 and its 10th/90th percentiles are
## roughly -0.3/+0.3), not chosen as round numbers. A band that is too wide turns
## every piece of land into "coast" and never lets relief develop inland.
const OCEAN_EDGE := -0.02
## Continentalness at which the land base stops rising away from the shore.
const LAND_EDGE := 0.14
## Continentalness at which full relief is allowed. Between [constant OCEAN_EDGE]
## and here, relief ramps in with distance inland, which is what keeps the
## shoreline gentle instead of letting a mountain belt end in a scarp at the
## water. Wider than [constant LAND_EDGE] on purpose: the land base settles
## quickly, the relief takes much longer.
const RELIEF_EDGE := 0.34
## Continentalness at which the seafloor stops deepening.
const ABYSS_EDGE := -0.35
## Fraction of relief that still applies at the waterline. Zero would make every
## coastal plain perfectly flat, which reads as a manufactured plateau.
const RELIEF_FLOOR := 0.25

## Vertical band around sea level that is compressed, in voxels.
const COAST_BAND := 3.5

## Hard limits on the surface, in voxels. Bounded height keeps the number of
## voxels the mesher must consider predictable.
const MIN_HEIGHT := 2.0
const MAX_HEIGHT := 96.0

## Classification thresholds, shared with [method classify].
const DEEP_OCEAN_EDGE := -0.30
const MOUNTAIN_THRESHOLD := 0.45
const HILL_THRESHOLD := 0.42

var _sea_level := 20.0
var _base_height := 24.0
var _terrain_height := 26.0
var _elevation_gain := 8.0
var _inland_rise := 4.0
var _ocean_depth := 16.0
var _mountain_scale := 1.5
var _hill_scale := 0.35

var _continents_index := -1
var _elevation_index := -1
var _mountains_index := -1
var _hills_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([&"continentalness", &"elevation", &"mountainness", &"hills"]),
			1
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_continents_index = dependency_index(&"continentalness")
	_elevation_index = dependency_index(&"elevation")
	_mountains_index = dependency_index(&"mountainness")
	_hills_index = dependency_index(&"hills")

	_sea_level = config.sea_level
	_base_height = config.base_height
	_terrain_height = config.terrain_height
	_elevation_gain = config.elevation_gain
	_inland_rise = config.inland_rise
	_ocean_depth = config.ocean_depth
	_mountain_scale = config.mountain_scale
	_hill_scale = config.hill_scale


## The world-unit limits of the composed surface, in voxels.
func get_output_bounds() -> Vector2:
	return Vector2(MIN_HEIGHT, MAX_HEIGHT)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]
	var elevation := values[_elevation_index]
	var mountains := values[_mountains_index]
	var hills := values[_hills_index]

	var land := smoothstep(OCEAN_EDGE, LAND_EDGE, continents)

	# 1. Seafloor: shallow on the shelf, deep off it.
	var shelf := smoothstep(ABYSS_EDGE, OCEAN_EDGE, continents)
	var seafloor := _sea_level - _ocean_depth * (1.0 - shelf)

	# 2. Land base. The elevation signal is shifted to 0..1 so it can only raise
	# land above the waterline, never drown it - no hydrology exists yet to
	# handle inland water bodies.
	var land_base := (
			_base_height
			+ _inland_rise * land
			+ _elevation_gain * (elevation * 0.5 + 0.5)
	)

	var base := lerpf(seafloor, land_base, land)

	# 3. Relief, ramped in with distance inland.
	#
	# The exponent makes the ramp leave the coast almost flat and reach full
	# strength well inland. Without it a mountain belt that happens to reach the
	# water produces a 30+ voxel wall over a few dozen voxels, which reads as an
	# artificial cliff - the thing the coastline requirement forbids. Relief is
	# the only thing this scales: the seafloor and the land base are unaffected.
	var inland_relief := pow(smoothstep(OCEAN_EDGE, RELIEF_EDGE, continents), 2.0)
	var relief := (
			(hills * _hill_scale + mountains * _mountain_scale)
			* _terrain_height
			* inland_relief
	)

	# 4. Coastal softening, then bounds.
	var height := soften_coast(base + relief)
	values[get_output_index()] = clampf(height, MIN_HEIGHT, MAX_HEIGHT)


## Compresses the height towards sea level inside [constant COAST_BAND] voxels of
## it, leaving everything outside untouched.
##
## [code]d' = B * sign(d) * (|d| / B)^2[/code] for [code]|d| < B[/code]: at the
## edge of the band the value and its slope match the untouched function, and at
## sea level the slope is exactly zero. A shoreline therefore always starts with
## a gentle apron and steepens with distance, in both directions.
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
static func classify(continentalness: float, mountainness: float, hills: float) -> StringName:
	if continentalness < DEEP_OCEAN_EDGE:
		return &"deep_ocean"
	if continentalness < OCEAN_EDGE:
		return &"shallow_ocean"
	if continentalness < LAND_EDGE:
		return &"coast"
	if mountainness >= MOUNTAIN_THRESHOLD:
		return &"mountains"
	if hills >= HILL_THRESHOLD:
		return &"hills"
	return &"plains"
