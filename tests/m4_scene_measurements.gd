extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for smooth in [false,true]:
		for enabled in [false,true]:
			var scene = load("res://scenes/smooth_terrain.tscn" if smooth else "res://scenes/main.tscn").instantiate()
			var cfg := WorldConfig.new()
			cfg.hydrology_enabled = enabled
			scene.get_node("World").config = cfg
			root.add_child(scene)
			var camera: OrbitCamera = scene.camera
			camera.distance = 115.0
			camera.pitch_degrees = -35.0
			camera.yaw_degrees = 25.0
			camera.focus_on(Vector3(256,scene.world.get_surface_height(256,-544),-544))
			var world: VoxelWorld = scene.world
			var start := Time.get_ticks_msec()
			var area := AABB(Vector3(240,16,-560),Vector3(32,32,32))
			var ready := false
			while Time.get_ticks_msec()-start < 60000:
				await process_frame
				ready = world.get_terrain().is_area_meshed(area)
				if enabled:
					ready = ready and world._water_view._tiles.size() >= 9 and world._water_view._thread == null
				if ready:
					break
			var ready_ms := Time.get_ticks_msec()-start
			var frame_start := Time.get_ticks_usec()
			for i in range(20):
				await process_frame
			print("M4_RENDER smooth=",smooth," hydrology=",enabled," ready=",ready," ready_ms=",ready_ms," mean_frame_ms=",(Time.get_ticks_usec()-frame_start)/20000.0," static_MB=",Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0)
			scene.queue_free()
			for i in range(10):
				await process_frame
	quit()
