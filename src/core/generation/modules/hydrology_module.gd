class_name HydrologyModule
extends GenerationModule

## Registered post-surface hydrology. Scalar output is runoff eligibility, NOT
## the vector water query. Spatial network data is exposed by GeographicSurface.
## The network reads the same engine's uncarved heights, preventing feedback.
var network: DrainageNetwork
var _sea := 20.0
var _rise := 12.0
var _surface_index := -1
var _config_context: GenerationContext

func _init() -> void:
	super(&"hydrology", &"runoff_potential", PackedStringArray(["surface"]), 1)

func configure(context: GenerationContext) -> void:
	_config_context = context
	_sea = context.config.sea_level
	_rise = context.config.hydrology_source_rise
	_surface_index = dependency_index(&"surface")

func attach_engine(engine: GenerationEngine) -> void:
	if _config_context.config.hydrology_enabled:
		network = DrainageNetwork.new()
		network.configure(engine, _config_context, version)

func evaluate_node(_x: int, _z: int, values: PackedFloat32Array) -> void:
	values[get_output_index()] = smoothstep(_sea, _sea + _rise, values[_surface_index])

func shape_columns(heights: PackedFloat32Array, origin: Vector2i, size: Vector2i) -> void:
	if network == null:
		return
	var tile: Dictionary = {}
	var last_key := Vector2i(2147483647,2147483647)
	for z in range(size.y):
		for x in range(size.x):
			var p := origin + Vector2i(x,z)
			var key := Vector2i(floori(float(p.x)/DrainageNetwork.TILE), floori(float(p.y)/DrainageNetwork.TILE))
			if key != last_key:
				tile = network.tile_at(p)
				last_key = key
			var i := z * size.x + x
			heights[i] = network.sample(Vector2(p), heights[i], tile).x
