extends SceneTree

## Reproducible Linux/runtime experiment, not a device benchmark.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for smooth in [false, true]:
		for vertical in [64, 128, 192]:
			var scene = load("res://scenes/smooth_terrain.tscn" if smooth else "res://scenes/main.tscn").instantiate()
			scene.get_node("World").config = WorldConfig.new()
			scene.get_node("World").config.vertical_view_distance_voxels = vertical
			root.add_child(scene)
			var world: VoxelWorld = scene.world
			var camera: OrbitCamera = scene.camera
			camera.set_fly_mode(true)
			for displacement in [Vector3.ZERO, Vector3(128, 0, 0), Vector3(0, 256, 0)]:
				camera.global_position += displacement
				var start := Time.get_ticks_msec()
				var area := AABB(camera.global_position - Vector3(16,16,16), Vector3(32,32,32))
				await process_frame
				while not world.get_terrain().is_area_meshed(area) and Time.get_ticks_msec() - start < 30000:
					await process_frame
				var ready_ms := Time.get_ticks_msec() - start
				var frame_start := Time.get_ticks_usec()
				for i in range(20):
					await process_frame
				print("M3_MEASURE smooth=%s vertical=%d move=%s ready=%s ready_ms=%d mean_frame_ms=%.2f static_mb=%.2f" % [smooth, vertical, displacement, world.get_terrain().is_area_meshed(area), ready_ms, (Time.get_ticks_usec()-frame_start)/20000.0, Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0])
			var generator := world.get_generator()
			var buffer := VoxelBuffer.new()
			buffer.create(16,16,16)
			buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
			buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
			var t := Time.get_ticks_usec()
			for i in range(100):
				generator._generate_block(buffer, Vector3i(i * 16, 16, 0), 0)
			print("M3_GENERATE smooth=%s vertical=%d us_per_block=%.2f" % [smooth, vertical, (Time.get_ticks_usec()-t)/100.0])
			scene.queue_free()
			for i in range(10):
				await process_frame
	quit()
