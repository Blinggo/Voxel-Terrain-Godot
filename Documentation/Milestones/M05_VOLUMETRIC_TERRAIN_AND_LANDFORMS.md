# M5 — Volumetric Terrain Foundation and Landform Architecture

## 1. Status and implemented features

**Substantial implemented foundation; full M5 acceptance is not claimed.** This is working code and rendered evidence, not only a design proposal. Both scenes use shared density, ten blended configurable profiles shape the existing geography, genuine local volumetric recesses exist, legacy comparison remains available, and hydrology remains in the shared pipeline.

Visible changes include substantially larger alpine relief at the fixed range site, broader low-relief areas and changed basin/range relationships. Not every view is dramatically different. Smooth material blending, long-distance presentation, topology cleanup, Android performance and the inherited M4 gaps remain open. No Vintage Story/modded-Minecraft visual parity is claimed.

## 2. File manifest

Runtime files added:
- `src/core/density/terrain_density.gd`
- `src/core/landforms/landform_profile.gd`
- `src/core/landforms/landform_profiles.gd`

Runtime/scene files modified:
- `src/core/generation/modules/surface_module.gd`
- `src/core/hydrology/drainage_network.gd`
- `src/voxel/terrain_block_generator.gd`
- `src/voxel/terrain_smooth_generator.gd`
- `src/world/world_config.gd`
- `src/world/voxel_world.gd`
- `src/world/main_scene.gd`
- `src/debug/debug_panel.gd`
- `scenes/main.tscn`

The inherited `scenes/smooth_terrain.tscn` requires no separate geographical changes.

Tests/tools added: `tests/suites/m5_density_suite.gd`, `tests/m5_density_probe.gd`, `tests/m5_site_survey.gd`, `tests/m5_measurements.gd`, `tests/m5_component_measurements.gd`, `tests/m5_showcase.gd`. Modified: `tests/test_runner.gd`, `tests/run_tests.sh`, `tests/capture_screenshot.gd`, `tests/suites/voxel_suite.gd`.

Documentation/evidence are listed in §18. `m5-evidence/manifest.json` enumerates exact paths, byte sizes and SHA-256 hashes, including generated script UID files, all comparison images and evidence logs. The manifest excludes its own hash.

## 3. Research and verified licences

| Public project | Inspected revision | Verified repository licence |
|---|---|---|
| TsokasGit/primitive-voxels-godot | `5af560bb8ff936bfbd12468f64c22d63ffb0e36c` | **CC0-1.0**, not MIT |
| TokisanGames/Terrain3D | `852b6c9742bcfebab30d06857c547e2d8daa2f60` | MIT |
| Auburn/FastNoiseLite | `785f37a9ad76e283586a379675085f2063ae03f7` | MIT |
| fabian-becker/Terrainy | `98f42ff4463f14bc89798020670e13149eaf2f14` | MIT |
| Zylann/godot_voxel v1.7 | `2ac9f5f8a8219bf499314cc0fad54ffc47df908f` | MIT |

See `../Research/M05_VOLUMETRIC_TERRAIN.md` for source URLs, inspected subsystems, algorithms, documented performance, limitations and reuse conditions. Licence texts and hashes are preserved. Public availability was not treated as a licence. No external private repository was accessed. No third-party code/assets were copied into the new runtime.

## 4. Chosen techniques

- Existing tectonic, ridged mountain, plateau, valley and coast fields remain authoritative macro inputs.
- One normalized, partition-of-unity evaluator blends profile parameters before hydrology.
- One renderer-independent density object supports exact legacy height representation and hybrid finite-band 3D modification.
- Existing coordinate hashing supplies deterministic independent noise substreams.
- Built-in FastNoiseLite supplies all new noise; one octave per new band.
- Column reuse, a bounded measured-hotspot cache and conservative uniform-region bounds control repeated work.
- Existing Voxel Tools native blocky/Transvoxel meshers remain responsible for geometry.

## 5. Rejected techniques and visual iteration

