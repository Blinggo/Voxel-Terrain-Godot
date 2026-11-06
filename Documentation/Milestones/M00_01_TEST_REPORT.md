# M0.1 — Test Report

Date: 2026-11-06
Engine: `4.7.2.stable.official.ed1daf0bf`
Extension: Voxel Tools 1.7 GDExtension (`v1.7x`)
Host: Debian 13, x86_64, 2 vCPU, software Vulkan (lavapipe) for rendering

**Summary: 41 of 41 automated checks pass. Terrain generation and 3D rendering
are both verified on Linux/x86_64. Android and Windows builds were not produced
or run — see section 6.**

---

## 1. How the tests were run

```bash
# automated suites, headless (this is the CI command)
godot --headless --path . res://tests/test_runner.tscn -- --suite=all
→ RESULT: PASS  (41 checks)   in 3.07 s wall clock

# suites with a real rendering device (same result, needed for the screenshot)
Xvfb :99 -screen 0 1280x720x24 &
DISPLAY=:99 godot --path . res://tests/test_runner.tscn -- --suite=all
→ RESULT: PASS  (41 checks)

# render proof
DISPLAY=:99 godot --path . res://tests/capture_screenshot.tscn -- \
    --out=/tmp/shots/A.png --warmup=12 --seed=1337 --distance=100 --pitch=-28 --yaw=35

# performance
godot --headless --path . res://tests/benchmark.tscn
```

The runner exits `0` on success, `1` on any failed check, and `2` if it exceeds
its 150 s watchdog. `tests/run_tests.sh` wraps both suites and adds an optional
`--screenshot` pass.

---

## 2. Requirements coverage

Every requirement in section 3.F of the brief, with what actually ran.

| # | Requirement | Result | Evidence |
|---|---|---|---|
| 1 | Project opens without script errors | **PASS** | `--import` and `--quit-after 200` both produce no `SCRIPT ERROR`; the 41-check run is itself a clean load |
| 2 | Voxel Tools loads successfully | **PASS** | 7 required classes present in `ClassDB` after import |
| 3 | Voxel terrain node initializes | **PASS** | generator/mesher/library/format assertions |
| 4 | Terrain is actually generated | **PASS** | data block at origin; 49 columns read back as solid below / air above; mesh blocks reported meshed |
| 5 | Terrain renders in 3D | **PASS (Linux/x86_64, software Vulkan)** | rendered PNGs in `screenshots/` |
| 6 | Changing the seed changes terrain | **PASS** | sampled terrain hash `2034004599` → `3624338474` |
| 7 | Same seed produces identical terrain | **PASS** | hash unchanged across a full rebuild; whole-block byte comparison also equal |
| 8 | No visible seams between adjacent blocks | **PASS** | 201 live columns scanned across 3 block planes; 42+49 block-level columns compared to the analytic field |
| 9 | Camera can inspect the terrain | **PASS** | simulated drag changes the camera transform; wheel changes distance |
| 10 | No unnecessary errors or warnings | **PASS with caveats** | see section 5 |

### 2.1 Core suite (17 checks, no engine nodes)

`tests/suites/core_suite.gd` exercises the generation core against standalone
`VoxelBuffer`s.

- noise output is finite and stays in `[-1, 1]`
- noise is a pure function of its arguments
- **same seed ⇒ identical heights across two independently constructed instances** (324 columns)
- **different seed ⇒ different terrain** (99.7 % of 361 columns differ)
- zero amplitude ⇒ flat surface at base height; amplitude actually varies it (max deviation 19.55 voxels)
- palette layering: air above, grass at surface, dirt within `soil_depth`, stone below
- **block content is independent of generation order** — a block generated after its eight neighbours is byte-identical to the same block generated in isolation
- **no seams at block level** — columns reconstructed from two adjacent blocks and from a vertically stacked pair match the analytic height field exactly (42 and 49 columns)
- **concurrent sampling matches serial** on 4 threads (512 samples each)

The seam tests initially failed (3 mismatches). The cause was the test, not the
terrain: columns whose surface lies above or below the block were compared
against unclamped expectations. Fixed by clamping the expectation to what a
single block can contain.

### 2.2 Voxel integration suite (24 checks, live scene)

`tests/suites/voxel_suite.gd` instantiates the real `scenes/main.tscn`.

- extension classes registered; terrain created; generator is our `TerrainBlockGenerator`; mesher is `VoxelMesherBlocky`
- block library holds every palette type plus air (4 models)
- format is 16-bit on the type channel
- streaming region meshed; voxel data present
- **49 live columns**: air above the surface, solid below, grass on top
- **201 live columns** across the x = −32, 0 and 32 block planes: no seam
- rebuild with the same seed ⇒ identical hash; different seed ⇒ different hash
- simulated mouse drag orbits, wheel zooms

---

## 3. Errors encountered and resolved

Recorded because each one cost real time and none is documented upstream.

