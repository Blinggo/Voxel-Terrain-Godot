class_name TerrainSmoothGenerator
extends VoxelGeneratorScript

## Shared density -> 32-bit SDF channel. No mesher-specific terrain maths.
const SDF_LIMIT := 32.0
var _density: TerrainDensity

func configure(surface: GeographicSurface, density: TerrainDensity = null) -> void:
	_density = density if density != null else TerrainDensity.new(surface)

func get_density() -> TerrainDensity:
	return _density

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	assert(lod == 0)
	if _density == null:
		return
	var size := buffer.get_size()
	var uniform := _density.uniform_sdf(origin,size,SDF_LIMIT)
	if not is_nan(uniform):
		buffer.fill_f(uniform,VoxelBuffer.CHANNEL_SDF)
		return
	var values := _density.sample_block(origin,size)
	for z in range(size.z):
		for x in range(size.x):
			var start := (z*size.x+x)*size.y
			for y in range(size.y):
				buffer.set_voxel_f(clampf(values[start+y],-SDF_LIMIT,SDF_LIMIT),x,y,z,VoxelBuffer.CHANNEL_SDF)
	buffer.compress_uniform_channels()
