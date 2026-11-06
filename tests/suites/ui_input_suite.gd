extends RefCounted

## UI input suite: numerical field editing on touch and mouse.
##
## [b]This suite needs a display server.[/b] Godot does not dispatch GUI input
## to [Control]s in `--headless` mode, so synthetic taps are ignored there and
## the suite would silently prove nothing. The runner skips it in headless mode
## and [code]run_tests.sh[/code] runs the suites with a display when one is
## available (Xvfb is enough).
##
## What is checked is the behaviour behind milestone M0.2: a raw
## [InputEventScreenTouch] - the event Android delivers when
## `input_devices/pointing/emulate_mouse_from_touch` is off - must focus the
## numeric field, the field must refuse invalid, empty or out-of-range text, and
## the panel must never hand a half-typed value to the world configuration.
##
## Note on honesty: these are synthetic events in a desktop build. They verify
## the code path Android depends on, but they are [i]not[/i] an Android device
## test and must never be reported as one.

const TestSupport = preload("res://tests/test_support.gd")

var _report
var _tree: SceneTree


static func run(report, tree: SceneTree) -> void:
	var suite := new()
	suite._report = report
	suite._tree = tree

	# The runner calls this from its own _ready(), while the root viewport is
	# still setting up its children; adding nodes to it would fail.
	await tree.process_frame

	print("")
	print("-- android input fix: numerical fields -------------------")
	await suite._test_touch_focuses_the_field()
	await suite._test_keyboard_types()
	await suite._test_mouse_still_works()
	await suite._test_valid_entry_commits()
	await suite._test_empty_and_invalid_input_are_rejected()
	await suite._test_range_enforcement()
	await suite._test_decimal_handling()
	await suite._test_step_buttons()
	await suite._test_focus_loss_commits()
	await suite._test_panel_bridge()


# --------------------------------------------------------------- field harness

func _make_field(minimum: float, maximum: float, step: float, whole: bool) -> NumericField:
	var field := NumericField.new()
	field.minimum = minimum
	field.maximum = maximum
	field.step = step
	field.whole_numbers_only = whole
	# A Control needs to be in the tree with a size before taps can hit it.
	var host := Control.new()
	host.size = Vector2(400, 400)
	_tree.root.add_child(host)
	host.add_child(field)
	field.position = Vector2(40, 40)
	field.size = Vector2(180, 31)
	return field


func _dispose(field: NumericField) -> void:
	var host := field.get_parent()
	host.queue_free()


## Sends what Android sends: a raw screen touch, no mouse emulation.
func _tap(control: Control) -> void:
	var centre := control.get_global_rect().get_center()
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = centre
	_tree.root.push_input(press)

	var release := InputEventScreenTouch.new()
	release.index = 0
	release.pressed = false
	release.position = centre
	_tree.root.push_input(release)
	await _tree.process_frame


func _click(control: Control) -> void:
	var centre := control.get_global_rect().get_center()
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = centre
		event.global_position = centre
		_tree.root.push_input(event)
	await _tree.process_frame


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await _tree.process_frame


# --------------------------------------------------------------------- checks

func _test_touch_focuses_the_field() -> void:
	var field := _make_field(0.0, 1000.0, 1.0, true)
	await _wait_frames(1)

	await _tap(field.get_line_edit())
	_report.check(
			"tapping the field with a raw touch focuses its text entry",
			field.get_line_edit().has_focus())

	var other := _make_field(0.0, 1000.0, 1.0, true)
	await _wait_frames(1)
	await _tap(other.get_line_edit())
	_report.check(
			"focus moves to the field that was tapped last",
			other.get_line_edit().has_focus() and not field.get_line_edit().has_focus())

	_dispose(field)
	_dispose(other)


func _test_keyboard_types() -> void:
	var integer_field := _make_field(-1000.0, 1000.0, 1.0, true)
	var decimal_field := _make_field(0.0001, 0.05, 0.0001, false)
	await _wait_frames(1)

	_report.check_equal(
			"integer field asks for a whole-number keyboard",
			integer_field.get_line_edit().virtual_keyboard_type,
			LineEdit.KEYBOARD_TYPE_NUMBER)
	_report.check_equal(
			"decimal field asks for a decimal keyboard",
			decimal_field.get_line_edit().virtual_keyboard_type,
			LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL)
	_report.check(
			"virtual keyboard is enabled on the field",
			integer_field.get_line_edit().virtual_keyboard_enabled)

	_dispose(integer_field)
	_dispose(decimal_field)


