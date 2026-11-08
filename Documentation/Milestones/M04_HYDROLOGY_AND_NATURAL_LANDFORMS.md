# M4 — Hydrology and Natural Landform Development

**Status: working implementation checkpoint, NOT full M4 completion.**

Rivers, tributary accumulation, closed-basin lakes, terrain carving, variable-width river valleys, waterfall candidates and shared water visualisation work in both scenes. **Routed lake outlets/connected overflowing lake chains and dedicated river terraces are still missing.** Cold generation cost and coarse shoreline quality also need refinement. Those requirements are not silently reclassified as completed.

## 1. Implemented features
- Deterministic, height-aware D8 source-to-terminal networks, reconstructed independently of voxel chunks.
- Elevated sources, shared receiver paths, tributary confluences and source-count accumulation.
- Entire unsupported or over-budget routes rejected, never cut off as accepted rivers at a query boundary.
- Variable widths/depths, curved reaches, smooth banks and slope/flow-dependent river-valley/floodplain envelopes.
- Connected-sublevel lakes in measured depressions, with constant water level below a minimax-measured spill saddle.
- Steep-drop waterfall candidate data and concentrated reach profiles, not animated waterfall effects.
- Renderer-independent water queries and shared diagnostic meshes in both scenes.
- A labelled **Lake demo (seed 1337)** button makes the matched landmark reachable without an Android keyboard.
- Targeted M3 ownership/teardown fixes, pause/focus input reset and an executed Transvoxel normal-orientation test.

## 2. Exact authored files created and modified
### Created
Code and tools (each also has a Godot `.gd.uid` sidecar):
```
src/core/hydrology/drainage_network.gd
src/core/generation/modules/hydrology_module.gd
src/world/hydrology_water_view.gd
tests/suites/m4_hydrology_suite.gd
tests/m4_survey.gd
tests/m4_landmark_survey.gd
tests/m4_measurements.gd
tests/m4_scene_measurements.gd
```
Documentation/evidence:
```
Documentation/Decisions/ADR-0018-bounded-drainage-and-shared-water.md
Documentation/Architecture/HYDROLOGY.md
Documentation/Research/M04_VINTAGE_STORY_TERRAIN.md
Documentation/Milestones/M04_HYDROLOGY_AND_NATURAL_LANDFORMS.md
Documentation/Milestones/m4-evidence/blocky_basin_1337.png
Documentation/Milestones/m4-evidence/smooth_basin_1337.png
Documentation/Milestones/m4-evidence/tests-linux.txt
Documentation/Milestones/m4-evidence/sampling-linux.txt
Documentation/Milestones/m4-evidence/rendering-linux.txt
Documentation/Milestones/m4-evidence/landmark-survey.txt
```
Godot generates `.png.import` metadata for the two evidence images on import.

### Modified
```
src/core/generation/generation_module.gd
src/core/generation/terrain_generation_stack.gd
src/core/generation/geographic_surface.gd
src/world/world_config.gd
src/world/voxel_world.gd
src/world/main_scene.gd
src/debug/debug_panel.gd
src/camera/orbit_camera.gd
src/camera/flight_controls.gd
scenes/main.tscn
tests/suites/m2_generation_suite.gd
tests/test_runner.gd
tests/run_tests.sh
tests/benchmark.gd
Documentation/Architecture/OVERVIEW.md
Documentation/PROJECT_CONTINUATION.md
Documentation/Milestones/M03_VERTICAL_WORLD_FLYCAM_DUAL_MESHING.md
```
Neither voxel adapter, the smooth scene inheritance file nor the existing geographical modules were replaced. The generation engine implementation was not duplicated or modified. Imported/generated workspace caches are not authored source changes.

## 3. Vintage Story findings
Full report: [terrain research](../Research/M04_VINTAGE_STORY_TERRAIN.md).

The useful distinction is **large-scale landform organization versus local roughness**. Documented landform maps, octave amplitudes/thresholds and vertical density profiles provide several independent shape controls. Geological provinces should not be mistaken for a verified tectonic simulation. Terra Prety's macro plains/range/coast organization and Watersheds' terrain-aware sampling are mod descriptions, not guarantees about vanilla VS internals. Future work should add broad weighted landform profiles, not copy a catalogue or disguise the terrain with foliage.

