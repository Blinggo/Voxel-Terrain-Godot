class_name FlightControls
extends Control

## Raw touch ownership is per finger; no mouse emulation or orbit event sharing.
var camera: OrbitCamera
var _fingers: Dictionary = {}
var _mode: Button
var _last_fly_mode := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode = Button.new()
	_mode.text = "Orbit / Fly (F)"
	_mode.position = Vector2(420, 12)
	_mode.size = Vector2(180, 48)
	_mode.focus_mode = Control.FOCUS_NONE
	_mode.pressed.connect(func():
		camera.set_fly_mode(not camera.fly_mode)
		_fingers.clear()
		queue_redraw())
	add_child(_mode)

func _draw() -> void:
	if camera == null or not camera.fly_mode:
		return
	for rect in _regions():
		draw_style_box(get_theme_stylebox("panel", "Panel"), rect)
	var labels := ["MOVE", "LOOK", "UP", "DOWN", "BOOST"]
	var regions := _regions()
	for i in range(regions.size()):
		draw_string(ThemeDB.fallback_font, regions[i].position + Vector2(12, 30), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)

func _regions() -> Array[Rect2]:
	var size := get_viewport_rect().size
	return [Rect2(20, size.y - 160, 150, 140), Rect2(size.x - 230, size.y - 200, 210, 180),
		Rect2(size.x - 340, size.y - 200, 90, 60), Rect2(size.x - 340, size.y - 130, 90, 60),
		Rect2(190, size.y - 90, 110, 70)]

func _input(event: InputEvent) -> void:
	if camera == null or not camera.fly_mode:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var regions := _regions()
			for i in range(regions.size()):
				if regions[i].has_point(event.position):
					_fingers[event.index] = {"region": i, "start": event.position, "delta": Vector2.ZERO}
					get_viewport().set_input_as_handled()
		elif _fingers.has(event.index):
			_fingers.erase(event.index)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _fingers.has(event.index):
		var finger: Dictionary = _fingers[event.index]
		finger.delta = (event.position - finger.start) / 55.0
		if finger.region == 1:
			camera.fly_look(event.relative)
		get_viewport().set_input_as_handled()
	else:
		return
	camera.touch_move = Vector3.ZERO
	camera.touch_boost = false
	for finger in _fingers.values():
		match int(finger.region):
			0:
				var axis: Vector2 = finger.delta.limit_length(1.0)
				camera.touch_move.x = axis.x
				camera.touch_move.z = -axis.y
			2: camera.touch_move.y += 1.0
			3: camera.touch_move.y -= 1.0
			4: camera.touch_boost = true

func _process(_delta: float) -> void:
	if camera != null and camera.fly_mode != _last_fly_mode:
		clear_input()
		_last_fly_mode = camera.fly_mode
	queue_redraw()


func clear_input() -> void:
	_fingers.clear()
	if is_instance_valid(camera):
		camera.touch_move = Vector3.ZERO
		camera.touch_boost = false
		camera.fly_velocity = Vector3.ZERO

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		clear_input()
