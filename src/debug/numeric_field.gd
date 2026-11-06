class_name NumericField
extends HBoxContainer

## A numerical input row that works with both a mouse and a raw touch screen.
##
## [b]Why this exists.[/b] Godot's [SpinBox] only inspects [InputEventMouse]
## events in its `gui_input`. With `input_devices/pointing/emulate_mouse_from_touch`
## disabled (this project disables it so the orbit camera does not receive every
## touch twice), Android delivers raw [InputEventScreenTouch] and the SpinBox
## never gains focus — so the field cannot be tapped or edited. The same is true
## of a bare [LineEdit], which has no touch handling either. [Button], by
## contrast, handles touch itself, which is why the Regenerate button kept
## working on device.
##
## This control therefore gives the [LineEdit] an explicit touch handler, and
## keeps the platform-neutral editing behaviour (mouse, keyboard, validation) in
## one place:
##
## - tapping the text field focuses it and shows the numeric virtual keyboard;
## - Enter/Done commits and dismisses the keyboard;
## - losing focus commits;
## - invalid, empty or out-of-range text never reaches the caller;
## - step buttons provide increment/decrement on both desktop and touch.
##
## It is a thin composition of stock Godot controls, not a UI framework.

## Emitted only when a new, valid value has been accepted.
signal value_committed(new_value: float)

## Lowest value accepted. Input below this is clamped.
@export var minimum: float = 0.0
## Highest value accepted. Input above this is clamped.
@export var maximum: float = 100.0
## Amount added or removed by the step buttons.
@export var step: float = 1.0
## When true, only whole numbers are accepted and a decimal point is rejected.
@export var whole_numbers_only: bool = true
## Width reserved for the two step buttons.
@export var button_width: float = 34.0

var _line_edit: LineEdit
var _step_button: Button
var _committed_value: float = 0.0
var _has_value := false


func _ready() -> void:
	_build()
	if not _has_value:
		# No external value was pushed before the node was ready: start at the
		# nearest valid value to the default, so the widget never shows an
		# out-of-range number.
		set_value_silent(clampf(0.0, minimum, maximum))


## Current committed value. Never reflects text that is still being typed.
func get_value() -> float:
	return _committed_value


## Sets the field without emitting [signal value_committed].
## Used when something else owns the value (initial config load, random seed).
func set_value_silent(new_value: float) -> void:
	_committed_value = _normalize(new_value)
	_has_value = true
	if _line_edit != null:
		_line_edit.text = _format(_committed_value)


## Applies whatever is currently typed, if it is valid, and returns the value in
## effect afterwards. Invalid text is discarded and the previous value is
## restored, so a half-typed value can never be used by the caller.
func commit_pending() -> float:
	if _line_edit == null:
		return _committed_value
	var typed: Variant = _parse(_line_edit.text)
	if typed == null:
		# Invalid or empty: put the last good value back.
		_line_edit.text = _format(_committed_value)
		return _committed_value

	var normalized: float = _normalize(float(typed))
	var changed := not is_equal_approx(normalized, _committed_value)
	_committed_value = normalized
	_line_edit.text = _format(normalized)
	if changed:
		value_committed.emit(normalized)
	return _committed_value


## Gives the text field focus the way a mouse click would, including the
## virtual keyboard. Used by tests and by touch input.
func focus_line_edit() -> void:
	if _line_edit == null:
		return
	_line_edit.grab_focus()
	_line_edit.select_all()
	_show_virtual_keyboard()


func get_line_edit() -> LineEdit:
	return _line_edit


## Asks the platform keyboard to appear.
##
## [method LineEdit.grab_focus] normally shows it, but only while the field is
## not already editing — after the user dismisses the keyboard with the system
## back gesture the field still holds focus, so a second tap would otherwise
## look like it did nothing. Asking again on every tap keeps the field alive.
func _show_virtual_keyboard() -> void:
	if _line_edit == null or not _line_edit.virtual_keyboard_enabled:
		return
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		# Desktop: there is no on-screen keyboard to show.
		return
	# DisplayServer and LineEdit each declare their own VirtualKeyboardType
	# enum, so the value has to come from the DisplayServer namespace here.
	var keyboard_type: DisplayServer.VirtualKeyboardType = (
			DisplayServer.KEYBOARD_TYPE_NUMBER if whole_numbers_only
			else DisplayServer.KEYBOARD_TYPE_NUMBER_DECIMAL)
	DisplayServer.virtual_keyboard_show(
			_line_edit.text,
			_line_edit.get_global_rect(),
			keyboard_type,
			_line_edit.max_length,
			_line_edit.caret_column,
			_line_edit.caret_column)


# ------------------------------------------------------------------ internals

func _build() -> void:
	_line_edit = LineEdit.new()
	_line_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_line_edit.custom_minimum_size = Vector2(84.0, 0.0)
	_line_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_line_edit.select_all_on_focus = true
	_line_edit.virtual_keyboard_enabled = true
	_line_edit.virtual_keyboard_show_on_focus = true
	_line_edit.virtual_keyboard_type = (
			LineEdit.KEYBOARD_TYPE_NUMBER if whole_numbers_only
			else LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	)
	_line_edit.text_submitted.connect(_on_text_submitted)
	_line_edit.focus_exited.connect(_on_focus_exited)
	# The missing link: LineEdit ignores raw InputEventScreenTouch, so focus it
	# ourselves when Android taps it.
	_line_edit.gui_input.connect(_on_line_edit_gui_input)
	add_child(_line_edit)

	_step_button = _make_step_button("-", -1.0)
	_step_button = _make_step_button("+", 1.0)

	_line_edit.text = _format(_committed_value)


func _make_step_button(label: String, direction: float) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(button_width, 0.0)
	# Do not steal focus from the text field, otherwise tapping "+" on Android
	# would close the keyboard the user just opened.
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_step_pressed.bind(direction))
	add_child(button)
	return button


func _on_step_pressed(direction: float) -> void:
	# Commit any typed text first so stepping starts from what is on screen.
	commit_pending()
	var stepped := _committed_value + step * direction
	var normalized := _normalize(stepped)
	if is_equal_approx(normalized, _committed_value):
		return
	_committed_value = normalized
	_line_edit.text = _format(normalized)
	value_committed.emit(normalized)


func _on_line_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		focus_line_edit()
		_line_edit.accept_event()


func _on_text_submitted(_new_text: String) -> void:
	commit_pending()
	# Dismiss the virtual keyboard: Enter/Done means "finished editing".
	_line_edit.release_focus()


func _on_focus_exited() -> void:
	commit_pending()


## Returns a valid number parsed from [param text], or null when the text is
## empty, malformed, or the wrong kind for this field.
func _parse(text: String) -> Variant:
	# Some Android numeric keyboards emit a locale decimal comma.
	var cleaned := text.strip_edges().replace(",", ".")
	if cleaned.is_empty():
		return null
	if whole_numbers_only:
		if not cleaned.is_valid_int():
			return null
		return float(cleaned.to_int())
	if not cleaned.is_valid_float():
		return null
	return cleaned.to_float()


func _normalize(new_value: float) -> float:
	var clamped := clampf(new_value, minimum, maximum)
	return roundf(clamped) if whole_numbers_only else clamped


func _format(new_value: float) -> String:
	if whole_numbers_only:
		return str(int(roundf(new_value)))
	var text := String.num(new_value, 6)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text
