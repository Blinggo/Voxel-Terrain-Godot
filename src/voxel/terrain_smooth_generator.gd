class_name TerrainSmoothGenerator
extends VoxelGeneratorScript

## Height-field adapter, not a true Euclidean SDF: negative below the surface.
## Single-resolution VoxelTerrain only. Geography is sampled once per column.
## DEPTH_32_BIT avoids the installed extension's 16-bit distance quantization.
## Configuration is frozen before worker use; all temporaries are block-local.
var _surface: GeographicSurface

func configure(surface: GeographicSurface) -> void:
	_surface = surface

func _get_used_channels_mask() -> int:
	return 1 << VoxelBuffer.CHANNEL_SDF

func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	assert(lod == 0, "This adapter targets single-resolution VoxelTerrain")
	if _surface == null:
		return
	var size := buffer.get_size()
	var heights := _surface.sample_block_heights(Vector2i(origin.x, origin.z), Vector2i(size.x, size.z))
	# Uniform far-air/solid blocks need no per-voxel writes. Saturation is far
	# outside the surface; it does not clip height or shift the zero crossing.
	var low := INF
	var high := -INF
	for h in heights:
		low = minf(low, h)
		high = maxf(high, h)
	if float(origin.y) - high > 512.0:
		buffer.fill_f(512.0, VoxelBuffer.CHANNEL_SDF)
		return
	if float(origin.y + size.y) - low < -512.0:
		buffer.fill_f(-512.0, VoxelBuffer.CHANNEL_SDF)
		return
	for z in range(size.z):
		for x in range(size.x):
			var height := heights[z * size.x + x]
			for y in range(size.y):
				buffer.set_voxel_f(clampf(float(origin.y + y) - height, -512.0, 512.0), x, y, z, VoxelBuffer.CHANNEL_SDF)
	buffer.compress_uniform_channels()