The two described reference images were unavailable in the workspace. Public screenshots and documentation were inspected; no gameplay video was viewed, and no third-party terrain source/assets were copied.

## 4. Selected algorithms
Hash-addressed source parcels; D8 steepest descent; accepted-source accumulation; a bounded minimax saddle search using a binary heap; connected sublevel flood; cubic reach interpolation approximated by four chords; distance-based bed/bank/valley shaping. This is not full rainfall accumulation, erosion, fluid simulation or a complete Priority-Flood world raster. Strahler ordering was investigated conceptually but is not implemented.

## 5. Drainage-region architecture
See [hydrology architecture](../Architecture/HYDROLOGY.md) and ADR-0018.

The `hydrology` module has stable id/version, declared `surface` dependency and the existing GenerationContext. It reads uncarved columns from the same engine, and GeographicSurface applies its shaping. Query tiles are 128 voxels, source parcels 128, routing lattice 32, accepted routes at most 16 edges, lake search ±128. A conservative 688-voxel halo reconstructs all source support relevant to a tile. All caches are bounded; eviction changes cost, not results.

## 6. Routing and continuity
Global-coordinate receiver decisions and complete-route reconstruction avoid tile-owned outlets. Routes meet at the same receiver nodes; shared endpoints and endpoint widths agree. Source-count accumulation controls width. Tests compare reversed tile-generation order, shared boundaries, arbitrary versus bulk columns and four-worker sampling.

The bounded acceptance rule has a consequence: long/unsupported watersheds disappear as a whole. It does not generate continental rivers of arbitrary length. Four-chord curves soften D8 turns but do not remove all grid-direction bias.

## 7. Lakes and floodplains
Lakes use actual depressed terrain and connected flood components, not circles. In the 81-tile seed-1337 survey, four retained lakes have 121, 42, 105 and 29 coarse cells. A broader three-seed survey found 9/22/10 distinct lakes; the largest encountered has 250 cells (coarse sampled footprint, not a precise continuous area). Rivers back up to a terminal lake level where appropriate.

Floodplain support grows with river width and shrinks with reach drop; bank profiles blend into original terrain rather than flattening every valley equally. **There are no dedicated river terraces. Lakes remain below spill, without routed overflow outlets or connected lake chains.**

## 8. Waterfall identification
A reach must have at least 8 voxels of water-profile drop and average gradient above 0.2 to qualify. The record carries the real reach drop and endpoint levels; its middle profile concentrates the descent. Tests require actual descending candidates. This establishes steep-drop geographical data only; not every candidate has been visually judged to resemble a convincing waterfall. Water curtains, spray, foam and fluid animation are not implemented.

## 9. Shared water interface
`GeographicSurface.get_water_at(x,z)` returns water kind, surface level, carved ground height, river width and a coordinate-derived body/reach identity. The drainage service exposes immutable reach/lake data and copied inspection routes. Ocean remains the sea-level plane; river/lake diagnostic meshes are built from the same data on a bounded background task.

## 10. Both scenes share the same data
Default blocky scene remains `scenes/main.tscn`; smooth remains `scenes/smooth_terrain.tscn`. Both instantiate identical configuration/GeographicSurface code and hydrology. No separate blocky/smooth river generator exists.

Matched real captures:
- [Blocky basin](m4-evidence/blocky_basin_1337.png)
- [Smooth basin](m4-evidence/smooth_basin_1337.png)

Seed 1337; focus (256, −544); distance 115; pitch −35; yaw 25; horizontal/vertical radii 128. The lake shape and level are shared, while block surfaces retain voxel quantization. Final water material clips conservatively to nearby streaming range; camera-limited geometry is not evidence that the geographic lake ends there.

## 11. Automated tests executed
**333 checks, exit 0, zero SCRIPT ERROR lines, zero shutdown leak warnings, zero get_global_transform-outside-tree warnings in the final full Linux run.**

| Suite | Checks | Result |
|---|---:|---|
| core | 17 | PASS |
| generation | 57 | PASS |
| M2 | 63 | PASS |
| M3 | 29 | PASS |
| M4 | 30 | PASS |
| voxel | 27 | PASS |
| reliability | 24 | PASS |
| performance | 41 | PASS |
| UI | 45 | PASS |

[Merged execution log](m4-evidence/tests-linux.txt). Expected negative registry tests deliberately report engine errors; the sandbox may also report missing audio hardware. Do not describe this as a log containing no ERROR strings of any kind.

