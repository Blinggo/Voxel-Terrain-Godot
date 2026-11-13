class_name TerrainDensity
extends RefCounted

## Shared solid field. Negative/zero solid, positive air. Not a Euclidean SDF.
## Legacy is exactly y-H, including M4 carving. Hybrid adds bounded, masked
## 3D modifiers. All adapter classification goes through this object; there is
## no Voxel Tools or scene-node dependency here.
const ALGORITHM_VERSION := 1
var surface: GeographicSurface
var _config: WorldConfig
var _profiles: LandformProfiles
var _geological: FastNoiseLite
var _structure: FastNoiseLite
var _roughness: FastNoiseLite
var _amplitudes := Vector3.ZERO
var _maximum_modifiers := Vector3.ZERO
const CONTROL_STRIDE := 32
## Measured uncached hybrid ~6.35 ms/block. Reuse 2D controls across vertical
## blocks; only standard footprints cached, 256*256*12 = 768 KiB payload.
const CONTROLS_CAPACITY := 256
var _controls_cache: Dictionary = {}
var _controls_mutex := Mutex.new()

func _init(geography: GeographicSurface) -> void:
	assert(geography != null)
	surface = geography
	_config = geography.get_config().duplicate_config()
	_profiles = LandformProfiles.new(_config.landform_profiles)
	var context := GenerationContext.new(_config.world_seed,_config.generation_version,_config)
	_geological = context.make_noise_stream(&"density",ALGORITHM_VERSION,1,_config.density_geological_frequency,1)
	_structure = context.make_noise_stream(&"density",ALGORITHM_VERSION,2,_config.density_structure_frequency,1)
	_roughness = context.make_noise_stream(&"density",ALGORITHM_VERSION,3,_config.density_roughness_frequency,1)
	_amplitudes = Vector3(maxf(0,_config.density_geological_amplitude),maxf(0,_config.density_structure_amplitude),maxf(0,_config.density_roughness_amplitude))
	for profile in _profiles.profiles:
		_maximum_modifiers.x = maxf(_maximum_modifiers.x,maxf(0,profile.geological_influence))
		_maximum_modifiers.y = maxf(_maximum_modifiers.y,maxf(0,profile.structure_influence))
		_maximum_modifiers.z = maxf(_maximum_modifiers.z,maxf(0,profile.roughness))
	_maximum_modifiers *= _amplitudes
	if _config.density_mode == 0:
		_maximum_modifiers = Vector3.ZERO
	if _config.density_warp_amplitude > 0:
		_structure.domain_warp_enabled = true
		_structure.domain_warp_amplitude = clampf(_config.density_warp_amplitude,0,8)
		_structure.domain_warp_frequency = 0.012

func sample_density(position: Vector3) -> float:
	var x := floori(position.x)
	var z := floori(position.z)
	var heights := surface.sample_block_heights(Vector2i(x,z),Vector2i(2,2))
	var height := lerpf(lerpf(heights[0],heights[1],position.x-x),lerpf(heights[2],heights[3],position.x-x),position.z-z)
	if _config.density_mode == 0:
		return position.y-height
	# The same integer-column metadata, bilinearly interpolated, is used by the
	# dense block path. This gives a continuous arbitrary-coordinate interface.
	var controls := _column_controls(Vector2i(x,z),Vector2i(2,2))
	var control: Vector3 = controls[0].lerp(controls[1],position.x-x).lerp(controls[2].lerp(controls[3],position.x-x),position.z-z)
	return _evaluate(position,height,control)

## y-major within each x/z column: index=(z*size.x+x)*size.y+y.
func sample_block(origin: Vector3i, size: Vector3i) -> PackedFloat32Array:
	var heights := surface.sample_block_heights(Vector2i(origin.x,origin.z),Vector2i(size.x,size.z))
	var controls := PackedVector3Array()
	if _config.density_mode == 1:
		controls = _column_controls(Vector2i(origin.x,origin.z),Vector2i(size.x,size.z))
	var result := PackedFloat32Array()
	result.resize(size.x*size.y*size.z)
	for z in range(size.z):
		for x in range(size.x):
			var h := heights[z*size.x+x]
			var start := (z*size.x+x)*size.y
			for y in range(size.y):
				if _config.density_mode == 0:
					result[start+y] = float(origin.y+y)-h
				else:
					result[start+y] = _evaluate(Vector3(origin.x+x,origin.y+y,origin.z+z),h,controls[z*size.x+x])
	return result

