class_name VoxelTerrainBuilder
extends RefCounted

## Creates and configures the Voxel Tools terrain node.
##
## This is the only place that knows about [VoxelTerrain] configuration details.
## Streaming, threading, meshing and block bookkeeping are all delegated to Voxel
## Tools: M0.1 deliberately does not implement a second chunk system on top of
## the one the library already provides.

## Must match the value the blocky mesher and the generator assume. 16 keeps
## mesh uploads small, which is friendlier to mobile GPUs than 32.
const MESH_BLOCK_SIZE := 16


static func create_terrain(
		generator: VoxelGeneratorScript,
		mesher: VoxelMesher,
		material: Material,
		view_distance_voxels: int
) -> VoxelTerrain:
	var terrain := VoxelTerrain.new()
	terrain.name = "VoxelTerrain"

	# The blocky mesher needs a 16-bit type channel: 8 bits would cap the world
	# at 256 block types and 1 bit cannot represent ids at all. Setting it on the
	# format means every buffer the terrain hands to the generator is already
	# configured, so generation never has to reallocate.
	var format := VoxelFormat.new()
	format.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	terrain.format = format

	terrain.generator = generator
	terrain.mesher = mesher
	terrain.material_override = material

	terrain.mesh_block_size = MESH_BLOCK_SIZE

	# Collision meshing is a significant extra cost and M0.1 has no physics
	# bodies interacting with the world, so it stays off. M0.2 can enable it
	# behind a WorldConfig flag when a character controller exists.
	terrain.generate_collisions = false

	# GPU generation needs compute shader support; it is not a mobile baseline
	# and is off by default. Stated explicitly so the choice is visible.
	terrain.set_generator_use_gpu(false)

	terrain.set_max_view_distance(view_distance_voxels)

	return terrain