An early signed structural-noise render created excessive rounded blobs. It was rejected; `m5-evidence/rejected-unrestricted-smooth.png` records that experiment. Structural noise now **carves only below the outer surface**, with steepness, depth and water masks. It can still produce local cavities or detached caps; no global topology correction is claimed.

Custom Marching Cubes, Terrain3D as a replacement renderer, Terrainy's editor/heightmap architecture, full cave networks, GPU/native/ML dependencies and full-world preprocessing were not adopted. Optional warp is off by default because it adds measured cost without being necessary for the foundation.

## 6. Architecture and migration

`geographical fields → blended profiles/base composition → existing surface detail → hydrology carving → shared density/material classification → adapters`

`VoxelWorld` explicitly constructs and passes its shared density. Configuration and nested profile resources are snapshotted. Caches are bounded and mutex-protected. No singleton or scene-node dependency was introduced into geography/density.

`get_surface_height()` is still the carved base H. In hybrid mode it is **not necessarily the final solid boundary**. Consumers needing true solid geometry must query density or terrain. A mode/configuration change defines a different generated world: the same seed alone is insufficient to reproduce it. Existing macro generation version remains 2; new density streams have their own version.

## 7. Density semantics and genuine volumetric geometry

Legacy mode reproduces `D=y-H`; negative/zero is solid and positive is air, verified against Voxel Tools v1.7 documentation and native plane normals. Primitive Voxels' inspected source uses the opposite sign and was not copied.

Hybrid density combines signed geological/fine terms with a nonnegative structural recess term. Structural effects fade in below depths 1–4 and out at 12–24. All modifiers are finite-band and profile-controlled. Ocean/coast, rivers and lakes are conservatively protected.

In the fixed seed-1337 patch x=[-128,-1], z=[-1536,-1409], y=[0,159], **919 columns have at least three solid/air transitions**. This proves non-heightmap occupancy. It does not prove every recess is externally accessible or that every solid is connected. The field is an approximate/shaped SDF, not exact Euclidean distance.

## 8. Ten profiles

Implemented IDs: plains, rolling hills, highlands, foothills, mountain ranges, alpine mountains, plateaus, mountain basins, coastal lowlands and steep rocky terrain.

Each resource supports elevation offset, relief, slope sharpness, ridge/valley influence, transition width and geological/structural/fine influence. Frequencies remain global per scale while profile influences blend smoothly, avoiding phase changes at profile transitions. These are ten parameter sets using one evaluator, not ten generators.

The exact parameter matrix, weight construction and configuration override procedure are in `../Architecture/DENSITY_AND_LANDFORMS.md`. Some profiles contribute without dominating the sampled survey; ten IDs do not imply ten visually isolated regions have all been accepted.

## 9. Scale hierarchy and noise

Existing macro frequencies/amplitudes for continents, elevation, mountains, hills, valleys, plateaus and fine surface detail remain configurable. New 3D defaults:

| Band | Amplitude | Frequency | Role |
|---|---:|---:|---|
| Geological | 2.0 | .008 | broad local volumetric modulation |
| Structure | 14.0 | .055 | masked undercut/recess carving; y frequency factor 1.8 |
| Roughness | .8 | .18 | bounded fine surface variation |

Each amplitude can be zeroed independently. Optional structural domain warp is clamped to 0–8 units and defaults to zero. No new dependency is required. The implementation does not spend full multi-octave 3D noise at every scale.

## 10. M4 integration and unresolved migration issues

Profile-shaped terrain is supplied to the existing hydrology system before density modification. Rivers, source/tributary accumulation, basin lakes, water levels, width, waterfall candidates and query format remain in that module. Routes may legitimately change between legacy and hybrid because their base terrain changes.

The M5 integration test checks **316 sampled wet reaches**: carving remains present and density modifications do not open their sampled beds. This is not a universal watertightness proof. River-protection support required extending the tile support margin from 48 to 64 units. Lake protection is deliberately conservative and can suppress nearby rocky detail.

