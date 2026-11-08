class_name HydrologyWaterView
extends Node3D

## Shared diagnostic water geometry, independent of either terrain mesher.
## One bounded background tile task; main thread only uploads the finished mesh.
const SPACING := 2
var surface: GeographicSurface
var viewer_position := Vector3.ZERO
var radius := 128
var vertical_radius := 128
var _tiles: Dictionary = {}
var _thread: Thread
var _pending := Vector2i.ZERO
var _material: ShaderMaterial

func _ready() -> void:
	# Clip diagnostic water conservatively to nearby streamed terrain. Otherwise
	# a whole 128-wide water tile can draw beyond the terrain's loaded shore.
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform vec3 viewer;
uniform float horizontal_radius = 112.0;
uniform float vertical_radius = 112.0;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    if (distance(world_position.xz, viewer.xz) > horizontal_radius || abs(world_position.y-viewer.y) > vertical_radius) { discard; }
    ALBEDO = vec3(0.08, 0.38, 0.65);
    ROUGHNESS = 0.35;
}
"""
	_material = ShaderMaterial.new()
	_material.shader = shader

func _process(_delta: float) -> void:
	if surface == null or surface.get_drainage() == null:
		return
	_material.set_shader_parameter("viewer",viewer_position)
	_material.set_shader_parameter("horizontal_radius",maxi(16,radius-16))
	_material.set_shader_parameter("vertical_radius",maxi(16,vertical_radius-16))
	var center := Vector2i(floori(viewer_position.x / 128.0), floori(viewer_position.z / 128.0))
	var reach := maxi(1, ceili(float(radius) / 128.0))
	if _thread != null and not _thread.is_alive():
		var vertices: PackedVector3Array = _thread.wait_to_finish()
		_thread = null
		if not vertices.is_empty():
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			var normals := PackedVector3Array()
			normals.resize(vertices.size())
			normals.fill(Vector3.UP)
			arrays[Mesh.ARRAY_NORMAL] = normals
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			instance.material_override = _material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
			_tiles[_pending] = instance
		else:
			_tiles[_pending] = null
	for key in _tiles.keys():
		if absi(key.x-center.x) > reach or absi(key.y-center.y) > reach:
			if is_instance_valid(_tiles[key]):
				_tiles[key].queue_free()
			_tiles.erase(key)
	if _thread != null:
		return
	for z in range(-reach, reach+1):
		for x in range(-reach, reach+1):
			var key := center + Vector2i(x,z)
			if not _tiles.has(key):
				_pending = key
				_thread = Thread.new()
				_thread.start(build_tile.bind(surface, key))
				return

func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

static func build_tile(geography: GeographicSurface, key: Vector2i) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	var network := geography.get_drainage()
	var tile := network.tile_at(key * 128)
	if tile.segments.is_empty() and tile.lakes.is_empty():
		return vertices
	var levels := PackedFloat32Array()
	levels.resize(65 * 65)
	levels.fill(-INF)
	# Bulk geographical reads retain existing coarse/fine sampling reuse.
	for z in range(65):
		var row := geography.sample_unmodified_heights(key * 128 + Vector2i(0,z*2), Vector2i(129,1))
		for x in range(65):
			var p := key * 128 + Vector2i(x*2,z*2)
			var sample := network.sample(Vector2(p), row[x*2], tile)
			if sample.w >= 2.0:
				levels[z*65+x] = sample.y + 0.05
	for z in range(64):
		for x in range(64):
			for triangle in [[Vector2i(x,z),Vector2i(x+1,z),Vector2i(x,z+1)], [Vector2i(x+1,z),Vector2i(x+1,z+1),Vector2i(x,z+1)]]:
				var valid := true
				for p in triangle:
					valid = valid and is_finite(levels[p.y*65+p.x])
				if valid:
					for p in triangle:
						vertices.append(Vector3(key.x*128+p.x*2,levels[p.y*65+p.x],key.y*128+p.y*2))
	return vertices