func _test_mouse_still_works() -> void:
	var field := _make_field(0.0, 1000.0, 1.0, true)
	await _wait_frames(1)
	await _click(field.get_line_edit())
	_report.check(
			"desktop mouse click still focuses the field",
			field.get_line_edit().has_focus())
	_dispose(field)


func _test_valid_entry_commits() -> void:
	var field := _make_field(0.0, 100000.0, 1.0, true)
	await _wait_frames(1)
	var commits: Array[float] = []
	field.value_committed.connect(func(value: float) -> void: commits.append(value))

	field.get_line_edit().text = "4242"
	var returned: float = field.commit_pending()
	_report.check_equal("typed integer is accepted", returned, 4242.0)
	_report.check_equal("committed value is readable through get_value", field.get_value(), 4242.0)
	_report.check_equal("accepted value emits exactly one signal", commits.size(), 1)

	commits.clear()
	field.commit_pending()
	_report.check_equal("re-committing the same text emits nothing", commits.size(), 0)

	_dispose(field)


func _test_empty_and_invalid_input_are_rejected() -> void:
	var field := _make_field(0.0, 1000.0, 1.0, true)
	await _wait_frames(1)
	field.set_value_silent(123.0)
	var commits: Array[float] = []
	field.value_committed.connect(func(value: float) -> void: commits.append(value))

	for bad_text in ["", "   ", "abc", "12x", "1.2.3", "--5"]:
		field.get_line_edit().text = bad_text
		var returned: float = field.commit_pending()
		_report.check(
				"rejects %s and keeps the previous value" % JSON.stringify(bad_text),
				returned == 123.0 and field.get_value() == 123.0)
	_report.check_equal("rejected input never emits a value", commits.size(), 0)
	_report.check_equal(
			"the text entry is restored to the last good value",
			field.get_line_edit().text, "123")

	_dispose(field)


func _test_range_enforcement() -> void:
	var field := _make_field(0.0, 500.0, 1.0, true)
	await _wait_frames(1)

	field.get_line_edit().text = "-40"
	_report.check_equal("value below the minimum is clamped", field.commit_pending(), 0.0)

	field.get_line_edit().text = "9999"
	_report.check_equal("value above the maximum is clamped", field.commit_pending(), 500.0)

	field.get_line_edit().text = "+7"
	_report.check_equal("an explicit plus sign is accepted", field.commit_pending(), 7.0)

	_dispose(field)


func _test_decimal_handling() -> void:
	var integer_field := _make_field(0.0, 1000.0, 1.0, true)
	var decimal_field := _make_field(0.0001, 0.05, 0.0001, false)
	await _wait_frames(1)

	integer_field.set_value_silent(26.0)
	integer_field.get_line_edit().text = "26.7"
	_report.check_equal(
			"a decimal typed into a whole-number field is rejected",
			integer_field.commit_pending(), 26.0)

	decimal_field.set_value_silent(0.008)
	decimal_field.get_line_edit().text = "0.0125"
	_report.check_equal(
			"a decimal typed into the frequency field is accepted",
			decimal_field.commit_pending(), 0.0125)

	decimal_field.get_line_edit().text = "0,0125"
	_report.check_equal(
			"a locale decimal comma is accepted",
			decimal_field.commit_pending(), 0.0125)

	decimal_field.get_line_edit().text = "1.5"
	_report.check_equal("frequency above its maximum is clamped", decimal_field.commit_pending(), 0.05)

	_dispose(integer_field)
	_dispose(decimal_field)


func _test_step_buttons() -> void:
	var field := _make_field(32.0, 128.0, 16.0, true)
	await _wait_frames(1)
	field.set_value_silent(64.0)
	await _wait_frames(1)

	var buttons: Array[Button] = []
	for child in field.get_children():
		if child is Button:
			buttons.append(child)
	_report.check_equal("the field exposes two step buttons", buttons.size(), 2)

	# Step buttons are ordinary BaseButtons, so a raw touch works on them.
	await _tap(buttons[1])
	_report.check_equal("touch on '+' increments by one step", field.get_value(), 80.0)
	await _tap(buttons[0])
	await _tap(buttons[0])
	_report.check_equal("touch on '-' decrements by one step", field.get_value(), 48.0)

	field.set_value_silent(128.0)
	await _tap(buttons[1])
	_report.check_equal("increment stops at the maximum", field.get_value(), 128.0)

	field.set_value_silent(32.0)
	await _tap(buttons[0])
	_report.check_equal("decrement stops at the minimum", field.get_value(), 32.0)

	_dispose(field)


