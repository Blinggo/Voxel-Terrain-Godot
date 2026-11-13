class_name MainScene
extends Node3D

## Scene wiring for the running game.
##
## Since M1 the camera also picks a sensible place to look at on startup, because
## a world can now legitimately be mostly ocean.
##
## Connects the three independent pieces - world, camera, debug overlay - and
## nothing else. Keeping the wiring here means [VoxelWorld] does not need to know
## that a camera or a UI exists, and [DebugPanel] does not need to know that a
## world exists. It is a plain node in the scene, not a singleton.

const STATUS_REFRESH_INTERVAL := 0.25

## How far out, and in what steps, the startup camera searches for land. 192
## voxels keeps the framed spot inside the streaming radius, so the view is
## already meshed by the time the first frames are drawn.
const LAND_SEARCH_RADIUS := 192
const LAND_SEARCH_STEP := 16

## Height above sea level that counts as "land worth framing".
const LAND_MARGIN := 4.0

@export var world: VoxelWorld
@export var camera: OrbitCamera
@export var debug_panel: DebugPanel

var _status_timer := 0.0


func _ready() -> void:
	if world == null or camera == null or debug_panel == null:
		push_error("MainScene is missing one of its node references.")
		return

	var flight_controls := FlightControls.new()
	flight_controls.camera = camera
	$DebugLayer.add_child(flight_controls)

	world.terrain_rebuilt.connect(_on_terrain_rebuilt)
	debug_panel.regenerate_requested.connect(_on_regenerate_requested)
	debug_panel.water_demo_requested.connect(_show_water_demo)
	debug_panel.density_mode_requested.connect(_toggle_density_mode)

	debug_panel.configure_from_config(world.config)

	# VoxelWorld builds in its own _ready, and children are readied before
	# their parent, so the first terrain already exists here.
	_focus_camera_on_origin()


func _process(delta: float) -> void:
	_status_timer += delta
	if _status_timer < STATUS_REFRESH_INTERVAL:
		return
	_status_timer = 0.0
	debug_panel.set_status(world.get_status())


func _on_terrain_rebuilt(_world_seed: int) -> void:
	# Keep the widgets truthful when the world is rebuilt by anything other than
	# the panel itself (a script, or a test).
	debug_panel.configure_from_config(world.config)
	if not camera.fly_mode:
		_focus_camera_on_origin()


func _on_regenerate_requested(request: Dictionary) -> void:
	var config := world.config.duplicate_config()
	config.world_seed = int(request.get("world_seed", config.world_seed))
	config.terrain_height = float(request.get("terrain_height", config.terrain_height))
	config.terrain_frequency = float(request.get("terrain_frequency", config.terrain_frequency))
	config.view_distance_voxels = int(request.get("view_distance_voxels", config.view_distance_voxels))
	config.vertical_view_distance_voxels = int(request.get("vertical_view_distance_voxels", config.vertical_view_distance_voxels))
	world.apply_config(config)


## Aims the camera at land near the world origin.
##
## Since M1 a world can legitimately be mostly ocean, and a camera parked on the
## seabed at the origin would show nothing but water on first launch. The search
## walks outwards in rings and takes the first ring that contains a column
## comfortably above sea level, preferring the highest column in that ring. It is
## deterministic: the same seed always frames the same place.
func _focus_camera_on_origin() -> void:
	var surface := world.get_surface()
	if surface == null:
		camera.focus_on(Vector3(0.0, world.get_surface_height(0, 0), 0.0))
		return

	var sea_level := surface.get_sea_level()
	var target := Vector2i.ZERO
	var target_height := surface.get_surface_height(0, 0)
	var found := false

	for radius in range(0, LAND_SEARCH_RADIUS + 1, LAND_SEARCH_STEP):
		var best_height := -INF
		var best_column := Vector2i.ZERO
		for offset in _ring_offsets(radius):
			var height := surface.get_surface_height(offset.x, offset.y)
			if height > best_height:
				best_height = height
				best_column = offset
		if best_height >= sea_level + LAND_MARGIN:
			target = best_column
			target_height = best_height
			found = true
			break

	if not found:
		# No land within the search radius: frame whatever is at the origin.
		target_height = surface.get_surface_height(target.x, target.y)

	camera.focus_on(Vector3(float(target.x), target_height, float(target.y)))


## Columns on the square ring at [param radius], plus the origin at radius 0.
func _ring_offsets(radius: int) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	if radius == 0:
		offsets.append(Vector2i.ZERO)
		return offsets
	for offset in range(-radius, radius + 1, LAND_SEARCH_STEP):
		offsets.append(Vector2i(offset, -radius))
		offsets.append(Vector2i(offset, radius))
		offsets.append(Vector2i(-radius, offset))
		offsets.append(Vector2i(radius, offset))
	return offsets


## Explicit debug landmark, labelled with its seed; no hidden generation changes.
func _show_water_demo() -> void:
	var cfg := world.config.duplicate_config()
	cfg.world_seed = 1337
	cfg.hydrology_enabled = true
	cfg.density_mode = 0
	cfg.terrain_height = 26.0
	world.apply_config(cfg)
	camera.set_fly_mode(false)
	camera.distance = 115.0
	camera.pitch_degrees = -35.0
	camera.yaw_degrees = 25.0
	camera.focus_on(Vector3(256,world.get_surface_height(256,-544),-544))


func _toggle_density_mode() -> void:
	var cfg := world.config.duplicate_config()
	cfg.density_mode = 1-cfg.density_mode
	var previous_target := camera.target
	var previous_pose := camera.global_transform
	world.apply_config(cfg)
	if camera.fly_mode:
		camera.global_transform = previous_pose
	else:
		camera.focus_on(previous_target)
