class_name ElevationModule
extends GenerationModule

## Broad, multi-scale elevation offset.
##
## Output: [code]-1.0 .. 1.0[/code]; positive means the land is generally higher
## than [member WorldConfig.base_height] would suggest, negative means lower.
##
## [b]Why several scales.[/b] One octave count on one frequency gives either
## smooth blobs or uniform noise. Three separate bands - broad, medium, fine -
## give a landscape that has large regional tilts, medium basins and swells, and
## small undulations at the same time, each band still smooth enough to survive
## the node grid.
##
## [b]Dependence on continentalness.[/b] The signal is damped under deep ocean, so
## the seafloor gets its relief from the surface module's depth model rather than
## from this field, while land keeps the full range. Depending on the declared
## field rather than reading it out of order is what the registry enforces.

const MODULE_ID := &"elevation"
const OUTPUT_FIELD := &"elevation"

## Relative weights of the three bands. Sum is 1.0 so the output stays in range.
const BROAD_WEIGHT := 0.60
const MEDIUM_WEIGHT := 0.28
const FINE_WEIGHT := 0.12

var _broad: FastNoiseLite
var _medium: FastNoiseLite
var _fine: FastNoiseLite
var _continents_index := -1


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray([&"continentalness"]), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_continents_index = dependency_index(&"continentalness")
	_broad = context.make_noise_stream(
			MODULE_ID, version, 1, config.elevation_frequency, 2
	)
	_medium = context.make_noise_stream(
			MODULE_ID, version, 2, config.elevation_frequency * 2.7, 2
	)
	_fine = context.make_noise_stream(
			MODULE_ID, version, 3, config.elevation_frequency * 7.0, 2
	)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]

	# 0 in deep ocean, 1 on land. Only used to scale the signal, never to pick a
	# terrain type - that stays the surface module's job.
	var land := smoothstep(-0.35, 0.0, continents)
	var strength := lerpf(0.45, 1.0, land)

	var combined := (
			_broad.get_noise_2d(x, z) * BROAD_WEIGHT
			+ _medium.get_noise_2d(x, z) * MEDIUM_WEIGHT
			+ _fine.get_noise_2d(x, z) * FINE_WEIGHT
	) * strength

	values[get_output_index()] = clampf(combined, -1.0, 1.0)
