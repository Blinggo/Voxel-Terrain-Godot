# ADR-0020 — Resource-defined mountain cross-sections and vertical profiles

Status: implemented; platform/visual acceptance recorded in the M5.1 report.

## Context
The Android owner confirmed M5 runs but found excessively pointed summits. Source inspection identified narrow ridge structure plus post-carve profile gains and coarse interpolation. The first width-only trial and its renders showed that changing MountainModule alone did not remove isolated tall peaks: plateau/valley composition could recreate them.

## Decision
Extend the existing LandformProfile resource with morphology/vertical controls and use one MountainMorphology evaluator in MountainModule. Retain tectonic location/rifts, the old M5 branch and all shared density/adapters. Use a low-frequency smooth primary crest coordinate, separate summit/shoulder/foothill cross-sections, existing secondary/province signals and normalized resource blending. Calibrate mountain relief before valley/plateau shaping, rather than applying mountain-dependent gains to an already carved height.

Use strictly increasing vertical threshold/elevation pairs with continuous monotone cubic interpolation. Keep summit height independent from width controls. No new 3D sampling, cache or runtime dependency. Default six resources can be replaced/extended through WorldConfig without editing unrelated modules.

## Consequences
Terrain identity includes the refinement flag and resource configuration. Hydrology may reroute because the base changes. Broad mountain mass is intentionally increased; existing lowland composition is blended back below the mountain envelope. Mathematical summit continuity does not remove the existing coarse sampling facets. The added profile arithmetic increases cold generation cost despite fewer primary noise octaves; measurements and Android Editor testing remain mandatory.

## Rejected alternatives
Lowering terrain_height; arbitrary high-frequency noise; separate smooth geography; six independent generators; global supersampling; proprietary implementation copying; hydraulic/thermal erosion; and accepting a width-only change that still rendered narrow peaks.
