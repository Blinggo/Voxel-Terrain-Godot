# M0.2 — Android Validation, Performance and Reliability

Date: 2026-11-07
Status: implemented and tested on Linux; Android release APK exported and
verified but **not installed or run**. Awaiting review.
Supersedes nothing: `M00_02_ANDROID_INPUT_FIX.md` remains the record of the
numerical-input fix, which is a separate piece of work inside the same milestone.

---

## 1. Milestone objectives

M0.2 has four work areas, all completed here:

| Area | Objective | Outcome |
|---|---|---|
| A | Android release validation for an ARM64 build | Export preset written, three real configuration faults found and fixed, **release APK exported, signed and verified**. Not run: no device. |
| B | Performance and memory instrumentation | `PerformanceSampler` + debug overlay readout, using only measurements that exist |
| C | Generation reliability | Screenshot harness exit codes fixed; palette configuration snapshot introduced |
| D/E | Regression testing and documentation | 151 automated checks pass; previous Android claims corrected |

Terrain mathematics, generation architecture, and all M0.1 systems are untouched.

---

## 2. Work completed

1. **Android export configuration audited** against the real exporter, not by
   inspection alone: the first export attempt was made in order to find out.
2. **Three configuration faults found and fixed** (§3). Two of them would have
   blocked or degraded the release build; one was a silent wrong-orientation bug.
3. **ARM64 release APK exported and verified** (§3.4): signature, architecture,
   packaged extension library, script contents, requested permissions.
4. **`PerformanceSampler`** added, plus an overlay readout with a toggle (§4).
5. **Screenshot harness hardened**: five distinct non-zero exit codes, directory
   creation, on-disk verification, render watchdog, headless fast-fail; and
   `run_tests.sh` now propagates those failures (§5.1).
6. **Palette snapshot** introduced so worker threads never read the editable
   resource (§5.2), with tests that prove both stability *and* that a rebuild
   still picks edits up.
7. **Two new test suites** (24 + 41 checks) and a corrected documentation set (§6).

---

## 3. Android configuration

### 3.1 What the project had

| Item | State found | Verdict |
|---|---|---|
| Export preset | **absent** | created (§3.2) |
| Renderer | `mobile` (`renderer/rendering_method="mobile"`) | correct for the target |
| Android extension binary | deleted in M0.2 pre-work per earlier instruction | restored into a **staging copy** only; the trimmed project is unchanged |
| Extension entry | `voxel.gdextension`, `compatibility_minimum = 4.4.1` | correct; verified packaged into the APK |
| Permissions | none requested | correct — nothing added |
| ETC2/ASTC import | **disabled** | fixed (§3.2) |
| Orientation | `window/handheld/orientation=1` (**portrait**) with a comment claiming landscape | fixed (§3.3) |
| Export templates | absent | installed 4.7.2.stable for this validation |

### 3.2 Export preset

`export_presets.cfg` (new, kept in the project):

- platform `Android`, name `Android ARM64`, release export;
- `architectures/arm64-v8a=true`, everything else `false` — one ABI only;
- `package/unique_name="io.arena.proceduralworld"`, `package/name="Procedural World"`;
- `version/code=1`, `version/name="0.2.0"`;
- `exclude_filter="tests/*"` so test scenes never ship;
- `gradle_build/use_gradle_build=false` — the prebuilt template is used, so no
  Gradle/Android project is required to produce an APK;
- `screen/immersive_mode=true`; no `permissions/*` entries are enabled.

A required project setting was missing. The first export was refused with:

```
ETC2/ASTC texture compression is required for Android export.
```

Fixed by adding `rendering/textures/vram_compression/import_etc2_astc=true` to
`project.godot`. It only adds compressed texture variants at import time; the
project has no textures yet, and nothing about terrain generation or desktop
rendering changes.

### 3.3 Orientation bug found during validation

`project.godot` carried this, under a comment saying the project is landscape:

```
window/handheld/orientation=1
```

`DisplayServer.SCREEN_LANDSCAPE = 0`, `SCREEN_PORTRAIT = 1` (checked against the
running engine, not from memory). So the value was portrait, contradicting its
own comment, and the first APK was portrait-locked — confirmed from the built
manifest:

