extends SceneTree

const SITES := [
	{"id":"plains","seed":1337,"target":Vector3(128,38,128),"distance":135.0,"pitch":-18.0,"yaw":35.0},
	{"id":"hills","seed":4242,"target":Vector3(704,44,960),"distance":120.0,"pitch":-22.0,"yaw":35.0},
	{"id":"plateau","seed":1337,"target":Vector3(192,58,-1472),"distance":140.0,"pitch":-24.0,"yaw":35.0},
	{"id":"basin","seed":1337,"target":Vector3(320,30,-640),"distance":160.0,"pitch":-50.0,"yaw":25.0},
	{"id":"coast","seed":90210,"target":Vector3(0,28,768),"distance":140.0,"pitch":-25.0,"yaw":35.0},
	{"id":"range","seed":1337,"target":Vector3(-64,90,-1472),"distance":110.0,"pitch":-18.0,"yaw":-180.0}
]
const OUTPUT := "res://Documentation/Milestones/m5-evidence/"
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for site in SITES:
		for smooth in [false,true]:
			for mode in [0,1]:
				var scene = load("res://scenes/smooth_terrain.tscn" if smooth else "res://scenes/main.tscn").instantiate()
				var cfg := WorldConfig.new()
				cfg.world_seed = site.seed
				cfg.density_mode = mode
				cfg.view_distance_voxels = 192
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
				var area := AABB(site.target-Vector3(16,16,16),Vector3(32,32,32))
				var ready := false
				while Time.get_ticks_msec()-start < 30000:
					await process_frame
					ready = world.get_terrain().is_area_meshed(area)
					ready = ready and world._water_view._tiles.size() >= 9 and world._water_view._thread == null
					if ready: break
				var ready_ms := Time.get_ticks_msec()-start
				var frame_start := Time.get_ticks_usec()
				for i in range(12): await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				var name := "%s_%s_%s.png" % [site.id,"smooth" if smooth else "blocky","hybrid" if mode == 1 else "legacy"]
				var error := image.save_png(OUTPUT+name)
				print("M5_CAPTURE ",name," ready=",ready," error=",error," ready_ms=",ready_ms," mean_frame_ms=",(Time.get_ticks_usec()-frame_start)/12000.0," static_MB=",Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0," pose=",camera.global_transform," seed=",site.seed)
				if error != OK:
					quit(1)
					return
				scene.queue_free()
				for i in range(8): await process_frame
	quit()
