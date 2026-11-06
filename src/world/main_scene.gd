class_name MainScene
extends Node3D

## Scene wiring for M0.1.
##
## Connects the three independent pieces - world, camera, debug overlay - and
## nothing else. Keeping the wiring here means [VoxelWorld] does not need to know
## that a camera or a UI exists, and [DebugPanel] does not need to know that a
## world exists. It is a plain node in the scene, not a singleton.

const STATUS_REFRESH_INTERVAL := 0.25

@export var world: VoxelWorld
@export var camera: OrbitCamera
@export var debug_panel: DebugPanel

var _status_timer := 0.0


func _ready() -> void:
	if world == null or camera == null or debug_panel == null:
		push_error("MainScene is missing one of its node references.")
		return

	world.terrain_rebuilt.connect(_on_terrain_rebuilt)
	debug_panel.regenerate_requested.connect(_on_regenerate_requested)

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
	_focus_camera_on_origin()


func _on_regenerate_requested(request: Dictionary) -> void:
	var config := world.config.duplicate_config()
	config.world_seed = int(request.get("world_seed", config.world_seed))
	config.terrain_height = float(request.get("terrain_height", config.terrain_height))
	config.terrain_frequency = float(request.get("terrain_frequency", config.terrain_frequency))
	config.view_distance_voxels = int(request.get("view_distance_voxels", config.view_distance_voxels))
	world.apply_config(config)


## Aims the camera at the surface directly above the world origin, so a fresh
## world is always framed sensibly regardless of its seed.
func _focus_camera_on_origin() -> void:
	var surface := world.get_surface_height(0, 0)
	camera.focus_on(Vector3(0.0, surface, 0.0))
