class_name DebugPanel
extends Control

## Debug overlay: exposes the generation parameters, reports generation
## status, and asks for a regeneration.
##
## The panel is deliberately dumb: it knows nothing about [VoxelWorld] or Voxel
## Tools. It reports what the user asked for through
## [signal regenerate_requested] and renders whatever status dictionary the
## scene hands it through [method set_status]. That keeps debug UI out of the
## generation code, and means the panel can be deleted without touching the
## world.
##
## Since M1 the status block also reports the geography under the viewer -
## terrain type, continentalness and mountainness - so a world can be read while
## flying over it.

signal regenerate_requested(request: Dictionary)
signal water_demo_requested

const RANDOM_SEED_LIMIT := 100000

## Key that turns the performance readout on and off.
const PROFILING_TOGGLE_KEY := KEY_F4

@onready var _vertical_field: NumericField = %VerticalField
@onready var _seed_field: NumericField = %SeedField
@onready var _height_field: NumericField = %HeightField
@onready var _frequency_field: NumericField = %FrequencyField
@onready var _view_distance_field: NumericField = %ViewDistanceField
@onready var _regenerate_button: Button = %RegenerateButton
@onready var _random_seed_button: Button = %RandomSeedButton
@onready var _status_label: Label = %StatusLabel
@onready var _performance_label: Label = %PerformanceLabel
@onready var _panel: PanelContainer = %PanelContainer


## Profiling is on by default; turning it off stops sampling entirely and
## hides the readout, so a device run can be done with the overlay quiet.
var _profiling_enabled := true
var _perf := PerformanceSampler.new()


func _ready() -> void:
	_regenerate_button.pressed.connect(_emit_regeneration)
	_random_seed_button.pressed.connect(_randomise_seed)
	var demo := Button.new()
	demo.text = "Lake demo (seed 1337)"
	demo.focus_mode = Control.FOCUS_NONE
	demo.pressed.connect(func(): water_demo_requested.emit())
	demo.position = Vector2(610,12)
	demo.size = Vector2(220,48)
	add_child(demo)
	_panel.visible = true
	set_profiling_enabled(_profiling_enabled)


## Fills the widgets from a configuration snapshot without emitting a request.
func configure_from_config(config: WorldConfig) -> void:
	if config == null:
		return
	_seed_field.set_value_silent(config.world_seed)
	_height_field.set_value_silent(config.terrain_height)
	_frequency_field.set_value_silent(config.terrain_frequency)
	_view_distance_field.set_value_silent(config.view_distance_voxels)
	_vertical_field.set_value_silent(config.vertical_view_distance_voxels)


## Renders a status snapshot produced by [method VoxelWorld.get_status].
func set_status(status: Dictionary) -> void:
	if status.is_empty():
		return

	# Streaming statistics come from Voxel Tools through the world; the panel
	# only displays them and never queries the extension itself.
	var voxel_statistics: Dictionary = status.get("voxel_statistics", {})
	if not voxel_statistics.is_empty():
		_perf.set_voxel_statistics(voxel_statistics)

	# Rebuild cost is reported by the world because it is the only place that
	# knows when a rebuild starts and ends. Only a new measurement is recorded,
	# so the average is not padded with repeats of the same number.
	var rebuild_ms := float(status.get("last_rebuild_ms", 0.0))
	if rebuild_ms > 0.0 and not is_equal_approx(rebuild_ms, _perf.get_section_ms("rebuild")):
		_perf.record_section("rebuild", rebuild_ms)

	_refresh_performance()
	var viewer_position: Vector3 = status.get("viewer_position", Vector3.ZERO)
	_status_label.text = "\n".join([
		"seed            %d" % int(status.get("seed", 0)),
		"builds          %d" % int(status.get("build_count", 0)),
		"streaming       %s" % ("ready" if bool(status.get("streaming_ready", false)) else "loading…"),
		"viewer          %d, %d, %d" % [
			int(viewer_position.x), int(viewer_position.y), int(viewer_position.z)
		],
		"dropped         %d loads / %d meshes" % [
			int(status.get("dropped_loads", 0)),
			int(status.get("dropped_meshes", 0)),
		],
		# Geography under the viewer, from the module pipeline. Absent keys are
		# tolerated so the panel keeps working with a bare status dictionary.
		"terrain         %s @ %.1f" % [
			String(status.get("terrain_type", "?")),
			float(status.get("surface_height_here", 0.0)),
		],
		# Two lines rather than one: M2 added fields the owner needs to see while
		# testing formations in the editor, and a single line would not fit.
		"fields          land %+.2f  mtn %.2f" % [
			float(status.get("landmass", 0.0)),
			float(status.get("mountainness", 0.0)),
		],
		"                tec %+.2f  plt %.2f  val %.2f" % [
			float(status.get("tectonics", 0.0)),
			float(status.get("plateaus", 0.0)),
			float(status.get("valleys", 0.0)),
		],
	])