```
uses-implied-feature: name='android.hardware.screen.portrait'
```

Changed to `0` (landscape). The re-exported APK now reports
`android.hardware.screen.landscape`. **This is a behaviour change on device and
should be confirmed during the manual test** — it is the only intentional change
to how the app presents itself.

### 3.4 Export result

Built with Godot 4.7.2, Android SDK build-tools 34.0.0, platform android-34,
JDK 21, and a local throwaway keystore:

```
artifacts/android/procedural-world-arm64.apk   35,933,509 bytes
sha256 edeca52406bfa9eb2580d96d9d94f639c573a901015abc8e181c44053022ace3
```

Verified, not assumed:

| Check | Method | Result |
|---|---|---|
| Signature | `apksigner verify --verbose` | **Verifies** (v2 and v3 schemes) |
| Package / version | `aapt2 dump badging` | `io.arena.proceduralworld`, code 1, name 0.2.0 |
| SDK levels | `aapt2 dump badging` | minSdk 24, targetSdk 36 |
| ABI | `aapt2` + APK listing | `native-code: 'arm64-v8a'` only |
| Voxel Tools in build | APK listing | `lib/arm64-v8a/libvoxel.android.template_release.arm64.so` (7.3 MB) |
| Engine | APK listing | `lib/arm64-v8a/libgodot_android.so` (release template) |
| Project code | APK listing | `.gdc` compiled scripts incl. `performance_sampler.gdc`, `scenes/main.tscn.remap` |
| Tests excluded | APK listing | 0 entries under `assets/tests/` |
| Permissions | `aapt2 dump badging` | **none requested** |
| Orientation | manifest | landscape |

**Not verified: that it runs.** There is no Android device and no emulator with
KVM in this environment, so the APK has never been installed. Everything above
is static verification of the artefact. See §7 and §9.

**Where the toolchain lives.** The export was produced with a toolchain installed
entirely outside the project: Godot 4.7.2, the 4.7.2 export templates, the Android
SDK (build-tools 34.0.0, platform-34) and a throwaway keystore all sat in
temporary/cache directories. A first attempt installed the Android SDK inside the
project's parent directory; at 9,650 files and 126 MB it pushed the workspace over
its snapshot budget and three artefacts failed to save. Nothing toolchain-related
is part of the project tree now — only the finished APK. Rebuilding needs a local
toolchain, but the project itself never does.

The Android extension binaries were restored in a staging copy so the delivered
project keeps the trimmed, Linux-only `addons/` from ADR-0006. To rebuild
locally, restore the arm64 binary first:

```
unzip GodotVoxelExtension.zip 'addons/zylann.voxel/bin/libvoxel.android.*' -d .
```

---

## 4. Performance instrumentation

### 4.1 Design

`src/debug/performance_sampler.gd` — a `RefCounted`, not a node and not a
singleton (ADR-0007). The debug panel owns one. Nothing in `src/core/`,
`src/voxel/` or `src/world/` references it, so it can be deleted with the panel.

Three independent measurements:

1. **Frame timing** — every frame, a running window of 1 s accumulates frames,
   total frame time and maximum frame time; on window close it computes fps,
   average frame time and worst frame time. Sampling every frame is what makes
   the maximum meaningful; reporting happens a few times per second.
2. **Godot memory** — `Performance.MEMORY_STATIC`, `MEMORY_STATIC_MAX`,
   `OBJECT_COUNT`, `OBJECT_NODE_COUNT`, `OBJECT_RESOURCE_COUNT`.
3. **Voxel statistics** — whatever `VoxelTerrain.get_statistics()` returns,
   passed through unmodified.
4. **Named sections** — `record_section(name, ms)` with last/average/max per
   name. This is the extension point for climate, hydrology and erosion: a new
   module records its own phase and the overlay displays it without new code.

`VoxelWorld.rebuild()` now also measures its own main-thread duration and
publishes it in `get_status()["last_rebuild_ms"]`.

### 4.2 What Voxel Tools actually exposes

Inspected on the installed extension, not assumed. `VoxelTerrain.get_statistics()`
returns exactly seven keys:

