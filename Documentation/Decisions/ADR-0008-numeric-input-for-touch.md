# ADR-0008 — Edit numbers with a purpose-built field, not `SpinBox`

**Status:** Accepted
**Date:** 2026-11-06

## Context

The M0.1 debug overlay used four `SpinBox` nodes (world seed, terrain height,
terrain frequency, view distance). They work with a mouse and keyboard, but on
the Android device none of them could be tapped or edited: no text cursor, no
virtual keyboard, no way to enter a value.

The cause is in the engine, not in this project. `SpinBox::gui_input()` in Godot
4.7.2 handles only `InputEventMouse*`; on a left press it calls
`line_edit->grab_focus(true)`. It never looks at `InputEventScreenTouch`.
`LineEdit` has no touch handling either. The project runs with
`input_devices/pointing/emulate_mouse_from_touch = false` — deliberately, so the
orbit camera does not receive every touch twice — so Android delivers raw
`InputEventScreenTouch` events, `SpinBox` ignores them, the inner `LineEdit`
never gains focus, and the platform keyboard is never requested. `BaseButton`
*does* handle `InputEventScreenTouch`, which is exactly why the Regenerate and
Random seed buttons kept working on the same device while the four fields did
not.

The engine class cannot be patched from GDScript, and the custom-module engine
build is excluded by ADR-0001.

## Decision

Compose a small control, `NumericField` (`src/debug/numeric_field.gd`), from
stock Godot nodes instead of using `SpinBox`:

```
HBoxContainer
├── LineEdit   numeric virtual keyboard, validation, commit on Enter / focus loss
├── Button "-" step down (focus_mode = FOCUS_NONE)
└── Button "+" step up
```

The only Android-specific code is one signal handler: on `InputEventScreenTouch`
with `pressed == true` the field grabs focus for its `LineEdit` and asks the
platform for the keyboard. Everything else is ordinary control composition.

Behaviour that the panel relies on:

- `set_value_silent(v)` updates the display without emitting, for values owned
  elsewhere (initial config load, random seed).
- `commit_pending()` parses, validates, clamps and returns the value in effect.
  Invalid or empty text is discarded, the last good value is restored, and
  nothing is emitted — so a half-typed value can never reach `WorldConfig`.
- `value_committed` fires only for accepted values.
- The virtual keyboard type is `KEYBOARD_TYPE_NUMBER` for whole-number fields
  and `KEYBOARD_TYPE_NUMBER_DECIMAL` for the frequency field.

## Consequences

- Tapping a field on a touch device can now focus it and open the correct
  keyboard; desktop mouse, typing, arrows-free stepping and `R`/`F3` shortcuts
  are unchanged in behaviour.
- `SpinBox` is gone from the panel. Anything relying on `%SeedSpin` and friends
  must use `%SeedField` and `get_value()`; nothing outside the panel did.
- The panel now owns input policy (ranges, integer/decimal, commit timing)
  rather than inheriting it from a stock widget. That policy is covered by
  `tests/suites/ui_input_suite.gd`.
- The field is a debug-overlay component, not a general form framework. Growing
  it into one would need a real design, not incremental patching.
- **This decision is not evidence that the fix works on Android.** No Android
  device or SDK is available in this environment; the touch path is exercised
  with synthetic `InputEventScreenTouch` events only. Device verification is
  still owed.
