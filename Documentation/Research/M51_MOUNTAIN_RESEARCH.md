# M5.1 — focused public-source research

## Terrainy (MIT)
Repository https://github.com/fabian-becker/Terrainy, inspected revision `98f42ff4463f14bc89798020670e13149eaf2f14`. Licence and inspected files are retained under `m51-source-evidence/` for research, not used as runtime dependencies.

Read `addons/terrainy/nodes/landscapes/mountain_range_node.gd` and `landscape_evaluation_context.gd`. The implementation separates lateral distance from position along a ridge, displaces the crest laterally with low-frequency noise, stacks a narrow Gaussian core over a broader skirt, modulates peaks/cols along the crest, adds flank ridgelets/gullies with anisotropic sampling, and tapers finite influence bounds. Evaluation contexts capture transforms, extents and noise references for workers.

Useful mathematical ideas: independent crest/skirt/foothill widths; retain elevated col floors rather than cutting ranges into isolated peaks; separate large mass from detail; use smooth influence masks and snapshots. Our implementation uses the existing warped primary noise's zero contours as an implicit crest coordinate, not Terrainy's finite axis-aligned feature-node system. It independently combines three cross-sections and reuses existing secondary/province fields. It does not copy Terrainy's coefficients, source, GPU parameter packing or full feature architecture. Our gully modulation is not simulated erosion.

## FastNoiseLite (MIT)
Repository https://github.com/Auburn/FastNoiseLite, revision `785f37a9ad76e283586a379675085f2063ae03f7`. Inspected licence and `Cpp/FastNoiseLite.h`, including `GenFractalFBm`, `GenFractalRidged` and domain-warp dispatch/accumulation.

FBm sums signed octave contributions with changing frequency and amplitude; ridged fractals fold the signal with absolute values and accumulate ridge contributions. Progressive warp compounds successive coordinate changes; independent warp avoids feeding each displacement back into the next octave's input. These are different shape/cost decisions, not interchangeable detail switches.

M5.1 retains Godot's existing implementation and hashed streams. It uses one smooth-Simplex octave for the primary crest coordinate rather than three-octave ridged noise, keeps existing secondary ridged detail, and slows/reduces the existing bounded two-component warp. Secondary frequency multiplier changes from 3.2 to 1.4; warp frequency multiplier from 1.3 to .55 and amplitude from 120 to 60, only in refined mode. Large-scale crest organization is therefore not repeatedly cut by nearly grid-scale detail. No added 2D noise calls, no added 3D noise, no new noise dependency. Six FastNoiseLite API calls per mountain node remain, with fewer primary octaves. Mathematical morphology evaluation still adds CPU cost and is measured separately.

## Vintage Story landform configuration
Source: https://wiki.vintagestory.at/Terrain_Generation (retrieved for this task). Its Landforms section explicitly lists required octaves, octave thresholds, terrain Y key positions and terrain Y key thresholds; it describes octaves as controlling rough/smooth character. The page does **not** establish a complete sign convention or interpolation formula for those thresholds. No proprietary implementation or game assets were copied, nor were linked implementation repositories treated as permissively licensed by assumption.

Useful idea: make vertical occupancy/shape response landform data rather than assuming that every mountain is one amplitude-scaled ridge. We independently define strictly increasing normalized threshold-versus-height keys, then evaluate their monotone inverse, height(signal). The implementation uses continuous monotone cubic Hermite interpolation with harmonic-mean tangents. Positive slopes prevent overshoot and avoid zero slope at every interior key (which piecewise smoothstep would turn into artificial shelves). This is our explicit mathematical convention, not a claim to reproduce Vintage Story's exact algorithm.

Lower, middle, upper and summit regions are configurable through the key pairs. Density remains downstream: vertical morphology shapes the base terrain before drainage and does not replace M5's solid/air function. Landform keys and mountain widths can be configured independently. Different default resources use different height-key positions.

## Reuse and limits
Both inspected code repositories have verified MIT licence texts; any copied code would require retaining their notices. There is no source reuse in runtime here. Archived research files retain their licence evidence. No documented upstream FPS figure is transferred to this GDScript/Android project. The source-based diagnosis was recorded separately in `M51_MOUNTAIN_DIAGNOSIS.md` before implementation. No visual parity claim, hydraulic/thermal erosion, climate, vegetation or caves follows from this research.