Still unresolved from M4: routed lake outlets and connected chains; dedicated river terraces; high-resolution shoreline/saddle guarantees; basin consolidation; cold preprocessing latency; Android measurements and long-duration rendered streaming. Diagnostic blue water remains a separate coarse mesh, not real-time fluid simulation or polished waterfall geometry.

## 11. Adapters, materials, seams and cameras

Blocky: TYPE channel, shared material classification, upper-Y halo, run-length writes, exact legacy span fast path and conservative uniform fills.

Smooth: the same field in a 32-bit SDF channel, saturated at ±32, with native Transvoxel transitions still disabled. Conservative uniform fills equal the saturated field result. **Smooth still renders its existing single visual material; grass/dirt/stone blending is not implemented there.** Shared solid geometry is implemented; visual material parity is not.

Tests cover field sign/value, shared ownership, integer point/block agreement, partitioned blocks, negative-coordinate boundaries, material solidity, uniform encoding and native hybrid finite normalized normals. Existing native negative-inside plane orientation tests remain. Independent H/V streaming, orbit/fly and touch controls are preserved.

## 12. Executed and unexecuted validation

The baseline shared `y-H` refactor passed 17 core and 30 M4 checks before hybrid changes. The final standalone M5 suite passes **46 checks**: profiles, noise controls, snapshots, determinism, continuity/partitioning, genuine volume, hydrology protection, channels/materials, four-worker identity, cache reconstruction/bounds, native normals and both scenes' ownership and orbit/free-flight camera-preserving mode toggle.

**Final full regression: 379 checks PASS, 10 suites, exit 0.** Breakdown: core 17 + generation 57 + M2 63 + M3 29 + M4 30 + M5 46 + voxel 27 + reliability 24 + performance 41 + UI 45. The display-backed final log has no SCRIPT ERROR, parse error, leaked-resource or out-of-tree transform messages. Expected negative-test engine errors and sandbox audio warnings remain distinct from test failures. See `m5-evidence/tests-linux.txt`.

An initial full run exposed one legacy seam assertion comparing final terrain to floor(H). The revised check compares **every voxel in the existing scan window** against shared density rather than weakening a height tolerance. Other original assertions remain. The failed first-run log is preserved separately. A scene-test harness initially tried to add children during root setup; it was fixed by awaiting a frame, and the standalone rerun has no script/leak errors.

Not executed: real Android/Windows performance, cross-platform bit identity, Android hardware interruption lifecycle, long-duration rendered streaming/RSS/GPU plateau, broad all-seed topology/shoreline guarantees or visual acceptance of every profile. Existing owner M3 observations of ~50 FPS blocky/~48 FPS smooth are historical, not M5 measurements.

## 13. Linux measurements

Godot 4.7.2, Voxel Tools 1.7, sequential local tests. Sampling site: seed 1337, origin (-96,64,-1472), 16³ blocks. Cold is one density block, warm density averages 100 calls, each adapter averages 50 calls.

| Mode | Cold density ms | Warm density µs/block | Blocky adapter µs/block | Smooth adapter µs/block |
|---|---:|---:|---:|---:|
| Legacy | 528.436 | 400.10 | 84.54 | 787.54 |
| Hybrid | 685.045 | 2401.81 | 3492.36 | 2856.44 |

Legacy blocky uses the exact span path instead of allocating/evaluating all voxel densities. These warm costs are site-specific; uniform far blocks use conservative fast paths. Hybrid surface blocks remain materially more expensive.

Before the control cache, warm hybrid density was 6352.55 µs/block; the first cache measurement was 2354.07 µs/block. The final measurement above includes later changes. Cold drainage remains the dominant hitch risk.

Component probe (separate run): first unmodified 16² base 546 µs; first carved request 717645 µs; warm base 203.68 µs; warm cached carved columns .77 µs; profile blend 7.685 µs/node; uncached controls 3480 µs/16²; cached controls .43 µs/16². Timings are not additive because caching and call paths differ.