## One extra sample above the block classifies top-facing surfaces across blocks.
func material_block(origin: Vector3i, size: Vector3i, palette: BlockPalette) -> PackedByteArray:
	var values := sample_block(origin,Vector3i(size.x,size.y+1,size.z))
	var result := PackedByteArray()
	result.resize(size.x*size.y*size.z)
	for z in range(size.z):
		for x in range(size.x):
			var source_start := (z*size.x+x)*(size.y+1)
			var target_start := (z*size.x+x)*size.y
			for y in range(size.y):
				var d := values[source_start+y]
				var material := BlockPalette.AIR
				if d <= 0.0:
					if values[source_start+y+1] > 0.0:
						material = BlockPalette.GRASS
					elif floori(-d) <= palette.soil_depth:
						material = BlockPalette.DIRT
					else:
						material = BlockPalette.STONE
				result[target_start+y] = material
	return result


## Non-monotone in y when structural influence is strong: permits genuine local
## overhangs/undercuts, not a second displaced heightmap. Modulation is localized
## to a finite band, fading continuously to y-H. No cave network is introduced.
func _evaluate(position: Vector3, height: float, control: Vector3) -> float:
	var d := position.y-height
	var a := _amplitudes * control * smoothstep(_config.sea_level+4.0,_config.sea_level+14.0,height)
	var bound := a.x+a.y+a.z
	if bound < 0.00001:
		return d
	var band := maxf(24.0,bound*2.0)
	if absf(d) >= band:
		return d
	var modifier := 0.0
	if a.x > 0.0:
		modifier += a.x * clampf(_geological.get_noise_3d(position.x,position.y,position.z),-1,1)
	if a.y > 0.0:
		# Carve-only structural recesses below the outer surface, on steep
		# landforms. Unrestricted signed displacement made disconnected blobs
		# on the first rendered trial and was rejected.
		var structure := _structure.get_noise_3d(position.x,position.y*1.8,position.z)
		var recess_band := smoothstep(1.0,4.0,-d)*(1.0-smoothstep(12.0,24.0,-d))
		modifier += a.y * smoothstep(-0.05,0.65,structure) * recess_band
	if a.z > 0.0:
		modifier += a.z * clampf(_roughness.get_noise_3d(position.x,position.y,position.z),-1,1)
	return d + modifier*(1.0-smoothstep(band*0.65,band,absf(d)))

func _control_node(p: Vector2i) -> Vector3:
	var control := _profiles.density_controls(surface.get_field_at(&"landmass",p.x,p.y),
		surface.get_field_at(&"mountainness",p.x,p.y),surface.get_field_at(&"hills",p.x,p.y),
		surface.get_field_at(&"plateaus",p.x,p.y),surface.get_field_at(&"valleys",p.x,p.y),
		surface.get_field_at(&"elevation",p.x,p.y))
	var dx := surface.get_field_at(&"surface",p.x+16,p.y)-surface.get_field_at(&"surface",p.x-16,p.y)
	var dz := surface.get_field_at(&"surface",p.x,p.y+16)-surface.get_field_at(&"surface",p.x,p.y-16)
	var slope := Vector2(dx,dz).length()/32.0
	control.y *= smoothstep(0.25,0.8,slope)
	return control