M4 checks include seed/order/repeat determinism; actual elevated source eligibility and terminal endpoints; descending profiles; accumulation/confluences; lake levels; real carving; shared index-boundary equality; width agreement; bulk/isolated samples; config disable; bounded caches; four-worker results; matching adapter paths; registry release; native smooth normals; and focus/pause reset paths.

The M2 suite now explicitly disables hydrology in its fixture. This preserves its isolated valley-parameter monotonicity and original sampling-performance contract: changing a valley can legitimately reroute M4 rivers, so comparing the newly routed final terrain is not an isolated valley test. Its expected registry order now includes the hydrology module. M4-enabled integration is separately executed; assertions were not silently dropped.

## 12. Tests written but not executed
All automated suites added here were executed. The Android Editor checklist below is **written but unexecuted**. Windows, multi-hour device streaming, app interruptions on real Android, cross-platform bit-identical determinism and high-resolution basin watertightness remain unverified. There is no unexecuted lake-outlet test passed off as successful: that feature is absent.

## 13. Performance measurements
### Linux sampling / drainage
Godot 4.7.2, Linux x86_64. Fixed 8×8 block-column region around the lake; 16³ adapter buffers; 192 actual block calls in warm tests. [Raw sampling log](m4-evidence/sampling-linux.txt).

| Hydrology | First 64 column blocks | Warm blocky µs/block | Warm smooth µs/block | Repeated water query µs |
|---|---:|---:|---:|---:|
| Off | 13.743 ms | 221.11 | 668.64 | 13.99 |
| On | 721.456 ms | 105.61 | 408.69 | 25.92 |

The faster **warm** enabled row is a cache effect, not evidence that hydrology is intrinsically cheaper. Before the final 512-entry 16²-column cache, measured enabled adapter times were 1709.79/1943.25 µs per block. Cold drainage remains expensive. The cache stores only a fixed footprint, with ~512 KiB maximum packed-height payload, plus dictionary overhead. Full cold survey of 81 hydrology tiles was about 1.2 seconds in the direct suite.

450 sequential drainage-index requests across 57,600 horizontal voxels exercised cache turnover. Static allocation at three phases was **33.98 → 37.81 → 34.00 MB**; tile count stayed 32, other caches remained within declared limits. This is a bounded CPU data-cache stress probe, **not multi-hour rendered streaming or a GPU/RSS plateau test**.

### Linux rendering (software GPU)
X11/Xvfb, llvmpipe Vulkan Mobile; both scenes same seed/pose/radii. 20 frames after local terrain readiness; enabled readiness additionally waits for nine water mesh tiles. Single sequential process; static allocation is not isolated RSS or GPU memory. [Raw rendering log](m4-evidence/rendering-linux.txt).

| Scene | Hydrology | Ready ms | Mean frame ms | Static MB |
|---|---|---:|---:|---:|
| Blocky | Off | 5475 | 406.39 | 105.95 |
| Blocky | On | 8519 | 393.36 | 108.36 |
| Smooth | Off | 5741 | 412.34 | 274.89 |
| Smooth | On | 9288 | 410.65 | 276.97 |

These noisy software-rendering numbers do not establish a GPU speed improvement. They include different geometry and are unsuitable for predicting Android FPS. The table was recorded before the final conservative water-distance clipping material; final screenshots and integration tests include that material, but a fresh timed rendering comparison after it was not run.

### Historical benchmark correction
Inspection found `tests/benchmark.gd` counted 5×5×5×2 blocks while its loops generated 5×5×2. Its throughput denominator was five times too large. The counter is fixed. Old benchmark figures produced by that version must not be compared directly to current measurements; this correction is not a remeasurement of M1/M2. New M4 measurements use their own explicitly counted loops. The corrected legacy harness was also executed and confirmed 50 block calls per pass and successful streaming; its old hardcoded vertical-ratio label was replaced with actual viewer/config values.

### Android
User reports approximately **50 FPS blocky / 48 FPS smooth** after testing M3. These are user observations, not controlled measurements by the assistant. No M4 Android benchmark was performed.

