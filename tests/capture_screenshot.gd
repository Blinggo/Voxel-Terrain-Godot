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
##
## An optional --center=x,z frames the shot on that column instead of the world
## origin, which is how the milestone screenshots reach specific landforms.
##
## [b]Exit codes.[/b] This script is consumed by CI, so a screenshot that was not
## written must not look like success:
##   0  PNG written, verified on disk, and reported with a SCREENSHOT_OK line
##   1  rendering produced no image
##   2  the scene did not come up (world or camera missing)
##   3  the output path is unusable (bad extension, directory not creatable)
##   4  PNG encoding or writing failed
##   5  the file is missing or empty after a successful save call

var _out_path := "/tmp/voxel_shot.png"
var _warmup := 8.0
var _seed := -1
var _center := Vector2.ZERO
var _center_set := false
var _distance := -1.0
var _pitch := 999.0
var _yaw := 999.0
var _elapsed := 0.0
var _scene: Node
var _finished := false

## How long to wait for a rendered frame before giving up. Without this the
## script waits on [signal RenderingServer.frame_post_draw] forever on a machine
## with no rendering device, which in CI is a hang rather than a failure.
const RENDER_TIMEOUT_SECONDS := 10.0


func _ready() -> void:
	# Fail immediately rather than waiting for a frame that can never arrive.
	if DisplayServer.get_name() == "headless":
		_fail(1, "no rendering device (running with the headless display server)")
		return

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
		elif arg.begins_with("--center="):
			var parts := arg.get_slice("=", 1).split(",")
			if parts.size() == 2:
				_center = Vector2(float(parts[0]), float(parts[1]))
				_center_set = true

	_scene = load("res://scenes/main.tscn").instantiate()
	add_child.call_deferred(_scene)
	await get_tree().process_frame
	_apply_overrides()


func _apply_overrides() -> void:
	var world: VoxelWorld = _scene.world
	var camera: OrbitCamera = _scene.camera
	if world == null or camera == null:
		printerr("SCREENSHOT_FAIL code=2 the main scene has no world or camera")
		get_tree().quit(2)
		return

	if _seed >= 0 and _seed != world.config.world_seed:
		world.set_world_seed(_seed)

	if _distance > 0.0:
		camera.distance = _distance
	if _pitch < 900.0:
		camera.pitch_degrees = _pitch
	if _yaw < 900.0:
		camera.yaw_degrees = _yaw
	# A capture can be framed on an arbitrary column, which is how the M1 shots
	# reach a mountain range or a coastline without hand-driving the camera.
	var focus_x := int(_center.x) if _center_set else 0
	var focus_z := int(_center.y) if _center_set else 0
	camera.focus_on(Vector3(float(focus_x), world.get_surface_height(focus_x, focus_z), float(focus_z)))


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < _warmup:
		return
	set_process(false)

	var watchdog := get_tree().create_timer(RENDER_TIMEOUT_SECONDS, true, false)
	watchdog.timeout.connect(
			func() -> void: _fail(1, "no frame was rendered within %.0f s" % RENDER_TIMEOUT_SECONDS))

	await RenderingServer.frame_post_draw
	if _finished:
		return
	_capture_and_exit()


func _capture_and_exit() -> void:
	var path_error := _prepare_output_path()
	if path_error != OK:
		_fail(3, "output path is unusable: %s" % _out_path)
		return

	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		_fail(1, "the viewport has no texture; is a rendering device available?")
		return

	var image := viewport_texture.get_image()
	if image == null or image.is_empty():
		_fail(1, "rendered image is empty; is a rendering device available?")
		return

	var error := image.save_png(_out_path)
	if error != OK:
		_fail(4, "save_png() failed with error %d for %s" % [error, _out_path])
		return

	# The save call can report success and still leave nothing behind (for
	# example on a full or read-only filesystem), so verify the file itself.
	var size_bytes := _file_size(_out_path)
	if size_bytes <= 0:
		_fail(5, "no data was written to %s" % _out_path)
		return

	var world: VoxelWorld = _scene.world
	if world != null:
		var status := world.get_status()
		print("STATUS: seed=%d streaming_ready=%s" % [
			int(status["seed"]), str(status["streaming_ready"])])

	# Single machine-checkable line for run_tests.sh and CI.
	_finished = true
	print("SCREENSHOT_OK path=%s bytes=%d size=%dx%d" % [
		_out_path, size_bytes, image.get_width(), image.get_height()])
	get_tree().quit(0)


## Makes sure the output can actually be written: absolute path, `.png`
## extension, and the containing directory created if needed.
func _prepare_output_path() -> Error:
	if _out_path.strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	if _out_path.get_extension().to_lower() != "png":
		return ERR_INVALID_PARAMETER

	var absolute := _out_path
	if not absolute.is_absolute_path():
		absolute = ProjectSettings.globalize_path(_out_path)
	_out_path = absolute

	var directory := absolute.get_base_dir()
	if directory.is_empty():
		return ERR_INVALID_PARAMETER
	if not DirAccess.dir_exists_absolute(directory):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(directory)
		if mkdir_error != OK:
			return mkdir_error
	return OK


func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


func _fail(code: int, message: String) -> void:
	if _finished:
		return
	_finished = true
	# Printed to stderr so CI logs separate a real failure from normal output.
	printerr("SCREENSHOT_FAIL code=%d %s" % [code, message])
	get_tree().quit(code)
