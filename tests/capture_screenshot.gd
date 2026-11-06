extends Node

## Renders the game scene and writes a PNG.
##
## This is the only check that can confirm the terrain actually *renders* in 3D
## rather than merely existing as voxel data. It needs a real rendering device,
## so it cannot run under --headless.
##
## Usage:
##   godot --path . res://tests/capture_screenshot.tscn -- \
##       --out=/tmp/shot.png --warmup=8 --seed=1337 --distance=110 --pitch=-32 --yaw=35

var _out_path := "/tmp/voxel_shot.png"
var _warmup := 8.0
var _seed := -1
var _distance := -1.0
var _pitch := 999.0
var _yaw := 999.0
var _elapsed := 0.0
var _scene: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_path = arg.get_slice("=", 1)
		elif arg.begins_with("--warmup="):
			_warmup = float(arg.get_slice("=", 1))
		elif arg.begins_with("--seed="):
			_seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--distance="):
			_distance = float(arg.get_slice("=", 1))
		elif arg.begins_with("--pitch="):
			_pitch = float(arg.get_slice("=", 1))
		elif arg.begins_with("--yaw="):
			_yaw = float(arg.get_slice("=", 1))

	_scene = load("res://scenes/main.tscn").instantiate()
	add_child.call_deferred(_scene)
	await get_tree().process_frame
	_apply_overrides()


func _apply_overrides() -> void:
	var world: VoxelWorld = _scene.world
	var camera: OrbitCamera = _scene.camera
	if world == null or camera == null:
		return

	if _seed >= 0 and _seed != world.config.world_seed:
		world.set_world_seed(_seed)

	if _distance > 0.0:
		camera.distance = _distance
	if _pitch < 900.0:
		camera.pitch_degrees = _pitch
	if _yaw < 900.0:
		camera.yaw_degrees = _yaw
	camera.focus_on(Vector3(0.0, world.get_surface_height(0, 0), 0.0))


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _warmup:
		return
	set_process(false)
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_out_path)
	print("SCREENSHOT: path=%s error=%d size=%dx%d" % [_out_path, error, image.get_width(), image.get_height()])

	var world: VoxelWorld = _scene.world
	if world != null:
		var status := world.get_status()
		print("STATUS: seed=%d streaming_ready=%s" % [
			int(status["seed"]), str(status["streaming_ready"])])
	get_tree().quit(0)
