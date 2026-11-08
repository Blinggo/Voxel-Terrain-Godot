# M4 hydrology architecture

## Status
Working bounded drainage and closed-basin lake implementation. **Overflowing/connected lake chains and dedicated river terraces are not implemented.** This is not a complete global hydrological simulation or a fully completed M4 brief.

## Layering
```
existing GenerationContext + registry + GenerationEngine
    -> existing uncarved coarse/fine surface (all M1/M2 modules)
    -> registered HydrologyModule (id hydrology, version 1, dependency surface)
         -> DrainageNetwork: deterministic routes, accumulation, lakes, spatial indexes
    -> GeographicSurface: apply river/valley shaping; expose water queries
         -> unchanged blocky adapter -> type voxels -> blocky mesher
         -> unchanged smooth adapter -> float SDF -> Transvoxel
         -> HydrologyWaterView -> shared diagnostic water mesh
```
There is no second terrain-generation stack or duplicate mountain/elevation generator. Drainage reads the **same engine's pre-carve columns**. It does not read its own carved result and cannot create feedback recursion. `HydrologyModule.evaluate_node` writes `runoff_potential` (source eligibility), not river geometry. Its spatial network is applied by GeographicSurface after the existing coarse/fine column stage. The engine and voxel adapters do not perform pathfinding.

The pipeline keeps generation_version 2 so the existing geographical random streams do not shift. Adding hydrology deliberately changes final heights when enabled. Hydrology has its own version-1 context-derived seed. Disabling it restores pre-carve geometry; changing seed/version or source parameters reconstructs everything.

## Source placement and routing
- Absolute 128-voxel source parcels. A coordinate hash selects one of the parcel's 32-voxel lattice nodes; no mutable RNG.
- A candidate must be at least `sea_level + hydrology_source_rise` (default 14). This is an elevation eligibility model, not precipitation or measured runoff.
- Route with steepest descending D8 neighbour on actual uncarved geography. Heights include the existing valleys, basins, hills and mountains. A strict positive drop and fixed neighbour order prevent cycles/tie instability.
- At/below sea level: ocean terminal. At a local minimum: attempt a validated enclosed lake. A missing/invalid lake does not become a dry river endpoint.
- **Accept only complete routes**, at least three nodes, reaching a valid terminal within 16 edges. Otherwise reject the entire source route. The budget never clips an accepted river in mid-land. This limits system length and omits long catchments; it is not an infinite river solution.
- Tributaries share the same downstream receiver at each node. Count accepted source contributions at nodes (not global raster rainfall accumulation, and not Strahler order). Counts and widths are nondecreasing downstream for the reconstructed accepted network.

## Spatial reconstruction and boundaries
128-voxel tiles are only cache/index windows. They do not own sources, sinks or flow directions. Candidate source parcels cover the tile plus a conservative halo: `16*32 + 128 + 48 = 688` voxels, expanded from the tile's influence rectangle. This covers maximal per-axis route travel, basin extent and channel/bank influence.

Every queried tile reconstructs complete source routes, merges canonical coordinate-keyed reaches, and indexes the same curves. A shared reach's flux includes all possible contributing accepted sources within the bounded support. Neighbouring tiles need no generated voxel neighbours and exchange no mutable boundary state. Fixed enumeration order makes reconstruction deterministic after eviction.

Cubic reach curves use endpoint tangents derived from downstream routing; four chords approximate each curve. Shared endpoints and tangents agree. Native D8 lattice direction bias and four-chord faceting are still visible; this is not a natural-meander simulation.

## Basin lakes
At a D8 sink, sample an 8-voxel raster inside ±128 voxels (33² samples). A binary-heap minimax search computes the lowest escape cost to the finite search perimeter. Water level is at most 12 voxels above the sink and 0.2 below the measured spill level. An 8-connected sublevel flood must be fully enclosed and contain at least three sample cells. A component touching the perimeter is rejected/retried at a lower level; a square region boundary is never accepted as a shoreline.

Actual water queries additionally require the underlying terrain to be below water. The lake plane is constant per body and follows connected depressed terrain, not a circular radius mask. Shore membership is resolved on the coarse raster; sub-grid saddle leakage and visible shoreline stair-stepping remain limitations. This is not proof of enclosure at every voxel.

