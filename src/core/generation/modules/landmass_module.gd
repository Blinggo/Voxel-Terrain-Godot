class_name LandmassModule
extends GenerationModule

## The effective land/sea signal: continental layout plus islands and coast shaping.
##
## Output: [code]-1.0 .. 1.0[/code], with the same meaning as
## [member ContinentalnessModule]'s field and the same thresholds: values above
## roughly zero are land, below are ocean.
##
## [b]What it composes, and why in one place.[/b]
## [codeblock]
## land = clamp(continentalness
##              + archipelago * island_strength
##              + coast_detail * coast_strength, -1, 1)
## [/codeblock]
## Islands and coastline detail are both corrections to the same signal, so they
## are added once, here, and every consumer - elevation, mountains, hills, valleys,
## plateaus, the surface composer, the classifier - reads the corrected value
## instead of the raw one. Without this compositing step each of those modules
## would need its own copy of the island and coast terms, and any change to island
## strength would have to be made in six places and could drift between them.
##
## [b]Kept separate from [method SurfaceModule] on purpose.[/b] This is dimensionless
## geography; the surface composer is the only module that converts a signal into
## voxels. Keeping the add here means land shape stays testable without a world
## height, and the sea-level behaviour defined by [method SurfaceModule] is
## unchanged: it still puts the waterline exactly where this field crosses
## [constant SurfaceModule.OCEAN_EDGE].
##
## [b]Bounded by clamping.[/b] Both corrections are added, then the sum is clamped,
## so no combination of them can put the field outside the range the rest of the
## pipeline's thresholds were calibrated against.

const MODULE_ID := &"landmass"
const OUTPUT_FIELD := &"landmass"

var _island_strength := 0.55
var _coast_strength := 0.14

var _continents_index := -1
var _archipelago_index := -1
var _coast_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([&"continentalness", &"archipelago", &"coast_detail"]),
			1
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_continents_index = dependency_index(&"continentalness")
	_archipelago_index = dependency_index(&"archipelago")
	_coast_index = dependency_index(&"coast_detail")
	_island_strength = config.island_strength
	_coast_strength = config.coast_strength


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	values[get_output_index()] = clampf(
			values[_continents_index]
			+ values[_archipelago_index] * _island_strength
			+ values[_coast_index] * _coast_strength,
			-1.0,
			1.0
	)
