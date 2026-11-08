# M3 camera, streaming and adapter guide

## Launching
- Blocky: open `scenes/main.tscn`, Run Current Scene. This remains the project's default main scene.
- Smooth: open `scenes/smooth_terrain.tscn`, Run Current Scene. It inherits main and overrides only `World.smooth_terrain`.
- Both use the same WorldConfig defaults, seed 1337 and GeographicSurface implementation.

## Camera
OrbitCamera remains the one camera and owns the one VoxelViewer. Fly mode is an exclusive branch before orbit event dispatch. Switching clears transient mouse/touch state and velocity. Returning to orbit reconstructs a target along the viewing direction, preserving transform. The first subsequent orbit drag restores the original downward-looking pitch restriction; looking upwards in fly mode is allowed.

Desktop: F switches modes. Orbit controls are unchanged (drag orbit, middle/right drag pan, wheel zoom). Fly uses WASD, Space up, Ctrl down, Shift 4× boost; hold right mouse button and move to look. Wheel adjusts speed ×/÷1.25, range 1–2048 voxels/s, default 32. Exponential velocity smoothing has rate 10/s. Keyboard movement is suppressed while a GUI control owns focus. No altitude clamp or target is used by fly movement.

Touch: tap Orbit / Fly at top. In Fly, bottom-left MOVE pad uses relative finger displacement; bottom-right LOOK pad rotates. UP/DOWN panels control vertical movement, BOOST gives 4× speed. Each raw finger owns its region until release. Touch events never pass to orbit while flying. Controls are visible on desktop too for testing. Portrait/small-screen layout and interrupted-touch lifecycle still need device validation.

## Vertical streaming
WorldConfig.view_distance_voxels defaults to 128 (horizontal). vertical_view_distance_voxels defaults to 128 independently. Panel exposes both, 32–512; press Regenerate to apply. The inspector permits larger vertical values, but do not use enormous radii on mobile.

The extension requires a ratio: viewer.vertical_ratio = vertical/horizontal. VoxelTerrain's maximum view distance is set to max(horizontal, vertical). The installed API accepts ratios above 1; upstream v1.7 `terrain/voxel_viewer.cpp` multiplies view distance by this ratio. Blocks are rounded to the library's streaming grid. Data streams around the moving viewer, not from the origin to the viewer. A mountain larger than the streamed volume will still be clipped outside that volume: this is not infinite simultaneous rendering.

The geographical 2..96 clamp is removed at both composition and post-detail stages (the engine's existing zero-bounds sentinel disables its final clamp). terrain_height's inspector supports larger values; panel cap is 1,000,000 for input validation, not a geographical ceiling. Basins still have geography-relative floors; these are not absolute altitude bounds. Existing version 2 field streams remain unchanged; heights formerly clipped to the old range now differ deliberately.

## Adapter boundary
GeographicSurface -> TerrainBlockGenerator -> CHANNEL_TYPE (16-bit) -> VoxelMesherBlocky
GeographicSurface -> TerrainSmoothGenerator -> CHANNEL_SDF (32-bit float) -> VoxelMesherTransvoxel

Both worlds construct GeographicSurface from a configuration snapshot. Neither adapter computes mountains, coastlines or plateaus. Smooth asks sample_block_heights once per block and writes world_y-height via set_voxel_f. Negative is solid, positive is air; zero is the geographical surface. This is a height-field implicit function, NOT a Euclidean signed distance on steep slopes and NOT volumetric terrain.

The installed extension's 16-bit floating API readback quantized 0.01 to zero and 0.5 to ~0.4883; 32-bit avoids that precision loss. Values saturate at ±512 only away from the isosurface. Far blocks use uniform fill, other blocks use per-voxel native writes; temporary heights are block-local. No new geography cache or native code is introduced.

Transvoxel has transitions disabled because VoxelTerrain is single resolution. Texturing defaults to TEXTURES_NONE; a uniform grass-coloured StandardMaterial3D avoids texture channels/shaders. Blocky retains its existing palette/material. Smooth surface is fractional; blocky fills through floor(height), so its top faces can differ by up to one voxel. No mesh post-smoothing is performed.

Sources verified against installed ClassDB/API probes:
- https://voxel-tools.readthedocs.io/en/latest/api/VoxelMesherTransvoxel/
- https://raw.githubusercontent.com/Zylann/godot_voxel/v1.7/terrain/voxel_viewer.cpp

## Android Editor validation (no export)
1. Restore the matching Voxel Tools 1.7 Android editor arm64 library from your original extension archive into addons/zylann.voxel/bin (ADR-0006); this workspace retains only Linux binaries.
2. Copy/import the project.godot project into Godot 4.7.2 Android Editor. Wait for imports; confirm no extension/parse errors.
3. Open scenes/main.tscn and use Run Current Scene. Start at horizontal 128, vertical 128. If memory/streaming is excessive, try vertical 64 (independent, no longer a hard restriction).
4. Test orbit, pinch, pan, the original four fields, Regenerate and Random seed.
5. Tap Orbit / Fly. Use MOVE and LOOK simultaneously, then UP/DOWN with BOOST. Release all fingers and confirm motion decays to rest. Switch back and check no position jump.
6. Set height 260 and vertical 192, Regenerate. Fly up to a peak, then farther upward. Confirm nearby blocks stream and old blocks unload. Do not expect the ground to remain visible when outside the configured radius.
7. Stop. Open scenes/smooth_terrain.tscn and Run Current Scene. Repeat the SAME seed, height and viewing distances. Compare land layout; smooth slopes should replace voxel steps.
8. Record frame time and memory at vertical 64/128/192 for each scene, horizontal 128, equal camera pose and warmup. Also test switching apps/backgrounding, interrupted touches and long travel. These are pending device checks, not passed tests.
