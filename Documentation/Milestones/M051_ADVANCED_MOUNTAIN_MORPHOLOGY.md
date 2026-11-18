# M5.1 — Advanced Mountain Morphology and Landform Refinement

## Status

Implemented in the existing Godot 4.7.2 / Voxel Tools 1.7 project. This report is finalized with the executed regression/capture results below. **Android M5.1 acceptance remains the owner's Editor test.** The owner confirmed M5 works on Android; that is not a measured M5.1 performance result.

No engine replacement, additional noise dependency, APK or release export. No vegetation, decorative cover, climate, erosion simulation or cave network was added.

## 1. Diagnosis and rejected first attempt

The actual registered classes are `MountainModule` (field ID `mountainness`) and `TectonicsModule`. Their existing architecture was inspected, not replaced.

The pointed mountains had several interacting causes: a narrow three-octave ridged primary field, higher-frequency secondary ridges, hard component maxima, no independent summit/shoulder widths, and M5's mountain-dependent profile gains applied **after** plateau/valley carving. Eight-voxel interpolation then exposed isolated high nodes as pointed facets.

A width-only first implementation did not solve the visible problem. A forced-massif transect showed mountainness remaining broadly .84–1.04 while surface heights jumped from about 77 to 145: downstream composition was recreating isolated peaks. That capture run was rejected. The final path establishes mountain mass before carving and does not reapply the old summit-dependent gain afterward.

See `../Research/M51_MOUNTAIN_DIAGNOSIS.md`, `m51-evidence/transect.txt` and the archived `initial-composition/` images. The source diagnosis was recorded before changes; the measured second finding was recorded before changing SurfaceModule.

## 2. Research and licensing

- **Terrainy**, MIT, revision `98f42ff4463f14bc89798020670e13149eaf2f14`: deeply inspected mountain-range and evaluation-context source. Useful ideas were independent summit/skirt widths, connected cols, wandering crests, foothill/gully masks and immutable evaluation contexts.
- **FastNoiseLite**, MIT, revision `785f37a9ad76e283586a379675085f2063ae03f7`: inspected FBm, ridged accumulation and domain-warp implementations. The existing Godot implementation is reused; no new dependency.
- **Vintage Story Terrain Generation wiki**: studied octaves, octave thresholds and Y-position/Y-threshold configuration. The page does not specify a complete interpolation/sign convention. We independently define a monotone inverse threshold curve; no proprietary implementation or game assets were copied.

Full URLs, findings, limitations and licence evidence are in `../Research/M51_MOUNTAIN_RESEARCH.md`. Public research source archives are ignored by Godot's importer and are not runtime scripts.

## 3. Architecture preserved

`existing geographical fields / tectonics → MountainModule + optional MountainMorphology → SurfaceModule / LandformProfiles → existing fine detail → hydrology carving → TerrainDensity → unchanged blocky/smooth adapters`

M5.1 adds no registry module, singleton, mutable RNG, generated-neighbour dependency or retained spatial cache. It preserves M5's shared density, negative-inside convention, noise substreams, existing bounded caches and worker-thread ownership. Both adapters still consume the same field. The density implementation and voxel adapters were not changed for this milestone.

`mountain_morphology_enabled=false` is the M5 comparison. Refinement is active only with Hybrid density. The existing Legacy density mode remains available. `WorldConfig.new()` leaves refinement off for old callers; the shipped main scene enables it and smooth inherits that setting.

## 4. Six configurable styles, one evaluator

Added six `LandformProfile` resources under `resources/mountains/`:

1. `alpine.tres` — intentionally sharper upper crests.
2. `massif.tres` — broad summit and large surrounding mass.
3. `rounded.tres` — softer, broader caps.
4. `rugged.tres` — stronger ridge/col contrast.
5. `eroded.tres` — analytical gully-dissection appearance, not erosion simulation.
6. `highland.tres` — broad, lower-relief mountain forms.

One `MountainMorphology` evaluator consumes all six. Independent controls cover overall elevation, mountain/summit/ridge/shoulder/foothill widths, summit sharpness, ridge/valley influence, surface roughness, geological detail and transition width. Styles are continuously blended using normalized weights; no nearest-profile generator switch.

An empty `WorldConfig.mountain_profiles` list uses the six defaults. A nonempty list supplies a complete custom catalogue. New IDs work without edits to the evaluator, registry, SurfaceModule, density or adapters. The architecture document gives exact resource-extension steps and distinguishes these controls from the original ten-landform override list.

## 5. Vertical shaping and range composition

