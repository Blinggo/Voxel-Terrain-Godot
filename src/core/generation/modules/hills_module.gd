class_name HillsModule
extends GenerationModule

## Rolling hills: the relief between flat plains and mountain ranges.
##
## Output: [code]0.0 .. 1.0[/code]. Low values are plains, higher values are
## hills.
##
## [b]Distinguishable from plains by construction.[/b] The noise is shaped by a
## smoothstep over its middle range, so the distribution is deliberately
## bimodal-ish: a large share of the field lands near 0 (plains) and the rest
## rises into hills, instead of everything sitting at a mediocre 0.5. The surface
## module then scales real relief by this value, which is what makes plains
## actually flat rather than just slightly-less-hilly hills.
##
## [b]Interaction with mountains.[/b] Hill relief is damped where mountainness is
## high, so a range is not decorated with unrelated bumps at its foot; the
## transition from hills to mountains stays continuous because both terms are
## smooth functions of the same underlying fields.
##
## [b]Range.[/b] The module reads continentalness (to stay on land) and
## mountainness (to defer to ranges), both declared as dependencies so the
## registry orders it after them.

const MODULE_ID := &"hills"
const OUTPUT_FIELD := &"hills"

const HILL_LOW := 0.28
const HILL_HIGH := 0.84
## Curve applied after the smoothstep. Above 1 it pushes the low half of the
## distribution towards zero, which is what makes plains genuinely flat rather
## than merely less hilly, while leaving the high end available for hills.
const HILL_CURVE := 1.9

## How much hill relief is removed where mountains dominate.
const MOUNTAIN_DAMPING := 0.55

var _hills: FastNoiseLite
var _continents_index := -1
var _mountains_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([&"continentalness", &"mountainness"]),
			1
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_continents_index = dependency_index(&"continentalness")
	_mountains_index = dependency_index(&"mountainness")
	_hills = context.make_noise_stream(
			MODULE_ID, version, 1, config.hill_frequency, 3
	)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]
	var mountains := values[_mountains_index]

	var raw := clampf(_hills.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var shaped := pow(smoothstep(HILL_LOW, HILL_HIGH, raw), HILL_CURVE)

	var on_land := smoothstep(-0.05, 0.07, continents)
	var defer_to_ranges := 1.0 - MOUNTAIN_DAMPING * mountains

	values[get_output_index()] = shaped * on_land * defer_to_ranges