| Key | Meaning | Unit |
|---|---|---|
| `time_detect_required_blocks` | phase duration, previous frame | µs |
| `time_request_blocks_to_load` | phase duration, previous frame | µs |
| `time_process_load_responses` | phase duration, previous frame | µs |
| `time_request_blocks_to_update` | phase duration, previous frame | µs |
| `dropped_block_loads` | cumulative counter | count |
| `dropped_block_meshs` | cumulative counter (upstream spelling) | count |
| `updated_blocks` | dead in 1.7x — never incremented | — |

The microsecond unit is not documented upstream, so it was read out of the
source rather than guessed: these values come from
`ProfilingClock::restart()`, which returns `Time::get_ticks_usec()` deltas
(`util/profiling_clock.h`, v1.7x).

**Not available in this version, and therefore not displayed:**

- number of loaded blocks;
- number of pending blocks;
- per-block generation or meshing timings from the generator script.

The overlay shows `-` rather than inventing them. Streaming readiness continues
to be reported the M0.1 way, by probing `is_area_meshed()` around the viewer,
because `updated_blocks` cannot be used as a progress signal.

### 4.3 Godot memory is not process memory

The overlay's `godot mem` figure is Godot's static allocator total. It excludes
the Android runtime, the Vulkan driver and driver-side allocations. A device's
actual resident set has to be read from outside the game:

```
adb shell dumpsys meminfo io.arena.proceduralworld | head -20
adb shell top -n 1 | grep procedural
```

The two are not interchangeable and the overlay does not pretend otherwise.

### 4.4 Interface

Four lines under the existing status block, 11 px font:

```
fps 58.9  frame 17.0 ms  max 41.2 ms
godot mem 33.1 MB  objects 2104  nodes 47
voxel   update 0.12 ms  load 0.00 ms  detect 0.01 ms
rebuild 21.7 ms
```

- refreshed on the overlay's existing 0.25 s cadence, never per frame;
- **F4** toggles it, or `DebugPanel.set_profiling_enabled(false)` from code;
  disabled means `sample()` returns immediately and the label hides — it is not
  a cosmetic switch;
- the panel keeps `mouse_filter = IGNORE`, so the readout cannot steal touches
  from the camera or the numerical fields;
- the first line reads `fps measuring…` until a full window has closed, instead
  of showing a misleading `0.0 fps`.

Cost when enabled: a handful of float operations per frame plus three
`Performance.get_monitor()` calls per 0.25 s. When disabled: one boolean test per
frame.

---

## 5. Reliability improvements

### 5.1 Screenshot harness

The previous script printed the result of `save_png()` and exited 0 regardless,
and `run_tests.sh` ignored the exit status. Both are corrected.

`tests/capture_screenshot.gd` now exits:

| Code | Condition |
|---|---|
| 0 | PNG written, verified on disk, `SCREENSHOT_OK path=… bytes=… size=…` printed |
| 1 | no rendering device, no viewport texture, empty image, or no frame within 10 s |
| 2 | the main scene came up without a world or camera |
| 3 | output path unusable (empty, non-`.png`, directory not creatable) |
| 4 | `save_png()` returned an error |
| 5 | file missing or empty after a successful save call |

It also creates missing output directories recursively, resolves relative paths
against the project directory, and fails immediately under `--headless` instead
of waiting forever for a frame that can never arrive (previously a CI hang).

`tests/run_tests.sh` now captures the exit status of each capture, requires the
`SCREENSHOT_OK` line, requires a non-empty file, and counts any failure towards
the run's exit code. The final banner distinguishes
`ALL SUITES PASSED` from `N FAILURE(S): suites or screenshots`.

Failure modes were exercised, not just reasoned about:

| Scenario | Observed |
|---|---|
| valid nested path, directory absent | `SCREENSHOT_OK … bytes=718556 size=1280x720`, exit 0, directory created |
| unwritable directory | `SCREENSHOT_FAIL code=4`, exit 4 |
| `--out=x.jpg` | `SCREENSHOT_FAIL code=3`, exit 3 |
| `--headless` | `SCREENSHOT_FAIL code=1 no rendering device`, exit 1 (no hang) |
| full run with unwritable `SHOT_DIR` | script exit 2, two failures counted |
| full run, normal output | both screenshots verified, exit 0 |