Finite-band evaluation microprobe, 20,000 samples each, explicit unit control: disabled bands .4353 µs/sample; geological only .7503; structure only .7954; roughness only .73625; all 1.08905; all plus warp amplitude 2: 1.322. These include GDScript evaluation overhead and are not standalone native-noise throughput.

The control cache holds at most 256 standard 16² packed-vector entries: 786432 bytes payload plus overhead. Existing carved-column cache payload is approximately 512 KiB. No full-world retained raster was introduced.

Software-rendered capture ranges across six sites, H=192/V=160, 960×540, llvmpipe Vulkan Mobile:

| Renderer/mode | Central readiness ms | 12-frame capture interval /12 ms | Godot static MB |
|---|---:|---:|---:|
| Blocky legacy | 12290–14249 | 269.91–383.36 | 193.36–381.43 |
| Blocky hybrid | 12743–16543 | 358.82–453.65 | 151.38–348.44 |
| Smooth legacy | 12889–14832 | 282.52–396.21 | 347.44–393.57 |
| Smooth hybrid | 13600–17409 | 340.91–551.51 | 330.39–387.49 |

The log's `mean_frame_ms` label includes screenshot readback/PNG encoding in that interval: **not a clean frame benchmark**. Readiness is central 32³ meshing plus nine water tiles, measured after scene initialization—not the whole visible frustum or total launch time. Sequential scenes retain engine/native allocations; lower hybrid static counters do not prove lower total memory. Static counters exclude RSS/GPU memory. These measurements do not predict Android FPS.

## 14. Visual evidence

Open **`M05_VISUAL_COMPARISON.html`**: self-contained offline gallery with 24 actual screenshots. Six sites × both renderers × legacy/hybrid, three seeds. Logged camera transforms were programmatically checked identical within each site's four images.

| Site | Seed | Target x,y,z | Distance | Pitch / yaw |
|---|---:|---|---:|---|
| Plains | 1337 | 128,38,128 | 135 | -18 / 35 |
| Rolling hills | 4242 | 704,44,960 | 120 | -22 / 35 |
| Plateau | 1337 | 192,58,-1472 | 140 | -24 / 35 |
| Basin / altitude | 1337 | 320,30,-640 | 160 | -50 / 25 |
| Coast | 90210 | 0,28,768 | 140 | -25 / 35 |
| Range | 1337 | -64,90,-1472 | 110 | -18 / -180 |

All use H/V=192/160, no foliage and no obscuring fog. Plains/coast changes are restrained. Range relief changes are conspicuous, but the coarse underlying sampling can still look faceted. The gallery includes medium/high-angle/range views; a dedicated close-up topology tour and genuinely long-distance range/LOD validation remain incomplete. Finite streaming edges and water limitations are visible, not hidden.

The earlier H=256 capture attempt failed its readiness deadline; its log is retained. Final images use the documented H=192 setup and all 24 report central readiness. This is not a claim that all distant chunks finished or that enlarged view distances are Android-ready.

## 15. Remaining limitations and acceptance gaps

- Smooth visual material palette is still single-material; no biome/vegetation disguise.
- Local enclosed cavities or detached caps can occur. No global connectivity guarantee.
- Profile catalogue exists, but every type has not received independent visual acceptance. Broad long-range composition needs more work than increasing relief.
- Coarse macro sampling can produce faceted/pointed silhouettes. Finite streaming boundaries remain visible; no distant LOD/clipmap added.
- Hybrid surface-block cost and cold hydrology latency are still high for the target budget.
- Water protection is conservative and suppresses some useful detail; shoreline proof and M4 outlet/chains/terraces remain open.
- Large view-distance capture readiness and long-duration Android streaming are not established.
- No full cave networks, erosion/climate/weather/clouds, biomes/vegetation, structures/NPC/gameplay or real-time fluids were added.

## 16. Exact Android Editor procedure — no export