## 14. Known limitations
- Missing routed lake outlets/connected lake chains and river terraces: full M4 remains incomplete.
- Short bounded catchments; long or unclosed routes are entirely omitted. No full global drainage coverage, discharge model, precipitation field or Strahler order.
- Separate coarse sinks are not consolidated into a basin hierarchy; overlapping basin levels/outlets require further validation.
- Lake shore support is an 8-voxel raster; sub-grid leakage/shore stair-stepping is possible. Closed at sampled resolution is not a proof of fully watertight shore geometry.
- Cubic curves use four chords and inherit some D8 directional bias; banks/floodplains are not erosion products.
- Waterfall data is candidate-level; rendering is diagnostic static water, not falling-water simulation.
- Diagnostic meshes use a 2-voxel grid, can miss narrow edge fragments, load after terrain and clip to finite streaming bounds. No foam, refraction, depth-based colouring or underwater volume.
- Cold preprocessing is serialized under a network mutex and remains a mobile hitch/latency risk. Memory figures exclude native/GPU allocations not exposed by the monitor.
- The lake demo resets seed to 1337, height to 26 and enables hydrology, but preserves other configuration; if other geography parameters were edited, the exact pictured lake need not match.
- No Android/Windows execution or cross-platform bitwise claim.

## 15. M3 validation follow-up
**Resolved with executed evidence:** registry/module RefCounted cycle (weak back-reference); native terrain teardown transform warning (free while still attached); explicit negative-inside smooth plane normals point upward. Final full run shows no former leak/transform warnings.

**Improved, still awaiting hardware validation:** focus loss/pause clears orbit ownership, fly velocity, touch movement and boost; automated direct notification-path checks pass. Actual Android interruption/background lifecycle has not been exercised.

**Still open:** multi-hour rendered streaming/memory plateau, high-speed movement responsiveness and device-specific behaviour. The 450-tile CPU probe does not replace those tests. The user's successful scene tests and 50/48 FPS observations are recorded, not upgraded to controlled validation.

## 16. Exact Android Editor instructions
1. Restore the matching **Voxel Tools 1.7 Android editor arm64** library from your extension archive into `addons/zylann.voxel/bin/` per ADR-0006. This workspace retains Linux binaries only. Do not export an APK.
2. Import `project.godot` in **Godot 4.7.2 Android Editor**. Wait for imports and check the error panel.
3. Open `scenes/main.tscn`; choose **Run Current Scene**. Defaults: seed 1337, terrain height 26, horizontal 128, vertical 128, hydrology enabled.
4. Tap **Lake demo (seed 1337)**. It regenerates and frames (256, −544). Wait for terrain and the blue lake/river mesh, which loads separately. Inspect banks, the basin and incoming channels using orbit/pinch.
5. Tap **Orbit / Fly**, use MOVE and LOOK simultaneously, and UP/DOWN/BOOST. Follow channels; compare narrow upper reaches with joined/wider reaches. Travel across 128-voxel coordinate boundaries while watching for jumps.
6. Background and resume the running scene, including while touching MOVE or BOOST. Verify motion does not remain latched. This is a pending device check.
7. Stop. Open `scenes/smooth_terrain.tscn`; choose **Run Current Scene** and repeat the same demo. Geography/water layout should match; steps become smooth slopes.
8. For an enabled/disabled comparison: stop; select World → its WorldConfig resource; toggle `hydrology_enabled`; run again with identical seed and camera pose. Do not press the demo button for the disabled measurement—it explicitly re-enables hydrology. `hydrology_source_rise` and `hydrology_width_scale` are inspector controls.
9. Record warm frame time/memory and first-load delay for both scenes. Start with radii 128/128; if needed lower them independently. Distinguish cold water loading from steady rendering. Exercise the original numeric fields, Regenerate, Random seed and seed restoration.
10. Report any seam with seed, config, scene and viewer coordinates. Extend to long-duration flight only after ordinary device memory/performance is acceptable.

## 17. Packaging confirmation
No APK or release package generated. No `artifacts/` or `.android/` directory recreated. Default main scene is unchanged. No new native extension, GPU compute system, foliage, biome, climate, erosion, cave or gameplay system added.

## 18. Recommended next milestone
**Finish M4 before starting M5:** canonical spill/outlet routing and connected basin chains; explicit river terraces; high-resolution shoreline validation/quality; lower cold-preprocessing latency; and Android Editor measurements. Only then pursue the research-derived large-scale landform profile refinements. Do not mask unfinished geometry with vegetation.