### 5.2 Palette configuration snapshot

The generator held a reference to the live `BlockPalette`. Its type ids are
constants, but `soil_depth` and the three colours are exported and editable, so
an inspector edit during generation could produce one block with `soil_depth = 4`
and the next with `soil_depth = 8` — a visible discontinuity that also breaks
same-seed reproducibility.

`BlockPalette.create_snapshot()` returns an independent copy of the configurable
fields (an explicit field-by-field copy, so that a new exported field is a
deliberate decision rather than an accidental inclusion). `VoxelWorld.rebuild()`
takes one snapshot and builds **both** the generator and the blocky library from
it, so the voxels a block is made of and the model used to draw them cannot
disagree. Type ids and material assignments are unchanged: ids remain
`AIR=0, GRASS=1, DIRT=2, STONE=3` and are shared by construction, being constants.

Covered by 24 checks in `tests/suites/reliability_suite.gd`, including a
sensitivity check that would fail if the test were vacuous:

- the snapshot copies every configurable field;
- editing the source afterwards leaves the snapshot untouched;
- blocks generated after such an edit are byte-identical (FNV-1a hash of a
  three-block column);
- the **same edit does change output when the live palette is used**, proving the
  test can detect the difference it is asserting;
- the library built from a snapshot has one model per type id and is unaffected
  by later edits;
- through the world: editing `world.palette` does not change what the running
  generator produces, and `rebuild()` does apply the edit.

---

## 6. Automated testing results

Run on Linux x86_64 with Godot 4.7.2 and Xvfb (software Vulkan). Exact output of
`./tests/run_tests.sh --screenshot`:

```
test mode: windowed (display: :99)
# suite: core          RESULT: PASS  (17 checks)
# suite: voxel         RESULT: PASS  (24 checks)
# suite: reliability   RESULT: PASS  (24 checks)
# suite: perf          RESULT: PASS  (41 checks)
# suite: ui            RESULT: PASS  (45 checks)
verified: /tmp/voxel_screenshots/terrain_seed_1337.png (682784 bytes)
verified: /tmp/voxel_screenshots/terrain_seed_90210.png (792950 bytes)
# ALL SUITES PASSED
```

**151 checks plus two verified screenshots, exit 0.** Coverage relative to the
brief:

| Required | Suite | Status |
|---|---|---|
| Core tests | `core` | 17 pass |
| Voxel integration | `voxel` | 24 pass |
| UI input | `ui` | 45 pass (needs a display; skipped loudly headless) |
| Screenshot capture | `run_tests.sh --screenshot` | 2 captures verified byte size > 0 |
| Palette snapshot behaviour | `reliability` | 24 pass |
| Performance instrumentation | `perf` | 41 pass |
| Existing terrain generation | `voxel` | pass (geometry, height agreement, seams) |
| Same-seed reproducibility | `voxel` | pass |
| Different-seed generation | `voxel` | pass |
| Block boundary continuity | `voxel` | pass (no-seam check) |

Headless behaviour is unchanged for CI: `./tests/run_tests.sh` without a display
runs everything except `ui`, which prints
`SKIP UI input suite needs a display server` and reports
`ALL RUNNABLE SUITES PASSED (1 skipped — needs a display)`.

---

## 7. Android manual testing results

### 7.1 Confirmed by the user (Editor runtime on a physical Android device)

Performed by the project owner, not by this environment:

- project launches;
- Voxel Tools initialises;
- procedural terrain generates and renders;
- touch orbit camera operates smoothly;
- terrain streaming works;
- Regenerate works;
- Random seed produces different terrain;
- restart restores the configured default seed;
- same seed reproduces the same terrain;
- all four numerical fields accept touch input and custom values.

This closes the M0.2 numerical-input item: the fix in
`M00_02_ANDROID_INPUT_FIX.md` is confirmed working on hardware.

### 7.2 Not confirmed

- Installing and launching the exported release APK (§3.4): **never done**.
- Release-build extension loading — the arm64 library is packaged and the
  manifest is correct, but no release build has executed.