Each resource supplies normalized `terrain_y_positions` and `terrain_y_thresholds` for lower, middle, upper and summit regions. Strictly increasing pairs are compiled into a continuous monotone cubic inverse, height(signal). Positive harmonic-mean tangents avoid overshoot and do not force flat slopes at every key. Invalid key data warns and falls back to identity.

The refined primary crest uses one smooth-Simplex octave rather than three ridged octaves. Existing warp amplitude/frequency are reduced to 60 and .55×base; secondary frequency becomes 1.4×base rather than 3.2×base. Existing tectonic uplift/rift/province location remains. Separate summit, shoulder and foothill sections, nonzero col floors and secondary flank ridges distribute mountain mass rather than simply adding height to noise peaks.

SurfaceModule calibrates mountain relief before valley/plateau shaping. The 2.35 relief calibration replaces the former profile-gain/uplift combination; `terrain_height` and `mountain_scale` were not reduced. The original ten-landform composition is retained and blended back below the mountain envelope.

## 6. Measured morphology changes

Fixed seed 1337, hydrology disabled to isolate the geographical composition, x=-256..256 and z=-1728..-1216, eight-unit survey grid:

| Measurement | M5 | M5.1 default blend |
|---|---:|---:|
| Highest sampled surface | 137.019 | 130.279 |
| 95th percentile surface | 76.864 | 111.140 |
| Eight-unit samples above elevation 80 | 166 | 922 |
| Four-unit samples above 90% of each mode's peak, within 64 units of its maximum | 10 | 120 |

The peak remains about **95% of its previous height**, while high mountain mass and summit-top area increase substantially. This is not merely lowering the terrain. These are one-region measurements, not universal all-seed guarantees. The summit-area threshold is relative to each mode's own maximum, so it must not be presented as a common-altitude polygon-area measurement.

The parameter test also compares isolated profiles at identical theoretical peak elevation: increasing summit width expands the upper-ten-percent cross-section from 34 to 89 samples. Width/shape changes preserve the ideal peak scale.

## 7. Hydrology

Drainage algorithms, river/tributary data, water levels, widths, waterfall candidates, lake data and separate water geometry remain intact. Refined terrain passes the integration checks for real carving, protected sampled beds, descending levels, positive widths, tributaries, multiple lakes and waterfall candidates.

Wider mass changes drainage placement; it does not preserve every old water body. In the surveyed mountain region, some former summit basins fill as the surrounding mass is raised. The identical 81-tile inventory contains six lake IDs in M5 and four in M5.1; the former `lake:1:-42` summit basin is absent in the refined inventory. A final confirmed lake is `lake:1:-46`, including cell (32,-1480), level approximately 43.79224. The lake showcase uses that region. We do **not** claim that fewer/different lakes automatically means better watershed realism.

M4 limitations remain: lake outlets/connected chains, dedicated river terraces, basin consolidation, fine shoreline/saddle guarantees and cold preprocessing cost. The diagnostic blue mesh remains coarse and is not a fluid simulation. Broader mountains do not solve those issues.

## 8. Tests

The standalone M5.1 suite passes **44 checks**. They verify actual geometric effects of every requested morphology parameter, a new custom resource ID, vertical monotonicity and derivative continuity, key-edit effects, normalized blending, configuration snapshots, six distinct cross-sections, actual height/mass preservation, seed/negative-coordinate determinism, four-worker identity, chunk partitioning, shared density, terrain transitions, hydrology and both scenes' comparison/tour controls.

**Final full-regression result is recorded in the final validation update below.** Existing suites are retained; M5.1 does not replace them. The earlier fixed lake-cell assertion was updated after a surveyed hydrological world change, not made optional: final tests still require an actual queried lake. The old M5 path remains covered by its unchanged generation fixtures.

Not executed here: Android hardware performance/lifecycle, Windows or cross-platform bit identity, long-duration rendered streaming/RSS/GPU plateau, or exhaustive all-seed connectivity/shoreline guarantees.

## 9. Performance methodology

All final component measurements are Linux-only, run sequentially after capture processes exit. The first exploratory measurement was made while a supposedly stopped capture child was still alive; it is excluded from final benchmark claims and retained as a contaminated trial. That child was explicitly terminated. Some early final capture frame diagnostics also overlap that period; they are not used as controlled performance results.

The profile benchmark measures 10,000 calls per catalogue/style. Surface/density tests compare M5 and M5.1 with Hybrid density and hydrology enabled. The same x/z footprint is used; the y origin is placed eight units below each mode's own first-column surface so both sample the active surface band. Warm density averages 100 blocks; adapters average 50 actual 16³ blocks. Timings from different stages are not additive.