1. Restore the matching **Voxel Tools 1.7 Android editor arm64** binary from the owner's original extension archive, following ADR-0006. The trimmed Linux workspace does not supply that binary.
2. Open the project in **Godot 4.7.2 Android Editor** and allow import. Confirm extension classes load. Do not use an APK/export workflow.
3. Open `scenes/main.tscn`; use **Run Current Scene**. The shipped scene defaults to Hybrid. Start with H/V=128/128; do not begin with the larger gallery distances.
4. Wait for streaming/water. Tap **Terrain: Hybrid** to switch to Legacy, then back. Seed and camera target/pose are preserved for orbit comparisons. Expect a rebuild and loading delay.
5. Open `scenes/smooth_terrain.tscn`; Run Current Scene. Repeat with the same seed, height, frequency and H/V values. It uses the same density, not a separate smooth geography.
6. Tap **M4 lake (legacy / 1337)** to restore the historical lake demonstration. This intentionally sets legacy mode, seed 1337, height 26 and hydrology on. Toggle Hybrid afterwards to inspect the effect of changing the base world; the old lake layout need not persist.
7. Use orbit/pinch/pan and Orbit/Fly, MOVE/LOOK/UP/DOWN/BOOST. Check numeric edits, Regenerate, Random seed and default input restoration. Background/resume the Editor during movement and verify no stuck touch input. Device behaviour is still owner validation.
8. For profile/noise experiments, stop the scene, select `World`, expand its `config` Resource in the Inspector, adjust Density Mode/amplitudes/frequencies or add matching-ID `LandformProfile` resources, then run again. Zero one amplitude at a time for cost/appearance comparisons.
9. For named sites, use the coordinates/poses in §14 while inspecting/flying. The offline gallery is the exact fixed-camera evidence. The CLI capture harness is a desktop reproduction tool, not an Android APK or an automatic on-device benchmark.
10. Only after the 128/128 baseline is usable, try H=192/V=160 for the gallery-scale workload. Record device model, settings, warmup, frame-time spikes, readiness delay and memory behaviour; compare the same path/seed in both modes. Do not infer device performance from llvmpipe numbers.

## 17. Build/export and dependency policy

No APK or production export was generated. No custom Godot engine, new native/GPU dependency, runtime ML or third-party terrain package was added. Existing Voxel Tools 1.7 and built-in FastNoiseLite are used. No `artifacts` or `.android` directory was recreated for development. Linux-only validation does not establish Android or Windows equivalence.

## 18. Documentation and reproducibility

- Research: `../Research/M05_VOLUMETRIC_TERRAIN.md` and `m5-licenses/`.
- Architecture/profile matrix: `../Architecture/DENSITY_AND_LANDFORMS.md`.
- Decision: `../Decisions/ADR-0019-shared-density-and-blended-landforms.md`.
- Updated overview and project continuation.
- Evidence: `m5-evidence/`, exact manifest, final/first-attempt logs, component/sampling probes, survey and screenshots.

Desktop commands from project root, with the matching engine available:

```sh
GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64
"$GODOT" --headless --path . --import
"$GODOT" --headless --path . res://tests/test_runner.tscn -- --suite=m5
DISPLAY=:99 GODOT="$GODOT" bash tests/run_tests.sh
"$GODOT" --headless --path . -s res://tests/m5_measurements.gd
"$GODOT" --headless --path . -s res://tests/m5_component_measurements.gd
DISPLAY=:99 "$GODOT" --audio-driver Dummy --resolution 960x540 --path . -s res://tests/m5_showcase.gd
```

A real display or Xvfb is required for rendered/UI checks. Grep logs for SCRIPT ERROR as well as process exit status; a GDScript coroutine failure can otherwise leave an incomplete run looking successful.

## 19. Recommended next work

Finish this milestone's acceptance before broadening scope: reduce cold/active-surface cost, validate actual Android Editor performance, improve macro silhouettes/long-view composition, add smooth material representation, and inspect local topology at close range. In parallel, resolve the inherited M4 outlet graph/connected lake chains, terraces and fine shoreline validation. Then consider bounded distant-LOD architecture and future cave integration as separate decisions—not an unmeasured stack of more 3D noise.
