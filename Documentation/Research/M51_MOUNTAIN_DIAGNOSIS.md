# M5.1 diagnosis — recorded before implementation changes

The Android owner confirms M5 runs; summit appearance is the reported defect. This is not a measured Android speed result.

Inspected actual files: `mountain_module.gd` (class MountainModule, registry ID mountainness), `tectonics_module.gd` (TectonicsModule), SurfaceModule, LandformProfile(s), TerrainDensity, WorldConfig and GenerationEngine. Names differ from the brief's MountainnessModule/TectonicModule; no duplicate classes are needed.

## Causal chain

1. MountainModule's primary ridge is three-octave ridged smooth Simplex at .006, transformed with smoothstep(.36,.84). The secondary ridge is two octaves at 3.2 times that frequency. The narrow high-frequency ridge structure and max(spine,secondary) produce localized crests and derivative discontinuities at component switches.
2. The broad apron is only .26 of the raw-spine tail. Structural band base .42 provides continuity, but neither crest nor shoulder widths are configurable. Tectonics correctly locates uplift/rifts; it is not itself a summit-shape model.
3. SurfaceModule multiplies mountainness by 1.8×26. M5 then weights mountain/alpine profiles increasingly strongly with the same mountainness: range relief 1.65 and alpine relief 2.2, plus ridge contributions 6m/12m and uplifts 8/15. This reinforces high points relative to their flanks. A profile's slope_sharpness=1 is just a relief exponent, not a summit-width control.
4. There are no vertical shape keys or independent lower/middle/upper/summit controls. Ten profile labels therefore do not provide ten summit geometries.
5. GenerationEngine evaluates at stride 8 then bilinearly interpolates. A high node surrounded by lower nodes becomes a faceted pointed apex; high-frequency crest contributions have too few samples to describe a broad cap. Merely raising sampling resolution would be costly and would not supply missing mountain mass distribution.
6. TerrainDensity's structure term carves at depths 1–24, with zero structural contribution at the base surface itself. Its small geological/fine displacements can alter local surfaces but cannot explain the large, consistently pointed mountain silhouette. Disabling density would not address the dominant source of the defect.

## Intended corrective approach

Keep tectonics, bounded regional evaluation and all shared density/adapters. Retain an exact M5 morphology switch. Separate a low-frequency wandering crest from secondary detail; use independently parameterized crest, shoulder and foothill cross-sections, smooth component composition, connected cols, and a continuous monotone vertical threshold curve. Preserve peak-scale amplitude instead of lowering terrain_height/mountain_scale. Six styles are resources evaluated by one shared function. Reuse existing noise streams; do not add 3D evaluations.

This diagnosis is source-based. Subsequent parameter-effect, height-distribution and fixed-camera results must demonstrate whether the remedy actually works; source inspection alone is not visual acceptance.

## Render/transect refinement before composition change

The first broad-profile renders still contained narrow tall peaks. A forced-massif transect at z=-1360 showed broad mountainness of .84–1.04 across x=-80..0, yet base heights jumped from 77 to 145. Valleys reached 1.43, and plateau masks changed from 0 through .33 to 1. Thus the mountain field alone was not the remaining cause: M5's post-carve gain/weight changes amplified surviving high nodes and removed their shoulders. `m51-evidence/transect.txt` records these values; the first comparison images are retained under `initial-composition/`.

The refined SurfaceModule path now calibrates mountain relief before carving, excludes plateau interiors smoothly from established mountain cores, and blends that result into the existing ten-landform composition through mountainness. It does not apply the M5 peak-dependent gain twice. This preserves lowland/plateau composition and the old M5 branch while giving the morphology evaluator control over the actual mountain cross-section. The 2.35 relief calibration substitutes for M5's former 1.65–2.2 profile gain plus uplift/ridge bonuses; it is not the morphology mechanism itself.