There are still six mountain-noise API calls per node, fewer primary octaves, and **no additional 3D noise evaluations**. Added resource blending/vertical arithmetic has a measurable cost. Existing node, hydrology and density caches keep their previous bounds.

Final uncontended measurement, `m51-evidence/sampling-linux.txt`:

| Stage | M5 Hybrid | M5.1 Hybrid |
|---|---:|---:|
| First unmodified 16² surface request, µs | 549 | 1173 |
| First carved 16² request, µs | 845896 | 1176780 |
| Warm unmodified 16² surface, µs | 104.97 | 133.55 |
| Warm density, µs / 16³ block | 3143.48 | 2964.47 |
| Blocky adapter, µs / 16³ block | 4586.76 | 4555.80 |
| Smooth adapter, µs / 16³ block | 3833.18 | 3177.06 |

The six-profile blend costs **20.2186 µs/evaluation**. Single-resource evaluations: alpine 3.556, massif 3.6133, rounded 3.3407, rugged 2.9655, eroded 3.1959, highland 3.9512 µs. These include the evaluator's arithmetic/weight/curve work, not all geographical fields or hydrology.

The active-band block origins are (-96,62,-1472) for M5 and (-96,89,-1472) for M5.1. Warm differences include changed terrain/water masks and sample heights, so the lower density/adapter values are **not a general speedup claim**. Cold carved work increases to about **1.18 seconds** in this probe—an explicit Android hitch risk. Cold values are one first-request sample per mode, not a statistical percentile. No Linux timing is an Android FPS prediction. The owner's M5 success report does not establish an M5.1 frame rate.

## 10. Visual evidence and reproducibility

The final offline comparison gallery is `M051_VISUAL_COMPARISON.html`. The completed set is **40 captures**: ten cases × both renderers × M5/M5.1: alpine, massif, rounded, rugged, eroded, highland, foothills, basin, lake range and distant silhouette. The first six force one resource to make styles directly inspectable; the last four use the default regional blend. M5 ignores the morphology resources in its disabled branch.

Each case uses identical camera transforms, seed, density settings and rendering settings within its four captures. Geometry is shown without foliage, decorations or obscuring fog. Exact poses live in `src/debug/mountain_showcase.gd`; `tests/m51_showcase.gd` logs the actual transforms and central readiness.

Linux gallery rendering uses Compatibility/OpenGL with llvmpipe, 960×540. The normal cases use H/V=160/160; the distant case uses 256/160. These settings are not an Android recommendation. Compatibility lighting differs from the project's default Mobile renderer; old and new comparisons use the same renderer. A separate **Vulkan Mobile** smoke check also completed for both blocky and smooth refined massifs, with central readiness true and successful PNGs (`m51-evidence/mobile/`, `mobile-linux.txt`). It uses the project-default renderer and the same geometry; it is still Linux llvmpipe, not an Android measurement.

Readiness means a central 32³ region around the local base surface is meshed and nine water tiles are available. It does not prove the entire frustum is loaded. Finite streaming edges, macro-grid facets and coarse water remain visible. Frame diagnostics exclude PNG readback/encoding in this harness but remain software-rendering diagnostics, not a controlled device benchmark. Native task-drain waits during scene teardown are retained in the log.

## 11. Android Editor procedure

1. Use Godot **4.7.2 Android Editor** and retain the matching **Voxel Tools 1.7 editor arm64** binary from the working M5 installation. For a fresh trimmed copy, restore it from the owner's original extension archive as in ADR-0006. No APK/export workflow.
2. Open `scenes/main.tscn` and Run Current Scene. Start with H/V=128/128 and default height 26/frequency .022. Hybrid and M5.1 are the shipped scene defaults.
3. Tap **Mountain tour →** to visit the showcase sites. It applies the labelled resource and seed, enables Hybrid, retains the current M5/M5.1 comparison selection and does not increase H/V. Its camera distance is capped at .75×H for the owner's current streaming budget.
4. At each site tap **Mountains: M5.1 / Mountains: M5** to compare morphology without moving the camera. Both orbit and free-flight pose preservation are tested. Wait for generation/water after each rebuild.
5. **Terrain: Hybrid / Legacy** remains the separate M5 representation control. The mountain comparison button is disabled in Legacy because refinement is only applied in Hybrid. The M4 lake button still selects its explicit legacy demonstration.
6. Open `scenes/smooth_terrain.tscn`, Run Current Scene and repeat with the same controls/settings. It consumes the same density.
7. To reproduce normal gallery-scale poses, cautiously try H/V=160/160 after the 128 baseline. The distant gallery uses H=256 and is optional/heavier; the tour will otherwise keep a closer safe-budget view. Do not assume those larger settings are suitable for the target device.
8. To tune styles, stop, select World, expand its config, and edit `mountain_profiles` resources in the Inspector. Regenerate/re-run to obtain a fresh snapshot. See Architecture/MOUNTAIN_MORPHOLOGY.md for adding a new style.
9. Check orbit/pinch/pan, flight MOVE/LOOK/UP/DOWN/BOOST, numeric controls, Regenerate/Random and background/resume. Record loading stalls, frame-time spikes and memory behaviour separately from appearance. Owner validation of **M5.1**, not M5, is still needed.

