extends RefCounted

static func run(report, tree: SceneTree) -> void:
	var cfg := WorldConfig.new()
	var surface := GeographicSurface.new(cfg)
	var same := cfg.duplicate_config()
	same.vertical_view_distance_voxels = 256
	var other := GeographicSurface.new(same)
	var equal := true
	for x in range(-128, 128, 7):
		equal = equal and surface.get_surface_height(x, 17) == other.get_surface_height(x, 17)
	report.check("vertical streaming configuration does not change geography", equal)
	var tall := cfg.duplicate_config()
	tall.terrain_height = 2000.0
	var high_surface := GeographicSurface.new(tall)
	var peak := -INF
	for x in range(-1024, 1024, 32):
		peak = maxf(peak, high_surface.get_surface_height(x, -1472))
	report.check("real geographical stack produces heights above former ceiling", peak > 500.0, "peak %.2f" % peak)
	var deep := cfg.duplicate_config()
	deep.sea_level = -1000.0
	deep.base_height = -1000.0
	var low_surface := GeographicSurface.new(deep)
	report.check("geography has no fixed floor at y=2", low_surface.get_surface_height(0, 0) < -900.0)
	var adapter := TerrainSmoothGenerator.new()
	adapter.configure(surface)
	var h := surface.get_surface_height(7, 9)
	var origin := Vector3i(7, int(floor(h)) - 2, 9)
	var buffer := VoxelBuffer.new()
	buffer.create(2, 8, 2)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	adapter._generate_block(buffer, origin, 0)
	report.check("smooth density is negative below shared surface", buffer.get_voxel_f(0, 0, 0, VoxelBuffer.CHANNEL_SDF) < 0.0)
	report.check("smooth density is positive above shared surface", buffer.get_voxel_f(0, 7, 0, VoxelBuffer.CHANNEL_SDF) > 0.0)
	var exact := true
	for y in range(8):
		exact = exact and absf(buffer.get_voxel_f(0, y, 0, VoxelBuffer.CHANNEL_SDF) - (origin.y + y - h)) < 0.0001
	report.check("adapter samples same heights with continuous unit vertical increments", exact)
	var next := VoxelBuffer.new()
	next.create(2, 8, 2)
	next.set_channel_depth(VoxelBuffer.CHANNEL_SDF, VoxelBuffer.DEPTH_32_BIT)
	adapter._generate_block(next, origin + Vector3i(1, 0, 0), 0)
	report.check_equal("overlapping block density samples agree", next.get_voxel_f(0, 3, 0, VoxelBuffer.CHANNEL_SDF), buffer.get_voxel_f(1, 3, 0, VoxelBuffer.CHANNEL_SDF))
	for path in ["res://scenes/main.tscn", "res://scenes/smooth_terrain.tscn"]:
		var main = load(path).instantiate()
		tree.root.add_child.call_deferred(main)
		for i in range(5):
			await tree.process_frame
		var camera: OrbitCamera = main.camera
		var before := camera.global_transform
		camera.set_fly_mode(true)
		report.check("switch to fly preserves transform: " + path, camera.global_transform.is_equal_approx(before))
		camera.advance_fly(0.1, Vector3(1, 1, 1), false)
		report.check("fly movement changes position: " + path, camera.global_position.distance_to(before.origin) > 0.1)
		var controls: FlightControls = main.get_node("DebugLayer").get_child(-1)
		var press := InputEventScreenTouch.new()
		press.index = 7
		press.pressed = true
		press.position = controls._regions()[0].get_center()
		controls._input(press)
		var drag := InputEventScreenDrag.new()
		drag.index = 7
		drag.position = press.position + Vector2(30, -30)
		drag.relative = Vector2(30, -30)
		controls._input(drag)
		report.check("raw touch pad drives flight: " + path, camera.touch_move.x > 0.0 and camera.touch_move.z > 0.0)
		camera._unhandled_input(drag)
		report.check("fly touch does not enter orbit handler: " + path, camera._touches.is_empty())
		press.pressed = false
		controls._input(press)
		report.check("touch release stops commanded movement: " + path, camera.touch_move == Vector3.ZERO)
		var flown := camera.global_transform
		camera.set_fly_mode(false)
		report.check("switch to orbit preserves transform: " + path, camera.global_transform.is_equal_approx(flown))
		camera._refresh_transform()
		report.check("reconstructed orbit preserves view: " + path, camera.global_position.distance_to(flown.origin) < 0.001)
		var viewer: VoxelViewer = camera.get_node("VoxelViewer")
		main.world.config.vertical_view_distance_voxels = 192
		main.world.configure_viewers(128)
		report.check("independent vertical radius reaches viewer: " + path, is_equal_approx(viewer.view_distance_vertical_ratio, 1.5) and viewer.view_distance == 128)
		var world: VoxelWorld = main.world
		report.check("scene uses shared geographical modules: " + path, world.get_surface().get_module_ids() == surface.get_module_ids())
		var terrain := world.get_terrain()
		report.check("scene selects intended mesher: " + path, (terrain.mesher is VoxelMesherTransvoxel) == path.contains("smooth"))
		var area := AABB(camera.global_position - Vector3(16, 16, 16), Vector3(32, 32, 32))
		var start := Time.get_ticks_msec()
		while not terrain.is_area_meshed(area) and Time.get_ticks_msec() - start < 30000:
			await tree.process_frame
		report.check("scene actually streams and meshes: " + path, terrain.is_area_meshed(area), "%d ms" % (Time.get_ticks_msec() - start))
		main.queue_free()
		for i in range(5):
			await tree.process_frame
