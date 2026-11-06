class_name OrbitCamera
extends Camera3D

## Inspection camera: orbits a target point, zooms, and pans.
##
## Supports mouse (desktop target) and touch (primary target) from the same
## code path. Touch input is read directly from [InputEventScreenTouch] /
## [InputEventScreenDrag]; mouse-from-touch emulation is disabled project-wide so
## a single finger drag does not get handled twice.
##
## The camera carries the [VoxelViewer] that drives streaming: wherever the
## camera goes, Voxel Tools loads blocks around it.

@export var target: Vector3 = Vector3(0.0, 30.0, 0.0)
@export var distance: float = 110.0
@export var min_distance: float = 12.0
@export var max_distance: float = 420.0

@export_range(-85.0, -1.0, 1.0) var pitch_degrees: float = -32.0
@export var yaw_degrees: float = 35.0

## Degrees of rotation per pixel of drag.
@export var orbit_sensitivity: float = 0.25

## Multiplier applied to [member distance] per wheel notch.
@export var zoom_step: float = 1.12

@export var pan_sensitivity: float = 0.9

var _orbiting := false
var _panning := false
var _last_mouse_position := Vector2.ZERO
var _touches: Dictionary = {}
var _pinch_reference := 0.0
var _pinch_reference_distance := 0.0


func _ready() -> void:
	_refresh_transform()


## Points the camera at a world position.
func focus_on(world_position: Vector3) -> void:
	target = world_position
	_refresh_transform()


## Resets orbit, distance and pitch to their defaults around the current target.
func reset_view() -> void:
	distance = 110.0
	pitch_degrees = -32.0
	yaw_degrees = 35.0
	_refresh_transform()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventScreenTouch:
		_handle_screen_touch(event)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			_orbiting = event.pressed
			_last_mouse_position = event.position
			_refresh_transform()
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			_last_mouse_position = event.position
			_refresh_transform()
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom(1.0 / zoom_step)
				_refresh_transform()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom(zoom_step)
				_refresh_transform()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var relative := event.position - _last_mouse_position
	_last_mouse_position = event.position

	if _orbiting:
		_orbit(relative)
	elif _panning:
		_pan(relative)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_last_mouse_position = event.position
		elif _touches.size() == 2:
			_begin_pinch()
	else:
		_touches.erase(event.index)
		if _touches.size() == 1:
			# Lifting one finger of a pinch: keep orbiting from the remaining one
			# without a jump.
			_last_mouse_position = _touches.values()[0]
		_pinch_reference = 0.0


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		_touches[event.index] = event.position

	var previous: Vector2 = _touches[event.index]
	_touches[event.index] = event.position

	if _touches.size() == 1:
		_orbit(event.position - previous)
	elif _touches.size() == 2:
		_update_pinch()


func _begin_pinch() -> void:
	var positions := _touches.values()
	_pinch_reference = (positions[0] as Vector2).distance_to(positions[1])
	_pinch_reference_distance = distance


func _update_pinch() -> void:
	var positions := _touches.values()
	var current := (positions[0] as Vector2).distance_to(positions[1])
	if _pinch_reference <= 1.0 or current <= 1.0:
		_begin_pinch()
		return
	# Pinch out (current > reference) should zoom in.
	distance = clampf(
			_pinch_reference_distance * (_pinch_reference / current),
			min_distance,
			max_distance
	)
	_refresh_transform()


func _orbit(relative_delta: Vector2) -> void:
	yaw_degrees -= relative_delta.x * orbit_sensitivity
	pitch_degrees = clampf(
			pitch_degrees - relative_delta.y * orbit_sensitivity,
			-85.0,
			-1.0
	)
	yaw_degrees = wrapf(yaw_degrees, -180.0, 180.0)
	_refresh_transform()


func _pan(relative_delta: Vector2) -> void:
	# Pan in the camera's own screen plane, scaled by distance so it feels the
	# same at every zoom level.
	var scale := distance * 0.0015 * pan_sensitivity
	var right := global_transform.basis.x
	var up := global_transform.basis.y
	target += (-right * relative_delta.x + up * relative_delta.y) * scale
	_refresh_transform()


func _zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)


func _refresh_transform() -> void:
	var yaw := deg_to_rad(yaw_degrees)
	var pitch := deg_to_rad(pitch_degrees)
	var offset := Vector3(
			distance * cos(pitch) * sin(yaw),
			-distance * sin(pitch),
			distance * cos(pitch) * cos(yaw)
	)
	global_position = target + offset
	look_at(target, Vector3.UP)