## 12. Limitations and scope

- Deliberately sharp alpine/rugged crests still exist; this is not universal summit flattening.
- The eight-voxel geographical grid can still produce facets. Vertical C1 curves do not make the entire world globally C1.
- Mountain mass distribution changes markedly in the demonstration region; more multi-seed aesthetic review is warranted.
- Local detached solids/cavities and single-material smooth rendering remain inherited M5 limitations.
- Finite view bounds/distant LOD, coarse water and the unresolved M4 hydrology work remain.
- Cold generation remains an Android hitch risk. No measured Android M5.1 budget is claimed.
- No climate, biomes, trees, foliage, weather/clouds, hydraulic/thermal erosion, cave networks, structures, NPCs or gameplay was implemented.

## 13. Files and documentation

Core additions: `src/core/landforms/mountain_morphology.gd`, six `.tres` resources and `src/debug/mountain_showcase.gd`.

Modified runtime: LandformProfile, MountainModule, SurfaceModule, WorldConfig, MainScene, DebugPanel and `scenes/main.tscn`. The inherited smooth scene, TerrainDensity, LandformProfiles' original evaluator, DrainageNetwork and both adapters remain structurally unchanged.

Validation additions: `tests/suites/m51_morphology_suite.gd`, `tests/m51_{probe,transect,lakes,measurements,showcase}.gd`; runner/capture harness updates. Documentation: diagnosis/research, `Architecture/MOUNTAIN_MORPHOLOGY.md`, ADR-0020, continuation/landform overview updates and this report. The final manifest enumerates exact files, byte sizes and hashes.

## 14. Acceptance boundary and next work

The implementation targets all fifteen requested engineering criteria, with actual parameter tests and fixed-camera evidence rather than compilation alone. Final validation below records exactly which captures/tests completed. Android Editor acceptance and subjective art-direction approval remain with the owner. No visual parity with Vintage Story or heavily modified Minecraft is claimed.

Next work should prioritize cold-generation cost and device measurements, broader multi-seed morphology review, then the already-open M4/M5 water, material, topology and distant-streaming issues—not additional unrelated terrain systems.


## 15. Final executed validation and remaining acceptance

- Full display-backed regression: **423 PASS across 11 suites, exit 0**, no skipped suites, script/parse errors or leak messages. Breakdown in runner order: 17, 57, 63, 29, 30, 46, 44, 27, 24, 41, 45. Log: `m51-evidence/tests-linux.txt`. Registry rejection tests intentionally emit four ERROR diagnostics; unsupported VSync and native task-drain warnings remain.
- First full attempt is preserved in `tests-first-full-attempt.txt`: one voxel assertion incorrectly assumed floor(carved H) must be grass in Hybrid. The corrected test compares all original above/below/base sample locations against exact shared-density material values. This changes the oracle to the actual volumetric contract, not a relaxed tolerance. Targeted recheck: 27 PASS. M5/M5.1 scene tests now wait two process frames before teardown to allow deferred sky initialization; targeted 46/44 PASS and final full run contain no texture leaks.
- All **40** Compatibility captures completed with readiness true, save=0 and capture process exit 0. Gallery builder validates ten identical-camera groups, filenames and image dimensions. Direct contact-sheet inspection confirms blocky/smooth labels match their representations. Two additional refined-massif Mobile-renderer captures also passed central readiness.
- `M051_VISUAL_COMPARISON.html` is a self-contained offline viewer with ten cases and renderer switching. Original PNGs remain authoritative; embedded JPEG previews are compressed.
- Clean sampling and paired lake inventory were executed without a competing capture renderer. Earlier contended timings are preserved separately and are not used as final performance figures.

**Not a full milestone acceptance:** the massif has visibly broader connected summit mass, but the rounded case still has a steep tower-like silhouette. Macro facets, detached fragments and finite water/streaming edges remain exposed. These images demonstrate a real change, not satisfactory completion of every requested natural landform. Further rounded-range and multi-seed visual refinement is needed, together with owner Android Editor performance/appearance validation. Do not mark M5.1 fully complete on the basis of the passing suites.
