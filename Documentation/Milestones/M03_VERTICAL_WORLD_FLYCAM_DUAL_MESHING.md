# M3 — Vertical World, Flycam and Dual Meshing

**Status: working implementation and Linux evidence; final validation/refinement still pending. Do not treat this as all acceptance criteria signed off.**

## 1. Implemented features
Switchable orbit/fly camera, desktop controls and raw multi-touch pads; independent horizontal/vertical streaming; removal of geographical fixed height bounds; inherited independently launchable smooth scene using the same GeographicSurface. Default main scene remains blocky. No prohibited terrain/gameplay systems added.

## 2. Exact authored file changes
Created:
- src/camera/flight_controls.gd
- src/voxel/terrain_smooth_generator.gd
- scenes/smooth_terrain.tscn
- tests/suites/m3_suite.gd
- tests/m3_measurements.gd
- Documentation/Architecture/M3_CAMERA_STREAMING_ADAPTERS.md
- Documentation/Milestones/M03_VERTICAL_WORLD_FLYCAM_DUAL_MESHING.md
- Documentation/Milestones/m3-evidence/smooth_mountains.png
- Documentation/Milestones/m3-evidence/tall_streaming.png
- Documentation/Milestones/m3-evidence/tests-linux.txt
- Documentation/Milestones/m3-evidence/measurements-linux.txt
Modified:
- src/camera/orbit_camera.gd
- src/world/main_scene.gd
- src/world/voxel_world.gd
- src/world/world_config.gd
- src/voxel/voxel_terrain_builder.gd
- src/core/generation/modules/surface_module.gd
- src/debug/debug_panel.gd
- scenes/main.tscn
- tests/capture_screenshot.gd
- tests/test_runner.gd
- tests/run_tests.sh
- tests/suites/core_suite.gd
- tests/suites/generation_suite.gd
- Documentation/Architecture/OVERVIEW.md
- Documentation/PROJECT_CONTINUATION.md
Godot also creates .gd.uid sidecars for new scripts and .png.import metadata for images. Scratch API probes were removed. No artifacts/ or .android/ directory recreated.

## 3–7. Controls, configuration, API and shared generation
See [implementation and Android guide](../Architecture/M3_CAMERA_STREAMING_ADAPTERS.md). Desktop F / on-screen Orbit-Fly toggles; WASD, Space/Ctrl, Shift, right-drag look and wheel speed. Touch MOVE/LOOK/UP/DOWN/BOOST. Defaults: 128 horizontal, 128 vertical; fly speed 32. Smooth uses VoxelMesherTransvoxel, CHANNEL_SDF at DEPTH_32_BIT with set_voxel_f(world_y-height). Both scenes use the identical GeographicSurface stack; no duplicated geography.

## 8. Automated tests executed
Final full shell run: **303 checks, exit 0, zero SCRIPT ERROR lines**.
Core 17; generation 57; M2 63; M3 29; voxel 27; reliability 24; perf 41; UI 45. Full log is retained. Shell runner now fails on SCRIPT ERROR/Parse Error as well as process exit code.

M3 tests exercise actual density buffers, overlap continuity, streaming-invariant geography, tall/deep configurations, transform preservation, movement, raw touch dispatch/release, independent viewer settings, same registered modules, correct scene meshers and live meshing for both scenes. A height amplitude of 2000 produced a sampled peak of **3016.55**. Default-bound historical tests remain; the far-coordinate bound test now uses an amplitude-derived envelope because the old hard floor legitimately clipped two samples. This is a changed contract, not a relaxed continuity/determinism requirement.

Important: **zero SCRIPT ERROR does not mean a clean engine log**. Logs contain ObjectDB/resource leaks on shutdown and get_global_transform calls outside the tree during some rebuild suites. Their origin/regression status has not been isolated. Expected negative registry tests also log errors. These need triage before full completion.

## 9. Unexecuted validation
Android Editor and Windows runs; long-duration streaming/memory plateau; interrupted touch/focus lifecycle; sustained high-speed flight; explicit mesher-normal orientation assertion and a broad smooth coastline/island/underwater visual tour. Manual Android checklist is written, not executed. No claim of cross-platform bit-identical determinism.

