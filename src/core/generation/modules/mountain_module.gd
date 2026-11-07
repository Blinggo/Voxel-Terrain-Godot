class_name MountainModule
extends GenerationModule

## Where mountains are, and how high.
##
## Output: [code]0.0 .. 1.0[/code]. 0 is flatland, 1 is the crest of a high
## range.
##
## [b]Three multiplied terms, each with a job.[/b]
## - [i]Ridged fractal[/i] supplies the range shape. Ridged noise builds crests
##   along continuous lines instead of isolated bumps, which is exactly the
##   difference between a mountain range and a field of spikes.
## - [i]Belt mask[/i] is a low-frequency field that decides which parts of the
##   continent are tectonically active. Multiplying by it gives mountain
##   [i]provinces[/i] separated by wide flatlands, rather than mountains sprayed
##   evenly over every continent.
## - [i]Inland gate[/i] keeps ranges away from the coast, so the coastline stays
##   low and the ranges sit behind it.
##
## [b]Precedent.[/b] Belt-shaped mountain provinces driven by a falloff from a
## tectonic boundary come from Guy-Shalev/terrain-generator (MIT), whose
## elevation module multiplies a range amplitude by an exponential falloff from
## the nearest plate boundary (`_ramp` / `_band` in its `terrain/elevation.py`).
## M1 borrows the [i]idea[/i] - a smooth falloff masks where relief applies - and
## implements it with ridged fractal noise instead of simulated plates, because
## plate simulation costs far more than the visual difference is worth on a
## mobile target. No code was copied.

const MODULE_ID := &"mountainness"
const OUTPUT_FIELD := &"mountainness"

## Ridged noise is mapped through these bounds so that only real crests read as
## mountains; everything below stays flatland.
const RIDGE_LOW := 0.38
const RIDGE_HIGH := 0.88

## Belt coverage: below LOW no mountains anywhere, above HIGH the whole belt is
## mountainous. Widened rather than narrowed so provinces have soft edges.
const BELT_LOW := 0.20
const BELT_HIGH := 0.75

var _ridges: FastNoiseLite
var _belts: FastNoiseLite
var _continents_index := -1


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray([&"continentalness"]), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_continents_index = dependency_index(&"continentalness")
	_ridges = context.make_noise_stream(
			MODULE_ID,
			version,
			1,
			config.mountain_frequency,
			3,
			FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			FastNoiseLite.FRACTAL_RIDGED
	)
	_belts = context.make_noise_stream(
			MODULE_ID, version, 2, config.mountain_frequency * 0.35, 2
	)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]

	var ridge := clampf(_ridges.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var shaped := smoothstep(RIDGE_LOW, RIDGE_HIGH, ridge)

	var belt := clampf(_belts.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var belt_mask := smoothstep(BELT_LOW, BELT_HIGH, belt)

	# Two nested gates: land at all, then far enough inland for a range.
	# Ranges begin well behind the shoreline. The surface module independently
	# ramps relief with distance inland; this gate is what makes the mountain
	# field itself empty at the coast, so a belt cannot be merely damped there.
	var on_land := smoothstep(-0.04, 0.06, continents)
	var inland := smoothstep(0.10, 0.30, continents)

	values[get_output_index()] = shaped * belt_mask * on_land * inland