## Enables or disables the performance readout. Disabled means no sampling at
## all, not just a hidden label.
func set_profiling_enabled(value: bool) -> void:
	_profiling_enabled = value
	_perf.enabled = value
	if _performance_label != null:
		_performance_label.visible = value
	set_process(value)
	if value:
		_performance_label.text = "perf: sampling…"


func is_profiling_enabled() -> bool:
	return _profiling_enabled


## Reports the duration of one phase, in milliseconds. Used by the scene wiring
## to record a full world rebuild; future generation modules can record their
## own phases without touching this method.
func record_section_ms(section_name: String, elapsed_ms: float) -> void:
	_perf.record_section(section_name, elapsed_ms)


## Snapshot of everything measured, for logs and tests.
func get_performance_report() -> Dictionary:
	return _perf.get_report()


func _process(delta: float) -> void:
	# The display is refreshed on the status cadence (a few times per second),
	# but frame times must be sampled every frame or the maximum is meaningless.
	_perf.sample(delta)


## Formats the readout. Called from [method set_status] so it shares the
## overlay's existing refresh rate instead of running every frame.
func _refresh_performance() -> void:
	if not _profiling_enabled:
		return
	var frames: Dictionary = _perf.get_frame_report()
	var memory: Dictionary = _perf.get_memory_report()
	var voxel: Dictionary = _perf.get_voxel_statistics()

	var lines: Array[String] = []
	if int(frames.get("frames", 0)) == 0:
		# Nothing to report until the first one-second window has closed, and
		# printing 0.0 fps in the meantime would look like a stalled game.
		lines.append("fps measuring…")
	else:
		lines.append("fps %.1f  frame %.1f ms  max %.1f ms" % [
			float(frames.get("fps", 0.0)),
			float(frames.get("frame_ms_avg", 0.0)),
			float(frames.get("frame_ms_max", 0.0)),
		])
	lines.append("godot mem %.1f MB  objects %d  nodes %d" % [
		float(memory.get("static_bytes", 0.0)) / (1024.0 * 1024.0),
		int(memory.get("object_count", 0)),
		int(memory.get("object_node_count", 0)),
	])

	# Voxel Tools reports its phase timings in microseconds, per frame. Missing
	# keys are shown as "-" rather than invented.
	if voxel.is_empty():
		lines.append("voxel   statistics unavailable")
	else:
		lines.append("voxel   update %s  load %s  detect %s" % [
			_format_microseconds(voxel.get("time_request_blocks_to_update")),
			_format_microseconds(voxel.get("time_request_blocks_to_load")),
			_format_microseconds(voxel.get("time_detect_required_blocks")),
		])

	var rebuild_ms := _perf.get_section_ms("rebuild")
	if rebuild_ms > 0.0:
		lines.append("rebuild %.1f ms" % rebuild_ms)

	_performance_label.text = "\n".join(lines)


func _format_microseconds(value: Variant) -> String:
	if value == null:
		return "-"
	return "%.2f ms" % (float(value) / 1000.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				_panel.visible = not _panel.visible
				get_viewport().set_input_as_handled()
			KEY_R:
				_emit_regeneration()
				get_viewport().set_input_as_handled()
			PROFILING_TOGGLE_KEY:
				set_profiling_enabled(not _profiling_enabled)
				get_viewport().set_input_as_handled()


func _randomise_seed() -> void:
	# A local generator: seeding it from the clock is fine here because the UI
	# is the only consumer, and the chosen value then becomes an explicit,
	# recorded world seed. No global RNG is involved in terrain generation.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_seed_field.set_value_silent(rng.randi_range(0, RANDOM_SEED_LIMIT))
	_emit_regeneration()


func _emit_regeneration() -> void:
	# Apply any text the user is still typing before it is read, so that
	# "type a seed, then press Regenerate" uses what is on screen. Invalid or
	# half-typed text is discarded by the field itself and the previous good
	# value is used instead.
	_seed_field.commit_pending()
	_height_field.commit_pending()
	_frequency_field.commit_pending()
	_view_distance_field.commit_pending()
	_vertical_field.commit_pending()

	regenerate_requested.emit({
		"world_seed": int(_seed_field.get_value()),
		"terrain_height": float(_height_field.get_value()),
		"terrain_frequency": float(_frequency_field.get_value()),
		"view_distance_voxels": int(_view_distance_field.get_value()),
		"vertical_view_distance_voxels": int(_vertical_field.get_value()),
	})