## 10. Performance (Linux only)
Godot 4.7.2, X11/Xvfb, llvmpipe software Vulkan Mobile. Horizontal 128, seed 1337, 20 sampled frames after local area readiness. Single sequential process: static allocation figures are NOT process RSS or isolated peaks and may retain resources from prior cases.

| Mode | Vertical | Initial readiness ms | Mean frame ms | Static MB | Adapter µs/block |
|---|---:|---:|---:|---:|---:|
| Blocky | 64 | 4215 | 355.44 | 75.03 | 293.92 |
| Blocky | 128 | 3850 | 431.80 | 103.83 | 284.92 |
| Blocky | 192 | 4149 | 425.37 | 131.55 | 289.89 |
| Smooth | 64 | 4823 | 366.93 | 215.97 | 632.74 |
| Smooth | 128 | 5760 | 411.63 | 276.95 | 661.29 |
| Smooth | 192 | 6097 | 435.76 | 319.22 | 621.04 |

After +128 horizontal travel: readiness 1317–1430 ms blocky, 1312–1388 smooth. After +256 vertical travel: 609–715 ms blocky, 611–739 smooth. All requested local areas became meshed. See raw log for frame/memory measurements at each position. These are end-to-end streaming observations, NOT isolated mesher CPU timings. Adapter probe runs 100 newly addressed 16³ blocks; it is not directly comparable to M2's benchmark harness. Camera math tests pass, but touch responsiveness on hardware is unmeasured.

**Android:** owner reports approximately 50 FPS for the existing terrain. This is user-observed baseline only. No M3 Android numbers measured. Smooth density writes and storage are measurably more expensive; the first implementation needs optimization/retention investigation before claiming a mobile performance target.

## 11. Visual evidence and limitations
smooth_mountains.png is a real same-seed mountain capture, not a generated illustration (captured before title changed from M2 to M3). It visibly shows smooth peaks, slopes and valleys. tall_streaming.png shows actual terrain near a camera at y≈452 with amplitude 260 and vertical radius 192. It also exposes a limitation: such steep/high terrain extends beyond the small streamed volume and appears cut off. No claim that finite streaming renders an entire mountain at once.

Uniform smooth material does not reproduce blocky's strata or baked AO. Height-field model only; no caves/overhangs. 32-bit density storage costs memory. View distance and camera far plane are finite, world coordinates ultimately have engine/float precision limits. Very high amplitudes without changing horizontal scale create unnaturally steep slopes. Generation version remains 2 to preserve field identities; formerly clipped heights differ. Fly-to-orbit upward view is preserved on switch, but the next orbit drag applies the legacy pitch range. Multi-touch app-background handling and renderer shutdown diagnostics remain unresolved.

## 12. Android Editor instructions
Follow the numbered Android section in the implementation guide. Use Run Current Scene, not export/deploy APK. Restore only the matching editor extension binary needed by your device.

## 13. Packaging
No APK or release package generated. Default main scene unchanged. Removed artifacts and .android directories remain absent.

## 14. Next work
Finish M3 validation first: investigate teardown warnings and smooth memory, perform a complete matched blocky/smooth landmark tour, add explicit mesh-normal and long-travel checks, validate Android touch cancellation and performance. Only then choose M4; do not start rivers/biomes/volumetric generation as part of M3.


## M4 validation follow-up (historical findings above retained)
The M4 full Linux regression run executes 333 checks with no former ObjectDB/resource
leak warnings or out-of-tree transform warnings. A registry/module reference cycle
was fixed with a weak back-reference; native terrain is now freed while attached.
A real Transvoxel plane test confirms upward outward normals for negative-inside SDF.
Pause/focus input reset paths are implemented and tested, but Android lifecycle and
multi-hour rendered streaming remain unverified. The owner reports working scenes at
approximately 50 FPS blocky / 48 FPS smooth; these are observations, not controlled
benchmarks. See the M4 report for evidence and remaining limits.