func _column_controls(origin: Vector2i, size: Vector2i) -> PackedVector3Array:
	var cacheable := size == Vector2i(16,16)
	if cacheable:
		_controls_mutex.lock()
		if _controls_cache.has(origin):
			var cached: PackedVector3Array = _controls_cache[origin]
			_controls_mutex.unlock()
			return cached
		_controls_mutex.unlock()
	var result := PackedVector3Array()
	result.resize(size.x*size.y)
	var local_nodes: Dictionary = {}
	var local_tiles: Dictionary = {}
	var network := surface.get_drainage()
	for z in range(size.y):
		for x in range(size.x):
			var p := origin+Vector2i(x,z)
			var cell := Vector2i(floori(float(p.x)/CONTROL_STRIDE),floori(float(p.y)/CONTROL_STRIDE))
			for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
				var key: Vector2i = cell+offset
				if not local_nodes.has(key):
					local_nodes[key] = _control_node(key*CONTROL_STRIDE)
			var t := Vector2(p-cell*CONTROL_STRIDE)/float(CONTROL_STRIDE)
			var c00: Vector3 = local_nodes[cell]
			var c10: Vector3 = local_nodes[cell+Vector2i.RIGHT]
			var c01: Vector3 = local_nodes[cell+Vector2i.DOWN]
			var c11: Vector3 = local_nodes[cell+Vector2i.ONE]
			var control := c00.lerp(c10,t.x).lerp(c01.lerp(c11,t.x),t.y)
			# Protect ocean/coast with a continuous height margin. Basin envelopes
			# are conservatively protected; no volumetric river logic in adapters.
			var protection := 1.0
			if network != null:
				var tile_key := Vector2i(floori(float(p.x)/128),floori(float(p.y)/128))
				if not local_tiles.has(tile_key):
					local_tiles[tile_key] = network.tile_at(p)
				protection = _water_protection(Vector2(p),local_tiles[tile_key])
			result[z*size.x+x] = control*protection
	if cacheable:
		_controls_mutex.lock()
		if _controls_cache.size() >= CONTROLS_CAPACITY:
			_controls_cache.erase(_controls_cache.keys()[0])
		_controls_cache[origin] = result
		_controls_mutex.unlock()
	return result

static func _water_protection(point: Vector2, tile: Dictionary) -> float:
	var amount := 1.0
	for lake in tile.lakes:
		amount = minf(amount,smoothstep(128.0,160.0,point.distance_to(lake.center)))
	for edge in tile.segments:
		var a: Vector2 = edge.a
		var ab: Vector2 = edge.b-a
		var t := clampf((point-a).dot(ab)/ab.length_squared(),0,1)
		var w := lerpf(float(edge.wa),float(edge.wb),t)
		amount = minf(amount,smoothstep(w*4.0,w*4.0+8.0,point.distance_to(a+ab*t)))
	return amount

func is_height_derived() -> bool:
	return _config.density_mode == 0

## Exact fast-path encoding of the same legacy density/material classification.
## Three integers per column: stone end, dirt end, grass row (-1 if absent).
func legacy_material_spans(origin: Vector3i, size: Vector3i, palette: BlockPalette) -> PackedInt32Array:
	assert(is_height_derived())
	var heights := surface.sample_block_heights(Vector2i(origin.x,origin.z),Vector2i(size.x,size.z))
	var spans := PackedInt32Array()
	spans.resize(size.x*size.z*3)
	for i in range(heights.size()):
		var top := floori(heights[i])-origin.y
		spans[i*3] = clampi(top-palette.soil_depth,0,size.y)
		spans[i*3+1] = clampi(top,0,size.y)
		spans[i*3+2] = top if top >= 0 and top < size.y else -1
	return spans


func cache_stats() -> Dictionary:
	_controls_mutex.lock()
	var count := _controls_cache.size()
	_controls_mutex.unlock()
	return {"columns":count,"capacity":CONTROLS_CAPACITY,"max_payload_bytes":CONTROLS_CAPACITY*256*12}

func clear_cache() -> void:
	_controls_mutex.lock()
	_controls_cache.clear()
	_controls_mutex.unlock()


## Conservative bounds, not a sampled approximation. Blended influences are
## normalized, noise is bounded, protection/band/slope masks are all in [0,1].
## Structural recesses only increase D; signed bands can move it either way.
func _density_interval(origin: Vector3i, size: Vector3i) -> Vector2:
	var heights := surface.sample_block_heights(Vector2i(origin.x,origin.z),Vector2i(size.x,size.z))
	var signed_bound := _maximum_modifiers.x+_maximum_modifiers.z
	var minimum := INF
	var maximum := -INF
	for height in heights:
		minimum = minf(minimum,height)
		maximum = maxf(maximum,height)
	return Vector2(origin.y-maximum-signed_bound,origin.y+size.y-1-minimum+signed_bound+_maximum_modifiers.y)

func uniform_material(origin: Vector3i, size: Vector3i, palette: BlockPalette) -> int:
	var interval := _density_interval(origin,size)
	if interval.x > 0: return BlockPalette.AIR
	if interval.y < -palette.soil_depth-1: return BlockPalette.STONE
	return -1

## Encoding optimization only: exact result of clamping every field sample.
func uniform_sdf(origin: Vector3i, size: Vector3i, limit: float) -> float:
	var interval := _density_interval(origin,size)
	if interval.x >= limit: return limit
	if interval.y <= -limit: return -limit
	return NAN
