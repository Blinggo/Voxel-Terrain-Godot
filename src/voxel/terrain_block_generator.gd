class_name TerrainBlockGenerator
extends VoxelGeneratorScript

## Density/material data -> TYPE channel only. No geographical/density maths.
## configure() keeps the prior surface API for callers; worlds pass one shared
## TerrainDensity explicitly. Run-length writes avoid one native call per voxel.
var _density: TerrainDensity
var _palette: BlockPalette

func configure(surface: GeographicSurface, palette: BlockPalette, density: TerrainDensity = null) -> void:
	_density = density if density != null else TerrainDensity.new(surface)
	_palette = palette.create_snapshot()

func get_density() -> TerrainDensity:
	return _density

func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_TYPE_BIT

func _generate_block(buffer: VoxelBuffer, origin: Vector3i, lod: int) -> void:
	assert(lod == 0)
	if _density == null:
		return
	var size := buffer.get_size()
	if _density.is_height_derived():
		_write_legacy_spans(buffer,origin,size)
		return
	var uniform := _density.uniform_material(origin,size,_palette)
	if uniform >= 0:
		buffer.fill(uniform,VoxelBuffer.CHANNEL_TYPE)
		return
	var materials := _density.material_block(origin,size,_palette)
	buffer.fill(BlockPalette.AIR,VoxelBuffer.CHANNEL_TYPE)
	for z in range(size.z):
		for x in range(size.x):
			var start := (z*size.x+x)*size.y
			var run := 0
			var material := int(materials[start])
			for y in range(1,size.y+1):
				var next := int(materials[start+y]) if y < size.y else -1
				if next != material:
					if material != BlockPalette.AIR:
						buffer.fill_area(material,Vector3i(x,run,z),Vector3i(x+1,y,z+1),VoxelBuffer.CHANNEL_TYPE)
					run = y
					material = next
	buffer.compress_uniform_channels()


func _write_legacy_spans(buffer: VoxelBuffer, origin: Vector3i, size: Vector3i) -> void:
	var spans := _density.legacy_material_spans(origin,size,_palette)
	buffer.fill(BlockPalette.AIR,VoxelBuffer.CHANNEL_TYPE)
	for z in range(size.z):
		for x in range(size.x):
			var i := (z*size.x+x)*3
			var stone := spans[i]
			var dirt := spans[i+1]
			var grass := spans[i+2]
			if stone > 0:
				buffer.fill_area(BlockPalette.STONE,Vector3i(x,0,z),Vector3i(x+1,stone,z+1),VoxelBuffer.CHANNEL_TYPE)
			if dirt > stone:
				buffer.fill_area(BlockPalette.DIRT,Vector3i(x,stone,z),Vector3i(x+1,dirt,z+1),VoxelBuffer.CHANNEL_TYPE)
			if grass >= 0:
				buffer.set_voxel(BlockPalette.GRASS,x,grass,z,VoxelBuffer.CHANNEL_TYPE)
