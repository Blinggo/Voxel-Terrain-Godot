class_name CoastModule
extends GenerationModule

## Shoreline irregularity: bays, peninsulas and ragged offshore transitions.
##
## Output: [code]-1.0 .. 1.0[/code], signed, and multiplied by a shore mask so it
## is exactly zero away from the waterline.
##
## [b]Why a mask, and why this field is signed.[/b] A coastline is where the
## continental field crosses its land threshold. Rather than moving the threshold
## itself - which would change continental layout, and with it every downstream
## field - this module perturbs the continental field [i]only near that crossing[/i].
## Signed detail therefore pushes land out into the sea in some places (peninsulas)
## and pulls it back in others (bays), while the interior of a continent and the
## middle of an ocean are untouched. The mask is a function of distance from the
## threshold in field units, so it is wide exactly where the transition is.
##
## [b]Two scales.[/b] Fine detail alone gives a crinkled edge but no structure at
## the scale of a bay. A second, much lower frequency term supplies the bays and
## peninsulas themselves, with a wider mask so it can reach a little inland and
## offshore. Summing them keeps the fine crinkle on top of the large shapes.

const MODULE_ID := &"coast_detail"
const OUTPUT_FIELD := &"coast_detail"

## Shore mask width in field units. The continental field's own percentile spread
## is roughly -0.3..+0.3, so a mask this wide covers the coastline band only.
const SHORE_WIDTH := 0.22
## Bays and peninsulas need a wider mask than fine detail, otherwise they stop
## exactly at the waterline and read as a wiggle rather than a bay.
const SHAPE_WIDTH := 0.38

const DETAIL_WEIGHT := 0.62
const SHAPE_WEIGHT := 0.38

var _detail: FastNoiseLite
var _shape: FastNoiseLite
var _warp: FastNoiseLite

var _continents_index := -1


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray([&"continentalness"]), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	var base := config.coast_frequency
	_continents_index = dependency_index(&"continentalness")
	_detail = context.make_noise_stream(MODULE_ID, version, 1, base, 2)
	_shape = context.make_noise_stream(MODULE_ID, version, 2, base * 0.36, 2)
	_warp = context.make_noise_stream(MODULE_ID, version, 3, base * 0.7, 1)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]
	var distance := absf(continents)

	var shape_mask := 1.0 - smoothstep(0.0, SHAPE_WIDTH, distance)
	if shape_mask <= 0.0:
		values[get_output_index()] = 0.0
		return
	var detail_mask := 1.0 - smoothstep(0.0, SHORE_WIDTH, distance)

	# Warping the fine term keeps the crinkle from lining up along noise axes,
	# which is the usual tell of an unwarped coastline.
	var warp := _warp.get_noise_2d(x, z) * 90.0
	var detail := _detail.get_noise_2d(x + warp, z - warp)
	var shape := _shape.get_noise_2d(x, z)

	values[get_output_index()] = (
			(detail * DETAIL_WEIGHT * detail_mask + shape * SHAPE_WEIGHT * shape_mask)
			* shape_mask
	)