| Symptom | Cause | Resolution |
|---|---|---|
| All Voxel classes `false` on first run | GDExtension registers only after a project scan creates `.godot/extension_list.cfg` | run `--headless --import` once, then assert |
| `VoxelMesherBlocky.build_mesh()` returned `null` with no error | slot 0 of the block library was a cube; the mesher treats type id 0 as air unconditionally | put `VoxelBlockyModelEmpty` in slot 0, real blocks from id 1 |
| Same, second cause | library was not baked; the mesher reads only baked data | call `library.bake()` |
| `ERROR: Unsupported voxel depth` | mesher accepts only 8- or 16-bit type channels | pin `DEPTH_16_BIT` via `VoxelFormat` |
| `add_child()` failed with "Parent node is busy setting up children" | test added a scene during the runner's own `_ready` | deferred the insertion and awaited a frame |
| Scene loaded, exported node references all `null` | hand-written `.tscn` lacked the `node_paths=PackedStringArray(...)` declaration on the node | added it |
| Terrain data generated but nothing meshed in tests | test region extended below the viewer's vertical streaming band (ratio 0.5), so those blocks were never viewed | moved the probe region inside the band |
| `updated_blocks` always 0 | Voxel Tools 1.7 reports the counter but nothing increments it | do not use it; report `is_area_meshed` around the viewer instead |
| Mesh counting from GDScript always 0 | `VoxelMeshBlock` holds block meshes as **RIDs**, not `MeshInstance3D` nodes | assert `terrain.is_area_meshed()`; verify visuals with a rendered screenshot |

The last two are worth emphasis: two natural ways of verifying "terrain
generated" — counting updated blocks and counting mesh nodes — both silently
report zero on a working terrain.

---

## 4. Performance observations

Measured with `tests/benchmark.gd` on 2 vCPU. These are *observations on this
host*, not targets, and not Android numbers.

### 4.1 Generator throughput (single thread)

```
250 blocks of 16^3 in 9.0 ms  →  36.0 µs/block  →  ~27,700 blocks/s
```

≈ 8.8 ns per voxel, from GDScript, for the trivial-noise height field. This is
the shape the design intends: one noise sample and at most three `fill_area`
calls per column instead of 4,096 script-level `set_voxel` calls per block.

For reference, the naive per-voxel form would be roughly 4,096 script calls per
block; the column form is ~48 per block.

### 4.2 Streaming

```
region meshed: true in 0.16 s   (view distance 128, vertical ratio 0.5)
```

Small, because only the probe region has to finish; the whole view keeps
streaming in the background.

### 4.3 Known costs not yet measured

- steady-state frame time with a full 128-voxel view on a real mobile GPU
- memory per streamed block on Android
- thermal behaviour over minutes

The software-rendering host makes any frame-rate figure here meaningless, so
none is quoted.

---

## 5. Warnings and noise

Clean runs produce no `SCRIPT ERROR` and no Voxel Tools errors.

Deliberate, understood messages that remain:

- **lavapipe/Xvfb runs** print missing `libxkbcommon`, `libasound`, `libpulse`
  and a dummy-audio fallback. Environmental, not project-related.
- **`Orphan StringName ...` / `RIDs leaked` at exit** appear only for throwaway
  probe scripts that instantiated scenes without freeing them; the shipped test
  runner and the game do not produce them.
- **`updated_blocks` in `get_statistics()` is always 0** (upstream issue). It is
  not surfaced in the UI.

---

## 6. Unverified requirements — do not read as passing

| Item | Why it is unverified |
|---|---|
| **Android ARM64 runtime** | No Android SDK, JDK, export templates or device in this environment. The Android arm64 extension binary is present and of the right architecture, and nothing in the project is desktop-specific, but **the project has never been exported to or run on Android**. No performance, memory or input claim is made for it. |
| **Windows x86_64 runtime** | The Windows extension binary is present; no Windows machine was available. Not executed. |
| **Touch input path** | The touch handlers (`InputEventScreenTouch`/`ScreenDrag`, pinch) are implemented and reviewed, but only the **mouse** path was exercised automatically. Touch was never dispatched on a real device or emulator. |
| **Real-GPU rendering** | All visual results come from Mesa lavapipe (software Vulkan). Shader compilation, mobile tile-based behaviour and GPU timings are untested. |
| **Export build of any kind** | No export presets were created; export templates are not installed. Only editor/runtime execution was tested. |
| **Long-running stability** | Runs are seconds long. No soak test of sustained streaming. |
| **Frame-rate targets** | None asserted; the host cannot produce a meaningful frame rate. |

---

## 7. Visual evidence

`screenshots/terrain_seed_1337.png` and `screenshots/terrain_seed_90210.png` are
the same camera position with two seeds; `screenshots/terrain_closeup.png` shows
individual voxels and the stepped blocky structure. All three are direct output of
`tests/capture_screenshot.tscn`, rendered by Godot 4.7.2 with the Voxel Tools
blocky mesher.

Note what the screenshots also show honestly: at a camera distance of 150 the
streaming boundary is visible, because the streaming radius is 128 voxels. The
kept screenshots use distance 100 for that reason.
