class_name PlateauModule
extends GenerationModule

## Where plateaus and tablelands are, as a mask the surface composer blends towards
## a level.
##
## Output: [code]0.0 .. 1.0[/code]. 0 is ordinary terrain, 1 is the interior of a
## plateau. Values in between are the transition band and are deliberately not a
## smooth ramp - see below.
##
## [b]How a plateau is made.[b] A low-frequency field at a wavelength of roughly
## 600 voxels, warped, is sharpened into a mask. The surface composer then blends
## the composed height towards a level that is constant across the masked region.
## Because relief is blended [i]away[/i], the interior is flat regardless of what
## the hill and mountain fields do there - a plateau is not a stack of noise with a
## lift added, it is terrain whose relief has been removed.
##
## [b]Why the edges are stepped.[b] Erosion on a plateau margin works in layers:
## hard strata hold, soft ones retreat, and the result is a staircase of shelves
## rather than a single smooth slope. [method terrace] quantises the transition
## band of the mask into [member WorldConfig.plateau_steps] shelves with smoothed
## risers, so the surface falls from plateau level to base level in visible steps
## while remaining continuous: at every shelf boundary the terrace function is
## exactly equal to the unquantised value, so no seam or cliff can appear, only a
## change in gradient.
##
## [b]Sizes.[b] Large plateaus come from the low-frequency core of the mask; smaller
## tablelands are the isolated islands of the same field above the threshold at its
## high-frequency edge. A second field scales the level of each region modestly, so
## one plateau in a world is not the same elevation as the next - the surface
## composer reads that through the elevation field it already blends in, and the
## warp and edge jitter here are what keep margins irregular.

const MODULE_ID := &"plateaus"
const OUTPUT_FIELD := &"plateaus"

## Mask shaping. Above HIGH is plateau interior, below LOW is ordinary terrain.
const MASK_LOW := 0.60
const MASK_HIGH := 0.78

## Edge raggedness, added to the mask before shaping so the margin is irregular at a
## much finer scale than the plateau itself.
const EDGE_JITTER := 0.20

## Plateaus are inland landforms. Blended in rather than gated hard so a plateau
## near a coast loses height gradually instead of ending in a wall.
const LAND_INNER := 0.06
const LAND_OUTER := 0.24

const WARP_AMPLITUDE := 170.0

var _mask: FastNoiseLite
var _edge: FastNoiseLite
var _warp: FastNoiseLite

var _steps := 3
var _landmass_index := -1


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray([&"landmass"]), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	var base := config.plateau_frequency
	_steps = maxi(config.plateau_steps, 1)
	_landmass_index = dependency_index(&"landmass")

	_mask = context.make_noise_stream(MODULE_ID, version, 1, base, 3)
	_edge = context.make_noise_stream(MODULE_ID, version, 2, base * 6.0, 2)
	_warp = context.make_noise_stream(MODULE_ID, version, 3, base * 1.7, 1)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var land := values[_landmass_index]
	var land_gate := smoothstep(LAND_INNER, LAND_OUTER, land)
	if land_gate <= 0.0:
		values[get_output_index()] = 0.0
		return

	var warp := _warp.get_noise_2d(x, z) * WARP_AMPLITUDE
	var raw := clampf(_mask.get_noise_2d(x + warp, z - warp) * 0.5 + 0.5, 0.0, 1.0)
	var jitter := (_edge.get_noise_2d(x, z)) * EDGE_JITTER

	var mask := smoothstep(MASK_LOW, MASK_HIGH, raw + jitter)
	values[get_output_index()] = terrace(mask, _steps) * land_gate


## Quantises [param value] into [param steps] shelves.
##
## Each shelf boundary keeps the original value exactly, so the function is
## continuous everywhere and only its gradient changes: the surface can step
## without the terrain ever jumping. Below the first shelf and above the last it is
## the identity, which is why a plateau interior stays perfectly level and the
## surrounding land keeps its own detail.
static func terrace(value: float, steps: int) -> float:
	if steps <= 1:
		return value
	var scaled := value * float(steps)
	var lower := floorf(scaled)
	var fraction := scaled - lower
	# A narrow riser in the middle of each step: mostly flat shelves, short steep
	# faces between them.
	var stepped := lower + smoothstep(0.34, 0.66, fraction)
	return clampf(stepped / float(steps), 0.0, 1.0)
