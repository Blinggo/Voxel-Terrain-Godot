# ADR-0019 — Shared solid field and blended landform parameters

Status: implemented foundation; visual/performance acceptance remains partial.

## Context
M1–M4 produced one carved height per column. M5 requires genuine local volumetric geometry without a second geography for the smooth scene or a replacement world-generation architecture.

## Decision
Keep the existing geographical registry and field streams. Blend ten configurable parameter profiles in SurfaceModule before hydrology. Introduce TerrainDensity after GeographicSurface carving, with negative-inside semantics, deterministic bounded 3D modifiers and shared material classification. Explicitly inject it into either adapter. Retain exact legacy height-derived mode.

Profiles share one normalized evaluator; no hard nearest-type switches. Noise frequencies are global per band, with profile-weighted amplitudes. Structural noise carves steep terrain below the outer surface; unrestricted signed displacement was rejected after it rendered excessive blobs. Conservative masks protect known water beds. No full caves, full-world preprocessing or new runtime dependency.

## Consequences
The carved base height is no longer the final solid boundary in hybrid mode. Live voxel tests must compare against shared density rather than floor(H). Hydrology routes can change when profile composition changes the base terrain; mode/configuration belongs to world identity. Water geometry remains separate. Single-resolution streaming, approximate SDF normals, finite view distance and existing smooth single-material rendering remain explicit constraints.

Measured repeated control evaluation justified a bounded 256×16² packed-vector cache. Conservative interval bounds permit exact uniform material and saturated-SDF writes. The smooth channel saturates at ±32; zero geometry is unaffected. Existing configuration snapshots and deterministic coordinate hashing remain authoritative.

## Alternatives rejected
- Independent smooth noise terrain: violates common geography and comparison semantics.
- Custom Marching Cubes or Terrain3D dependency: duplicates existing extension duties or loses volumetric representation.
- Unrestricted 3D signed noise: rendered blobby/disconnected geometry and damaged landform readability.
- World-wide connectivity cleanup or hydrological simulation: violates bounded random-access scope.
- Claiming completion from compilation or one screenshot: insufficient; retain visual, material, performance and device gaps.
