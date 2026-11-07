class_name DetailModule
extends GenerationModule

## Fine surface roughness, added per column at full resolution.
##
## Node-grid interpolation cannot carry structure finer than the stride, so this
## module is the pipeline's escape hatch: it declares
## [member GenerationModule.contributes_columns] and the engine adds its
## contribution to every column after interpolation.
##
## Output field: raw noise in [code]-1.0 .. 1.0[/code]. The height contribution
## is that value multiplied by [member WorldConfig.terrain_height] and
## [member WorldConfig.detail_scale], which keeps the module independent of how
## far apart the nodes are.
##
## [b]Cost.[/b] One noise lookup per column, the same as the M0.1 height field
## spent per column for everything. It is the only per-voxel-column cost in the
## pipeline.

const MODULE_ID := &"detail"
const OUTPUT_FIELD := &"detail"

var _noise: FastNoiseLite
var _amplitude := 0.0


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray(), 1)
	contributes_columns = true


func configure(context: GenerationContext) -> void:
	var config := context.config
	_noise = context.make_noise_stream(
			MODULE_ID, version, 1, config.terrain_frequency, config.fractal_octaves
	)
	_amplitude = config.terrain_height * config.detail_scale


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	# Recorded so the field is well defined at node resolution too; the engine
	# still adds the per-column term from sample_column().
	values[get_output_index()] = _noise.get_noise_2d(x, z)


func add_columns(heights: PackedFloat32Array, origin: Vector2i, size: Vector2i) -> void:
	# Hoisted out of the loop: one property read and one write per column would
	# otherwise cost more than the noise lookup in GDScript.
	var noise := _noise
	var amplitude := _amplitude
	var origin_x := origin.x
	var origin_z := origin.y
	for j in range(size.y):
		var world_z := origin_z + j
		var row := j * size.x
		for i in range(size.x):
			# Clamped because at extreme coordinates (|x| near 1e9) the underlying
			# float32 noise lattice degrades and can return values far outside
			# [-1, 1]. The documented contribution bound must hold everywhere.
			var value := clampf(noise.get_noise_2d(float(origin_x + i), float(world_z)), -1.0, 1.0)
			heights[row + i] += value * amplitude
