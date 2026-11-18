extends SceneTree
const OUTPUT := "res://Documentation/Milestones/m51-evidence/"
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var only_site := ""
	var refined_only := false
	var output := OUTPUT
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--site="): only_site = arg.get_slice("=",1)
		elif arg == "--refined-only": refined_only = true
		elif arg.begins_with("--output="): output = arg.get_slice("=",1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var captures := 0
	for site in MountainShowcase.SITES:
		if not only_site.is_empty() and site.id != only_site: continue
		for smooth in [false,true]:
			for enabled in [false,true]:
				if refined_only and not enabled: continue
				var scene = load("res://scenes/smooth_terrain.tscn" if smooth else "res://scenes/main.tscn").instantiate()
				var cfg := WorldConfig.new()
				MountainShowcase.apply_profile(cfg,site)
				cfg.mountain_morphology_enabled = enabled
				cfg.view_distance_voxels = 256 if site.id == "distant" else 160
				cfg.vertical_view_distance_voxels = 160
				scene.get_node("World").config = cfg
				root.add_child(scene)
				var camera: OrbitCamera = scene.camera
				camera.distance = site.distance
				camera.pitch_degrees = site.pitch
				camera.yaw_degrees = site.yaw
				camera.focus_on(site.target)
				scene.get_node("DebugLayer").visible = false
				var world: VoxelWorld = scene.world
				var start := Time.get_ticks_msec()
				var ground := world.get_surface_height(int(site.target.x),int(site.target.z))
				var area := AABB(Vector3(site.target.x,ground,site.target.z)-Vector3(16,16,16),Vector3(32,32,32))
				var ready := false
				while Time.get_ticks_msec()-start < (90000 if site.id == "distant" else 45000):
					await process_frame
					ready = world.get_terrain().is_area_meshed(area) and world._water_view._tiles.size() >= 9 and world._water_view._thread == null
					if ready: break
				var ready_ms := Time.get_ticks_msec()-start
				var frame_start := Time.get_ticks_usec()
				for i in range(16): await process_frame
				await RenderingServer.frame_post_draw
				var frame_ms := (Time.get_ticks_usec()-frame_start)/16000.0
				var name := "%s_%s_%s.png" % [site.id,"smooth" if smooth else "blocky","m51" if enabled else "m5"]
				var image := root.get_texture().get_image()
				var error := image.save_png(output+name)
				captures += 1
				print("M51_CAPTURE ",name," ready=",ready," save=",error," ready_ms=",ready_ms," frame_ms=",frame_ms," static_MB=",Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0," pose=",camera.global_transform," seed=",site.seed)
				scene.queue_free()
				for i in range(8): await process_frame
				if error != OK or not ready:
					quit(1)
					return
	quit(0 if captures > 0 else 1)
