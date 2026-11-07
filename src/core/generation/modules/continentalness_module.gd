class_name ContinentalnessModule
extends GenerationModule

## How far out to sea, or how far inland, a place is.
##
## Output: [code]-1.0 .. 1.0[/code], where strongly negative is open ocean,
## around zero is a coastline, and strongly positive is a continental interior.
##
## [b]Algorithm.[/b] A low-frequency fractal simplex field, domain-warped by two
## independent fields of its own. The warp is what stops the result looking like
## a repeating noise lattice: it displaces the sample coordinate by up to
## [member WorldConfig.continent_warp] voxels before lookup, so continent shapes
## bend and pinch instead of repeating on a period.
##
## [b]Precedent.[/b] The idea of deforming a low-frequency field with another
## noise before picking terrain type is standard in procedural world generators;
## the domain warp follows the `warp()` helper of Guy-Shalev/terrain-generator
## (MIT), and the layered continent/elevation split follows the same project's
## separation of continent-scale and relief-scale fields. No code was copied: the
## warp is re-expressed on top of Godot's own [FastNoiseLite].
##
## [b]Cost.[/b] Three noise lookups per node. Nodes are spaced
## [member WorldConfig.sampling_stride] voxels apart, so this is a small fraction
## of a per-voxel cost.

const MODULE_ID := &"continentalness"
const OUTPUT_FIELD := &"continentalness"

var _base: FastNoiseLite
var _warp_x: FastNoiseLite
var _warp_z: FastNoiseLite
var _warp_amount := 0.0


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray(), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_base = context.make_noise(
			MODULE_ID, version, config.continent_frequency, config.continent_octaves
	)
	# Warp streams are 1.7x the base frequency: slower than the field itself, so
	# the deformation is smooth rather than jittery.
	_warp_x = context.make_noise_stream(
			MODULE_ID, version, 1, config.continent_frequency * 1.7, 2
	)
	_warp_z = context.make_noise_stream(
			MODULE_ID, version, 2, config.continent_frequency * 1.7, 2
	)
	_warp_amount = config.continent_warp


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var warp_x := _warp_x.get_noise_2d(x, z) * _warp_amount
	var warp_z := _warp_z.get_noise_2d(x, z) * _warp_amount
	# FastNoiseLite fractal output can overshoot [-1, 1] slightly at high octave
	# counts; clamping keeps the field's documented range true.
	var value := _base.get_noise_2d(float(x) + warp_x, float(z) + warp_z)
	values[get_output_index()] = clampf(value, -1.0, 1.0)
