# M0.2 — Android Debug Panel Numerical Input Fix

Date: 2026-11-06
Status: implemented, tested on Linux, awaiting review
Scope: debug panel input only. No terrain, noise, streaming or voxel-pipeline
change; no new dependency; M1 not started.

---

## 1. Problem

On the Android device the four numerical fields in the debug overlay — **world
seed**, **terrain height**, **terrain frequency**, **view distance** — could not
be used at all:

- tapping the field did nothing: no cursor, no selection highlight;
- no virtual keyboard appeared, so no value could be typed;
- the fields therefore showed their current values but could not change them.

The same overlay worked normally on desktop. The two buttons next to the fields
(**Regenerate**, **Random seed**) and the orbit camera worked on the same
device, which mattered later: it proved touch input itself was arriving.

---

## 2. Root cause

Not a project bug in the usual sense, and not a wiring mistake. It is a gap in
the stock widget, visible in the Godot 4.7.2 sources.

**2.1 The project receives raw touch events, not emulated mouse events.**
`project.godot` sets `input_devices/pointing/emulate_mouse_from_touch = false`.
This was a deliberate M0.1 choice: with emulation on, every touch is also
delivered as a mouse event, and the orbit camera would act on the same gesture
twice. The consequence is that Android delivers `InputEventScreenTouch`
(`InputEventScreenDrag` while moving), and never fabricates
`InputEventMouseButton` for a finger.

**2.2 The viewport delivers that touch event correctly.**
`scene/main/viewport.cpp` routes `InputEventScreenTouch` through
`gui_find_control()` and delivers it, unmodified, to the `Control` under the
finger. The event reaches the `SpinBox` — this is not a routing problem.

**2.3 `SpinBox` ignores touch.** In `scene/gui/spin_box.cpp`, `SpinBox::gui_input()`
inspects only `InputEventMouseButton` / `InputEventMouseMotion`. On a left press
it does `line_edit->grab_focus(true)`, which is what opens the keyboard on
desktop. There is no `InputEventScreenTouch` branch, so a finger press falls
through and nothing happens: no focus, no keyboard.

**2.4 `LineEdit` has no touch handling either.** `scene/gui/line_edit.cpp`
contains no `InputEventScreen*` code at all. It shows the on-screen keyboard only
from `_edit()`, which runs when the field gains focus. Since focus is only ever
granted by the `SpinBox` mouse branch, the keyboard is never requested.

**2.5 Why the buttons still worked.** `scene/gui/base_button.cpp` *does* handle
`InputEventScreenTouch` (it presses on touch-down inside its rect and releases on
touch-up). `Button` inherits that, so Regenerate and Random seed worked on the
device while the fields next to them did not. The camera worked because
`OrbitCamera` reads `InputEventScreenTouch`/`InputEventScreenDrag` directly.

**Summary:** with mouse emulation disabled, `SpinBox` is not touch-operable in
Godot 4.7.2. The fields had to stop being `SpinBox`.

### 2.6 How this was established

- By reading the 4.7.2 sources listed above (fetched from the `4.7.2-stable` tag),
  not by guessing.
- By reproducing it: a probe scene instantiated `main.tscn` in a windowed run
  (Xvfb) and pushed synthetic input at the controls' global rects.

  | Event pushed | Control | Result |
  |---|---|---|
  | `InputEventScreenTouch` | `RegenerateButton` | `pressed` fired ✔ |
  | `InputEventMouseButton` | `RegenerateButton` | `pressed` fired ✔ |
  | `InputEventScreenTouch` | `SeedSpin` text area | `get_line_edit().has_focus() == false` ✘ |

  That reproduces the device symptom on Linux: touch reaches the control, the
  button acts on it, the spin box does not.
- Note the probe only works in a windowed run. In `--headless` Godot does not
  dispatch GUI input at all, and the same probe reports zero presses for *both*
  mouse and touch — a reminder that a headless UI test proves nothing.

---

## 3. Files modified

