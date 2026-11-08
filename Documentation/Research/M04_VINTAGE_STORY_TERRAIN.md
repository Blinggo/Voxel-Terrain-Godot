# M4 research — Vintage Story terrain and transferable design ideas

## Scope and evidence discipline
This is algorithmic/visual study, not copied implementation. No Vintage Story assets, landform JSON, mod source, textures or code are included. The two landscape images described in the brief were not present in this workspace; its sole uploaded image was an earlier storage-warning screenshot. Therefore the user's descriptions remain the reference brief, not images claimed to have been inspected.

Read the official/community wiki pages and mod descriptions below. Inspected the Terra Prety mountain/shore landscape linked from its mod page (`mng_ad2_5f510ee5bc98a9e42862a1f3e4986249.jpg`). A second image turned out to advertise flowers and was not used as evidence for terrain quality. No gameplay video was watched. Visual observations below are not proof of an implementation algorithm.

## What the sources actually establish

- The wiki describes staged generation: property noise maps → landforms → geology/strata → further world-generation passes. Landform and geological-province maps are distinct. Landform selection uses a landform map; geological provinces influence rock strata. Do not equate geological provinces with a documented tectonic simulation. [4](https://wiki.vintagestory.at/Terrain_Generation)
- Landform definitions control octave amplitudes/thresholds and vertical key positions/thresholds. Low-frequency octave contributions describe broad changes; high-frequency contributions describe roughness. Octave thresholds suppress portions of an octave, rather than making every part of a region equally noisy. The vertical keys describe a density profile, not simply this project's `height=f(x,z)`. The configuration page contains confusing wording around solid/air threshold polarity; its exact runtime sign is not needed or adopted here. [1](https://wiki.vintagestory.at/index.php/Modding:WorldGen_Configuration)
- [World generation wiki](https://wiki.vintagestory.at/index.php?title=World_generation/en) describes environments emerging from multiple properties rather than discrete biome labels. This does not justify adding climate or biomes in M4.
- [Terra Prety's description](https://mods.vintagestory.at/terraprety) explicitly discusses a coastal map, mountain-range organization, milder continental-interior plains, hillier/mountainous surrounding regions, gentler coastlines and grouped islands. These are claims about the MOD, not proof that vanilla Vintage Story uses that exact organization.
- [Algernon's Watersheds](https://mods.vintagestory.at/algernonswatersheds) describes terrain-aware flow using cheap samples of surrounding terrain, high inland starts, widening streams and tributaries. Its feature list includes much more than M4 implements. Its public description is a conceptual reference only; implementation/source licensing was not established or used.
- [Procedural Unbounded River Generation](https://alcatrazescapee.com/rivers/) distinguishes context-free, bounded and unbounded methods. In particular, “walk until an ocean is found” is not a bounded random-access algorithm. This motivated a complete-route acceptance rule rather than truncated rivers at query boundaries.
- Priority-Flood is a depression-processing algorithm operating on finite DEMs; it uses priority order and can support watershed/flow-direction derivation. M4 implements an independently written *bounded minimax escape search*, not a complete world-wide Priority-Flood drainage solution. [2](https://www.sciencedirect.com/science/article/abs/pii/S0098300413001337)

## Answers to the ten research questions

| Question | Supported finding or inference | Transfer to this project |
|---|---|---|
| 1. How are large regions distinguished? | Documented landform map selects parameterized forms; provinces separately affect strata. Terra Prety describes additional macro organization. | Preserve continental/tectonic fields; later add slow-varying landform weights rather than choosing a whole new generator. |
| 2. Plains → foothills? | The mod describes plains surrounded by hillier regions; published descriptions do not specify an exact transition equation. | Proposed smooth weight ramps that first increase medium-scale relief, with fine detail still suppressed. This is a design recommendation, not attributed VS code. |
| 3. Foothills → ranges? | Landform octave/density controls permit different scale mixes; Terra Prety separately organizes long mountain ranges. | Combine existing connected-range placement with a broad apron and spatially varying relief budgets. Do not merely add more ridged octaves. |
| 4. Broad valleys? | The sources inspected do not establish one universal vanilla valley algorithm. | M4 widens corridors based on contributing source count and reach slope. Later use catchment-scale valley envelopes, not constant-width flat trenches. |
| 5. Mountain basins? | Observed landscapes combine high relief with low enclosed spaces, but pictures cannot establish whether erosion, density profiles or authored forms produced them. | Use actual pre-hydrology elevation depressions, with an explicit basin/spill test. Do not place circular bowls randomly. |
| 6. Lakes in depressions? | Wiki lists pond generation but its technical pond section is sparse; no precise vanilla lake algorithm was established. | M4 directly tests connected low terrain below a locally measured saddle. Overflow routing is still missing; do not claim it from research alone. |
| 7. Avoid repetitive mountain noise? | Parameterized scale mixtures and thresholding are documented; mod-level range/coast organization adds structure. | Later vary profile, range width and local relief budgets within a coherent region; keep connected large-scale skeletons. |
| 8. Control different scales? | Octave weights/thresholds separate broad structure from roughness; vertical keys control density shape. | In our height-field model, introduce scale-specific amplitude/curve parameters, not a wholesale VS volumetric density implementation. |
| 9. Coexist without abrupt boundaries? | Descriptions support organic transitions, but the exact vanilla blending implementation was not verified. | Proposed partition-of-unity/smooth weighted transitions with shared base elevation. Evaluate slope as well as height continuity. |
| 10. Interesting distant structure? | Inspected mountain image has an irregular skyline, broad lower apron, flatter foreground and a water basin; distant mountains form larger masses. | Test terrain without foliage, using long-range silhouettes and broad open regions. Do not rely on grass, trees, texture detail or fog to hide geometry defects. |

The landform parameter statements in the table refer to the configuration reference above. [1](https://wiki.vintagestory.at/index.php/Modding:WorldGen_Configuration)

## Selected now, deferred deliberately
**Now:** height-aware bounded drainage; scale-separated river core/bank/valley shaping; connected sublevel basin lakes; one shared water interface; visible diagnostic water in both scenes.

**Later:** richer landform weights/profiles, coordinated catchment-scale mountain basins, broad valley classes, plateau/basin relationships and improved silhouettes. Do not add a complete landform catalogue, vegetation, climate or full erosion in this milestone.

**Licensing:** Wiki prose and mod descriptions were studied, not copied into code. No licence assumptions were made about executable mod source. The drainage implementation was independently written from downhill-routing and minimax-path definitions; the paper/article citations document the concepts. External reference screenshots are not redistributed with the project.
