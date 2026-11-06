class_name DebugPanel
extends Control

## Debug overlay for M0.1: exposes the generation parameters, reports generation
## status, and asks for a regeneration.
##
## The panel is deliberately dumb: it knows nothing about [VoxelWorld] or Voxel
## Tools. It reports what the user asked for through
## [signal regenerate_requested] and renders whatever status dictionary the
## scene hands it through [method set_status]. That keeps debug UI out of the
## generation code, and means the panel can be deleted without touching the
## world.

signal regenerate_requested(request: Dictionary)

const RANDOM_SEED_LIMIT := 100000

@onready var _seed_field: NumericField = %SeedField
@onready var _height_field: NumericField = %HeightField
@onready var _frequency_field: NumericField = %FrequencyField
@onready var _view_distance_field: NumericField = %ViewDistanceField
@onready var _regenerate_button: Button = %RegenerateButton
@onready var _random_seed_button: Button = %RandomSeedButton
@onready var _status_label: Label = %StatusLabel
@onready var _panel: PanelContainer = %PanelContainer


func _ready() -> void:
	_regenerate_button.pressed.connect(_emit_regeneration)
	_random_seed_button.pressed.connect(_randomise_seed)
	_panel.visible = true


## Fills the widgets from a configuration snapshot without emitting a request.
func configure_from_config(config: WorldConfig) -> void:
	if config == null:
		return
	_seed_field.set_value_silent(config.world_seed)
	_height_field.set_value_silent(config.terrain_height)
	_frequency_field.set_value_silent(config.terrain_frequency)
	_view_distance_field.set_value_silent(config.view_distance_voxels)


## Renders a status snapshot produced by [method VoxelWorld.get_status].
func set_status(status: Dictionary) -> void:
	if status.is_empty():
		return
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
	])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F3:
				_panel.visible = not _panel.visible
				get_viewport().set_input_as_handled()
			KEY_R:
				_emit_regeneration()
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

	regenerate_requested.emit({
		"world_seed": int(_seed_field.get_value()),
		"terrain_height": float(_height_field.get_value()),
		"terrain_frequency": float(_frequency_field.get_value()),
		"view_distance_voxels": int(_view_distance_field.get_value()),
	})
