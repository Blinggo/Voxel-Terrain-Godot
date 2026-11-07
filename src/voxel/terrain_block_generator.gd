class_name TerrainBlockGenerator
extends VoxelGeneratorScript

## Adapter between Voxel Tools and the project's terrain model.
##
## Its responsibility is narrow on purpose: translate a block of voxel
## coordinates into type ids and write them into the [VoxelBuffer] Voxel Tools
## hands us. It performs no terrain mathematics of its own - it asks
## [GeographicSurface] for the column heights and [BlockPalette] for the material.
## Geography therefore stays in `src/core/` and can be replaced without editing
## this file.
##
## [b]Threading.[/b] Voxel Tools may call [method _generate_block] on worker
## threads, and may call it for several blocks at once. This class mutates no
## state while generating: [method configure] runs once on the main thread
## before the generator is attached, and everything written is derived from the
## arguments. The only shared objects touched are the height field and the
## palette, both documented as read-only once configured.
##
## [b]Cost.[/b] One [method GeographicSurface.sample_block_heights] call per block
## - which shares node lookups and interpolation weights across all of the
## block's columns - plus at most three [method VoxelBuffer.fill_area] calls per
## column, instead of one noise call and one [method VoxelBuffer.set_voxel] per
## voxel. Crossing between GDScript and C++ is comparatively expensive, so both
## reductions matter on mobile.

var _surface: GeographicSurface
var _palette: BlockPalette


## Must be called on the main thread before the generator is given to a terrain.
func configure(surface: GeographicSurface, palette: BlockPalette) -> void:
	if surface == null or palette == null:
		push_error("TerrainBlockGenerator.configure(): surface and palette are required.")
		return
	_surface = surface
	_palette = palette


## Tells Voxel Tools which channels we write, so it can skip allocating and
## storing the rest.
func _get_used_channels_mask() -> int:
	return VoxelBuffer.CHANNEL_TYPE_BIT


func _generate_block(out_buffer: VoxelBuffer, origin_in_voxels: Vector3i, _lod: int) -> void:
	if _surface == null or _palette == null:
		# configure() was never called. Leave the block empty rather than
		# spamming errors from worker threads.
		return

	var block_size := out_buffer.get_size()
	var soil_depth := _palette.soil_depth
	var origin := origin_in_voxels

	# All column heights for this block in one call. The surface evaluates its
	# regional fields on a coarse node grid, so asking per block instead of per
	# column lets it reuse the same nodes for all 256 columns.
	var heights := _surface.sample_block_heights(
			Vector2i(origin.x, origin.z), Vector2i(block_size.x, block_size.z)
	)

	for z in range(block_size.z):
		for x in range(block_size.x):
			var surface := heights[z * block_size.x + x]

			# Local y of the topmost solid voxel of the column (the grass one).
			# Derived purely from the world position, never from the block, so
			# neighbouring blocks agree on shared voxels by construction.
			var top_local := int(floor(surface)) - origin.y
			if top_local < 0:
				# Whole column lies above the surface: air, nothing to write.
				continue

			# Ranges are half-open [lo, hi) in local y.
			var stone_hi := clampi(top_local - soil_depth, 0, block_size.y)
			var dirt_lo := stone_hi
			var dirt_hi := clampi(top_local, 0, block_size.y)

			if stone_hi > 0:
				out_buffer.fill_area(
						BlockPalette.STONE,
						Vector3i(x, 0, z),
						Vector3i(x + 1, stone_hi, z + 1),
						VoxelBuffer.CHANNEL_TYPE
				)
			if dirt_hi > dirt_lo:
				out_buffer.fill_area(
						BlockPalette.DIRT,
						Vector3i(x, dirt_lo, z),
						Vector3i(x + 1, dirt_hi, z + 1),
						VoxelBuffer.CHANNEL_TYPE
				)
			if top_local < block_size.y:
				out_buffer.fill_area(
						BlockPalette.GRASS,
						Vector3i(x, top_local, z),
						Vector3i(x + 1, top_local + 1, z + 1),
						VoxelBuffer.CHANNEL_TYPE
				)
