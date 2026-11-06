extends Node

## Measures generation cost. Run with:
##   godot --headless --path . res://tests/benchmark.tscn
##
## Two separate numbers matter and they are easy to confuse:
##   1. generator throughput - how long the CPU spends turning coordinates into
##      voxels, which is what a native reimplementation would target;
##   2. time to stream - how long a viewer waits before the region around it is
##      generated and meshed, which includes threading and mesh upload.

const BLOCKS_PER_AXIS := 5
const BLOCK_SIZE := 16
const REPEATS := 3


func _ready() -> void:
	print("")
	print("=== M0.1 generation benchmark ===")
	print("engine: %s" % Engine.get_version_info()["string"])
	print("cpu count: %d" % OS.get_processor_count())

	_benchmark_generator()
	await _benchmark_streaming()

	get_tree().quit(0)


func _make_generator(world_seed: int) -> TerrainBlockGenerator:
	var noise := FastNoiseLiteSource.new(world_seed, 0.008, 4)
	var field := TerrainHeightField.new(noise, 24.0, 26.0)
	var generator := TerrainBlockGenerator.new()
	generator.configure(field, BlockPalette.new())
	return generator


func _benchmark_generator() -> void:
	var generator := _make_generator(1337)
	var total_blocks := BLOCKS_PER_AXIS * BLOCKS_PER_AXIS * BLOCKS_PER_AXIS

	# Warm up once so JIT/allocator warm-up is not counted.
	var warm := VoxelBuffer.new()
	warm.create(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	warm.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	generator._generate_block(warm, Vector3i.ZERO, 0)

	var best_us := INF
	for _repeat in range(REPEATS):
		var start := Time.get_ticks_usec()
		for z in range(BLOCKS_PER_AXIS):
			for x in range(BLOCKS_PER_AXIS):
				for y in range(2):
					var buffer := VoxelBuffer.new()
					buffer.create(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
					buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
					generator._generate_block(
							buffer, Vector3i(x * BLOCK_SIZE, y * BLOCK_SIZE, z * BLOCK_SIZE), 0)
		var elapsed_us := Time.get_ticks_usec() - start
		# 2 layers of blocks per column
		var blocks := total_blocks * 2
		var per_block := float(elapsed_us) / float(blocks)
		best_us = minf(best_us, per_block)
		print("  generator pass %d: %d blocks in %.1f ms -> %.1f us/block, %.0f blocks/s (1 thread)" % [
			_repeat + 1, blocks, elapsed_us / 1000.0, per_block, 1e6 / per_block])

	print("  BEST: %.1f us per %d^3 block (single thread)" % [best_us, BLOCK_SIZE])


func _benchmark_streaming() -> void:
	var world := VoxelWorld.new()
	world.config = WorldConfig.new()
	world.build_on_ready = false

	var viewer := VoxelViewer.new()
	viewer.view_distance = 128
	viewer.requires_collisions = false
	add_child(world)
	add_child(viewer)
	viewer.add_to_group(VoxelWorld.VIEWER_GROUP)
	viewer.global_position = Vector3(0, 40, 0)

	# Wait for a frame so the viewer is registered before the world builds.
	await get_tree().process_frame
	world.rebuild()

	var start := Time.get_ticks_msec()
	var probe := AABB(Vector3(-32, 16, -32), Vector3(64, 64, 64))
	var ready := false
	var deadline := start + 60000
	while Time.get_ticks_msec() < deadline:
		if world.get_terrain() != null and world.get_terrain().is_area_meshed(probe):
			ready = true
			break
		await get_tree().process_frame
	var elapsed := Time.get_ticks_msec() - start

	print("  streaming region meshed: %s in %.2f s (view distance 128, vertical ratio 0.5)" % [
		str(ready), elapsed / 1000.0])

	var stats := world.get_terrain().get_statistics() if world.get_terrain() != null else {}
	print("  statistics: %s" % str(stats))