| File | Status | Change |
|---|---|---|
| `src/debug/numeric_field.gd` | **new** (225 lines) | `NumericField`, a `HBoxContainer` of `LineEdit` + `-`/`+` buttons with touch focus, validation and commit rules |
| `scenes/main.tscn` | modified | the four `SpinBox` nodes replaced by four `NumericField` nodes; ranges and step sizes moved onto them; one new `ext_resource` |
| `src/debug/debug_panel.gd` | modified | reads `%SeedField`/`%HeightField`/`%FrequencyField`/`%ViewDistanceField`; commits pending edits before emitting; uses `set_value_silent()` / `get_value()` |
| `tests/suites/ui_input_suite.gd` | **new** | 45 self-checking UI input tests |
| `tests/test_runner.gd` | modified | registers the `ui` suite; skips it loudly when the display server is `headless` |
| `tests/run_tests.sh` | modified | runs windowed when a display exists, headless otherwise; reports which mode |
| `Documentation/Decisions/ADR-0008-numeric-input-for-touch.md` | **new** | the decision and its consequences |
| `Documentation/Milestones/M00_02_ANDROID_INPUT_FIX.md` | **new** | this document |
| `Documentation/PROJECT_CONTINUATION.md` | modified | status, file list, test counts, next steps |

Nothing else was touched: no terrain, noise, generator, streaming, camera or
palette code changed, and no dependency was added.

---

## 4. Implementation

### 4.1 `NumericField`

```
HBoxContainer
├── LineEdit   (expands)  right-aligned text, numeric virtual keyboard
├── Button "-" (34 px)    step down, focus_mode = FOCUS_NONE
└── Button "+" (34 px)    step up,   focus_mode = FOCUS_NONE
```

Configurable per instance: `minimum`, `maximum`, `step`, `whole_numbers_only`.

The touch fix is a single handler:

```gdscript
func _on_line_edit_gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch and event.pressed:
        focus_line_edit()
        _line_edit.accept_event()
```

`focus_line_edit()` grabs focus, selects the whole value (so typing replaces it,
matching the old `select_all_on_focus` behaviour) and asks for the keyboard.
It asks explicitly through `DisplayServer.virtual_keyboard_show()` rather than
relying on focus alone, for two reasons: `LineEdit` defers the keyboard to
mouse-release when `select_all_on_focus` is set, and a finger never produces
that release; and after the user dismisses the keyboard with the system back
gesture the field still holds focus, so without an explicit request a second tap
would silently do nothing.

Step buttons keep `FOCUS_NONE` on purpose: tapping `+` must not take focus away
from the text field and close the keyboard the user just opened.

### 4.2 Values, validation and commit

| Field | Type | Range | Step | Keyboard |
|---|---|---|---|---|
| World seed | integer | −1 000 000 000 … 1 000 000 000 | 1 | number |
| Terrain height | integer (voxels) | 0 … 128 | 1 | number |
| Terrain frequency | decimal | 0.0001 … 0.05 | 0.0001 | number (decimal) |
| View distance | integer | 32 … 512 | 16 | number |

Ranges are the ones the `SpinBox` nodes already enforced; no new limit was
invented. Height stays whole-numbered, as before (voxels are integers).

Commit happens on three occasions only: **Enter/Done**, **focus loss**, and
**before the panel emits a regeneration request**. There is no commit per
keystroke, so a half-typed value is never applied.

- Empty or whitespace-only text → previous value restored, nothing emitted.
- Malformed text (`abc`, `12x`, `1.2.3`, `--5`) → previous value restored,
  nothing emitted.
- A decimal point in a whole-number field → rejected, previous value restored.
- A decimal comma (some Android numeric keyboards emit `,`) → accepted as a
  decimal point.
- Out of range → clamped to the field's own limits, never rejected silently.
- Enter/Done also releases focus, which dismisses the keyboard.

`DebugPanel._emit_regeneration()` calls `commit_pending()` on all four fields
*before* reading them, so "type a seed, then press Regenerate" uses what is on
screen — and invalid text falls back to the last good value instead of
corrupting `WorldConfig`.

### 4.3 What did not change

`WorldConfig`, `VoxelWorld`, `MainScene._on_regenerate_requested`, the rebuild
path, the `R` / `F3` shortcuts, `configure_from_config()`, the status block and
the panel layout are untouched. The panel still emits the same
`regenerate_requested` dictionary with the same four keys and types.

---

## 5. Desktop results (verified here, Linux x86_64, Xvfb + llvmpipe)

`./tests/run_tests.sh` with `DISPLAY=:99`:

```
test mode: windowed (display: :99)
# suite: core   RESULT: PASS  (17 checks)
# suite: voxel  RESULT: PASS  (24 checks)
# suite: ui     RESULT: PASS  (45 checks)
# ALL SUITES PASSED
```

The 45 UI checks cover, per field:

- a raw `InputEventScreenTouch` focuses the text entry, and focus moves to the
  field tapped last (the regression itself);
- the whole-number field requests `KEYBOARD_TYPE_NUMBER`, the frequency field
  `KEYBOARD_TYPE_NUMBER_DECIMAL`, and the keyboard is enabled;
- a mouse click still focuses the field (desktop behaviour preserved);
- a valid value is accepted, is readable, and emits exactly once; re-committing
  the same text emits nothing;
- empty, whitespace, `abc`, `12x`, `1.2.3`, `--5` are all rejected, the previous
  value survives, nothing is emitted, and the text snaps back;
- values below the minimum and above the maximum are clamped; `+7` is accepted;
- a decimal in a whole-number field is rejected; a decimal in the frequency
  field is accepted; a decimal comma is accepted;
- `+`/`-` step by exactly one step under touch and stop at the limits;
- focus loss commits valid text and keeps the old value for invalid text;
- through the panel: the fields load from the world configuration; a typed seed
  is applied when Regenerate is touched; invalid text falls back to the last
  good seed and the field shows the value that was actually used; Random seed
  emits a request inside `0…100000` and updates the display; all four fields
  commit together and reach `world.config`.

Screenshot: `Documentation/Milestones/screenshots/m00_02_debug_panel.png`
(seed 1337) shows the new rows rendering as before, with the two step buttons.

Headless CI keeps working: `./tests/run_tests.sh` without a display runs
`core` + `voxel` and prints
`SKIP  UI input suite needs a display server (run without --headless)` rather
than reporting a vacuous pass.

---

## 6. Android results

### 6.1 Confirmed on a physical Android device

Corrected on 2026-11-07. The project owner ran the project from the Godot Editor
on an Android device and confirmed, specifically for this fix:

- all four numerical fields — world seed, terrain height, terrain frequency,
  view distance — accept touch input;
- each field opens the keyboard and accepts a custom numerical value;
- the values reach the world: Regenerate applies them, and changing the seed or
  Random seed produces different terrain.

That is the acceptance test this document previously listed as outstanding, and
it passed.

### 6.2 Still not confirmed

The device run was an **Editor run (debug)**, not an exported release build:

- a separately exported release APK has not been run on the device;
- release-build extension loading is therefore still unverified;
- long-duration and thermal behaviour are unverified.

See `M00_02_ANDROID_VALIDATION.md` §3.4 and §7.2 for the exact status of the
exported APK.

## 7. Limitations

1. **Release-build verification is outstanding.** The Editor run on device
   passed (§6.1); an exported release APK has not been run (§6.2).
2. **Synthetic input only.** The 45 checks push `InputEventScreenTouch` into a
   desktop viewport. They exercise the handler, not the platform keyboard, the
   IME, or the back-gesture dismissal.
3. **Height is whole-numbered.** Preserved from the old `SpinBox` behaviour;
   `WorldConfig.terrain_height` is a float, so fractional heights are possible in
   data but not enterable in the panel. Deliberate, not an oversight.
4. **Step buttons are 34 px wide** in a debug overlay. Fine with a mouse, and
   reachable with a fingertip, but small by mobile touch-target standards. The
   text field itself is the primary input.
5. **The panel is still a debug overlay.** `NumericField` is a composition of
   stock controls aimed at four fields, not a form framework.
6. **`SpinBox` is gone from this panel.** If a future screen needs a spin box,
   this fix does not make stock `SpinBox` touch-operable; the same replacement
   applies.
7. **Pre-existing log noise, unrelated to this change.** Rebuilding the world
   while streaming is still busy intermittently prints
   `Condition "!is_inside_tree()" is true` from `node_3d.cpp` inside Voxel Tools'
   teardown. It appears with and without this milestone's changes — the
   untouched `voxel` suite reproduces it on some runs (0 on three runs, 72 on
   another) — and no test result is affected. It is recorded here so it is not
   mistaken for a regression of M0.2.