**No spill outlet is routed.** The saddle is measured, but these lakes are retained below spill as endorheic bodies. Large connected lake chains, overflow/breaching and outlet rivers must be added before the full M4 lake requirement can be considered satisfied.

## Geometry and waterfall data
- Half-width: `min(8, 1.5 + sqrt(source_count)) * width_scale`; width scale clamped to 0.5–1.25 to preserve the finite influence bound.
- Depth: `1.5 + 0.3*half_width`.
- Water profile: descending interpolation of endpoint terrain heights minus 0.5, backed up to the terminal water level where necessary.
- Floodplain/valley support: `half_width * (2 + 2/(1 + reach_drop))`, narrower on steep reaches. Smooth transitions blend from carved bed into original terrain and never raise it.
- A reach drop ≥8 with average gradient >0.2 flags a waterfall candidate. Its profile concentrates the drop into the middle half of the reach; data includes `waterfall`, `drop`, endpoints and levels. These are geographical steep-drop candidates, not an animated falling-water renderer or independently simulated discharge.
- Dedicated stepped river terraces, erosion, sediments, distributaries and oxbows are absent.

## Public interface
`GeographicSurface.get_water_at(x,z)` returns:
- `kind`: dry / ocean / river / lake
- `water_height`: world-space level; -INF when dry
- `ground_height`: shaped ground
- `river_width`: full width (zero for non-river bodies)
- `body_id`: ocean, lake coordinate identity, or reach coordinate identity (scoped to world/config)

`get_drainage().tile_at(column)` exposes read-only `segments` and `lakes` for diagnostics/rendering. Each segment includes endpoint levels, width, source-count flux and waterfall data. `inspect_routes(parcel_rectangle)` returns deep copies for tests. `get_unmodified_height` / `sample_unmodified_heights` expose the shared pre-carve terrain. Both voxel adapters continue calling the same final surface interface.

## Caches, allocation, threading
| Cache | Limit | Eviction/reconstruction |
|---|---:|---|
| Drainage index tiles | 32 | oldest insertion removed; complete halo reconstruction |
| Source routes | 1024 | clear and deterministically rebuild |
| D8 nodes | 8192 | clear and resample the same engine |
| Basin records | 512 | clear and reconstruct bounded minimax/flood |
| Final 16² shaped columns | 512 | oldest insertion removed; ~512 KiB float payload |
| Existing engine nodes | 8192 | unchanged M1 strategy |

A network mutex serializes cold preprocessing and cache publication. Published tiles are treated as immutable after release. Per-column shaping uses 16-voxel spatial bins, no route search, and a small packed result. The final-column cache was added only after measuring repeated shaping for vertical blocks at ~1.7 ms/block; arbitrary larger rectangles are not cached. A caller must not mutate returned cached structures.

Preprocessing allocates bounded dictionaries, path arrays, a 33² basin grid and its bounded priority queue. Tile bin lists share segment dictionaries. These structures are larger than their packed float payloads; use measured process/runtime allocation rather than assuming the cache table alone describes total memory. Cache bounds are structural, not an assertion that Android memory has been validated.

Registry/module reference cycles are fixed with a weak registry back-reference. Drainage holds a weak engine reference; surface/stack own the engine. Four-worker column comparison is executed. Network preprocessing may cause cold-start contention; it is not lock-free.

## Shared water visualisation
HydrologyWaterView uses one background Thread at a time to build 2-voxel-spaced water triangles from the same water query mathematics. Mesh upload and scene changes occur only on the main thread. Ocean remains the existing sea plane. Rebuild joins any active water task before releasing its surface.

Default horizontal radius 128 requests a 3×3 group of 128-wide water mesh tiles. Tiles outside the viewer window are freed. A minimal material shader clips water conservatively inside horizontal/vertical streaming radii minus 16 voxels so full water tiles do not draw over unloaded shores. This is a simple material, not compute generation or a fluid simulation. Water can visibly clip at the view boundary and appear later than terrain. Narrow headwaters and shoreline fragments may be missed by the 2-voxel diagnostic mesh, especially in blocky mode. Geometry/data remain shared across both scenes.