- Android process memory under load (the overlay cannot report it; §4.3).
- Sustained runtime, thermal behaviour, battery draw.
- Behaviour on any device other than the one used.

---

## 8. Known limitations

1. **The APK is unrun.** Everything about it is static verification.
2. **No block-count statistics.** Voxel Tools 1.7x does not expose loaded or
   pending block counts, so the overlay cannot show them (§4.2).
3. **Memory readout is Godot-side only** (§4.3).
4. **`updated_blocks` remains useless** and is deliberately not displayed.
5. **Rebuild timing covers the main thread only** — teardown, snapshotting,
   library build, node creation. Streaming afterwards is asynchronous and is not
   included.
6. **Orientation changed** from portrait to landscape (§3.3) — the only
   presentation change in this milestone, and it needs a device check.
7. **The shipped APK is signed with a throwaway keystore.** Installing it over a
   build signed by another key requires uninstalling first. The keystore is not
   part of the project.
8. **Single ABI.** `arm64-v8a` only, by design. 32-bit ARM and x86_64 emulators
   are not built and the extension binaries for them are not shipped.
9. **Profiling is a debug overlay**, not a profiler. It measures frame time, not
   where that time goes.
10. **Pre-existing log noise**: rebuilding while streaming is busy intermittently
    prints `Condition "!is_inside_tree()" is true` from Voxel Tools teardown. It
    reproduces with and without this milestone's changes and affects no result.

---

## 9. Outstanding work

1. **Install and run the exported APK** on the device (§7.2). This is the one
   acceptance test M0.2 cannot perform here. Step-by-step checklist:
   `M00_02_ANDROID_TESTING_CHECKLIST.md`.
2. Confirm orientation is landscape and the panel is still readable and usable
   in landscape at the device's DPI.
3. Record process memory and frame times from the device with
   `adb shell dumpsys meminfo` and the overlay readout, over a 20–30 minute
   session, including a thermal check.
4. Confirm the four numerical fields still behave in a **release** build (they
   were verified in the Editor run).
5. Restore the arm64 extension binary in the working project before exporting
   locally (ADR-0006 update).

---

## 10. Final milestone assessment

The engineering work of M0.2 is complete and its Linux-verifiable parts are
proven: the export configuration is correct and produces a signed, verifiable
ARM64 release APK with the extension packaged and no unnecessary permissions;
instrumentation reports only real measurements and is switchable and cheap;
the screenshot harness fails loudly instead of silently; and generation reads an
immutable palette snapshot, with tests that would catch a regression.

What remains is device evidence, and only that: nobody has run the release APK.
Combined with the user's confirmed Editor testing, the milestone is in good
shape, but "the release build works" is not yet a fact and is not claimed here.

**Recommendation:** approve the code and documentation, and make the single
device run in §9 item 1 the closing acceptance test before M1 starts.

---

## 11. Documentation produced and corrected

| Document | Change |
|---|---|
| `Milestones/M00_02_ANDROID_VALIDATION.md` | **new** — this document |
| `Milestones/M00_02_ANDROID_TESTING_CHECKLIST.md` | **new** — step-by-step device checklist, incl. the 20–30 minute sustained test |
| `Milestones/M00_02_ANDROID_INPUT_FIX.md` | §6 rewritten: the Android Editor run is now recorded as confirmed, with the release-build distinction kept |
| `Decisions/ADR-0008-numeric-input-for-touch.md` | consequence corrected: the touch fix is verified on hardware, not outstanding |
| `Decisions/ADR-0009-performance-instrumentation.md` | **new** — what is measured, what is not, and why |
| `Decisions/ADR-0010-palette-generation-snapshot.md` | **new** — snapshot rule for generation inputs |
| `Decisions/ADR-0006-trimmed-extension-binaries.md` | updated earlier in M0.2: Linux-only binaries |
| `PROJECT_CONTINUATION.md` | current state, commands, ADR table, limitations, next steps |
| `screenshots/m00_02_profile_overlay.png` | **new** — the overlay with the profiling block |

Earlier milestone records (`M00_01_*`) were not modified.