func _test_focus_loss_commits() -> void:
	var field := _make_field(0.0, 1000.0, 1.0, true)
	await _wait_frames(1)
	field.set_value_silent(11.0)
	await _wait_frames(1)

	await _tap(field.get_line_edit())
	_report.check("field has focus before the edit", field.get_line_edit().has_focus())

	field.get_line_edit().text = "77"
	field.get_line_edit().release_focus()
	await _wait_frames(1)
	_report.check_equal("losing focus commits the typed value", field.get_value(), 77.0)

	await _tap(field.get_line_edit())
	field.get_line_edit().text = "zzz"
	field.get_line_edit().release_focus()
	await _wait_frames(1)
	_report.check_equal("losing focus with invalid text keeps the old value", field.get_value(), 77.0)

	_dispose(field)


func _test_panel_bridge() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	_tree.root.add_child(scene)
	await _wait_frames(3)

	var panel: DebugPanel = scene.get_node("DebugLayer/DebugPanel")
	var world: VoxelWorld = scene.get_node("World")
	var requests: Array[Dictionary] = []
	panel.regenerate_requested.connect(
			func(request: Dictionary) -> void: requests.append(request))

	_report.check_equal(
			"the seed field is populated from the world configuration",
			panel.get_node("%SeedField").get_value(), float(world.config.world_seed))

	# Typed but not yet committed when Regenerate is pressed: the typed value
	# must be the one used, so what is on screen and what is generated agree.
	var seed_field: NumericField = panel.get_node("%SeedField")
	seed_field.get_line_edit().text = "246810"
	await _tap(panel.get_node("%RegenerateButton"))
	await _wait_frames(1)

	_report.check(
			"a typed seed is applied when Regenerate is touched",
			requests.size() == 1 and int(requests[0]["world_seed"]) == 246810,
			"requests=%d" % requests.size())

	# Invalid text must not corrupt the configuration.
	requests.clear()
	seed_field.get_line_edit().text = "not a number"
	await _tap(panel.get_node("%RegenerateButton"))
	await _wait_frames(1)
	_report.check(
			"invalid text falls back to the last good seed",
			requests.size() == 1 and int(requests[0]["world_seed"]) == 246810,
			"requests=%d" % requests.size())
	_report.check_equal(
			"the field shows the value that was actually used",
			seed_field.get_line_edit().text, "246810")

	# Random seed still works and stays inside its documented range.
	requests.clear()
	await _tap(panel.get_node("%RandomSeedButton"))
	await _wait_frames(1)
	_report.check("Random Seed still emits a request through touch", requests.size() == 1)
	if requests.size() == 1:
		var random_seed: int = int(requests[0]["world_seed"])
		_report.check(
				"the random seed is within 0..%d" % DebugPanel.RANDOM_SEED_LIMIT,
				random_seed >= 0 and random_seed <= DebugPanel.RANDOM_SEED_LIMIT,
				"seed=%d" % random_seed)
		_report.check_equal("the seed field shows the random seed",
				seed_field.get_line_edit().text, str(random_seed))

	# The other three fields must be reachable and correct too.
	var height_field: NumericField = panel.get_node("%HeightField")
	var frequency_field: NumericField = panel.get_node("%FrequencyField")
	var view_field: NumericField = panel.get_node("%ViewDistanceField")

	requests.clear()
	height_field.get_line_edit().text = "40"
	frequency_field.get_line_edit().text = "0.012"
	view_field.get_line_edit().text = "96"
	await _tap(panel.get_node("%RegenerateButton"))
	await _wait_frames(1)
	_report.check("all four fields commit together on Regenerate", requests.size() == 1)
	if requests.size() == 1:
		_report.check_equal("terrain height reaches the request",
				float(requests[0]["terrain_height"]), 40.0)
		_report.check_equal("terrain frequency reaches the request",
				float(requests[0]["terrain_frequency"]), 0.012)
		_report.check_equal("view distance reaches the request",
				int(requests[0]["view_distance_voxels"]), 96)

	# And the world really rebuilds with them.
	var applied: bool = (
			is_equal_approx(world.config.terrain_height, 40.0)
			and is_equal_approx(world.config.terrain_frequency, 0.012)
			and world.config.view_distance_voxels == 96)
	_report.check("the world configuration received the new values", applied,
			"height=%s frequency=%s view=%s" % [
				world.config.terrain_height,
				world.config.terrain_frequency,
				world.config.view_distance_voxels])

	scene.queue_free()
	await _wait_frames(2)
