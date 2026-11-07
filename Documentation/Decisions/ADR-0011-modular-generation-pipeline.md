# ADR-0011 — Terrain is a pipeline of registered single-field modules

**Status:** Accepted
**Date:** 2026-11-07
**Supersedes (implementation):** ADR-0003 — the height-field *rule* survives, the
`TerrainHeightField`/`NoiseSource` objects it described do not.

## Context

M1 replaces the single noise band with several geographic fields
(continentalness, elevation, mountains, hills, a composer and a detail term) and
must keep room for climate, hydrology, erosion and vegetation later. The
requirements are explicit: module identification, registration, configuration,
declared dependencies, deterministic execution order, optional modules,
independent testability, configuration snapshots, and extension without touching
unrelated modules — with no significant per-voxel overhead.

Two designs were considered:

- **One big generator function** that computes every field inline. Fastest to
  write, and fastest at runtime, but every new field edits the same function, no
  field can be tested alone, and ordering is implicit.
- **Module objects with declared wiring**, executed by an engine.

## Decision

Terrain generation is a pipeline of `GenerationModule` objects. Each module:

- owns exactly **one scalar field** and declares `id`, `version`, `dependencies`
  and `output_field`;
- is configured once per build from a `GenerationContext` (seed, generation
  version, frozen `WorldConfig`), and from then on only reads;
- writes its field through `evaluate_node(x, z, values)` at a shared node grid;
- may opt into a full-resolution `add_columns(heights, origin, size)` bulk term.

`GenerationRegistry` resolves execution order from the declared dependencies
(Kahn's algorithm, registration order as tie-break, so the order is platform
independent) and refuses duplicate ids, duplicate fields, unknown dependencies and
cycles. `TerrainGenerationStack` is the single registration point.

Module ↔ module coupling is only ever through a declared dependency, resolved to a
field slot at build time. A module that reads a field it did not declare is
reported rather than silently reading a stale slot.

## Consequences

- Adding a field is one class plus one registration line; existing modules keep
  producing bit-identical values (tested, not assumed).
- Each field is independently testable with no engine, no world and no voxel
  tooling (tested: a module configured and evaluated standalone).
- Ordering is data, not code: the registration list is presentational.
- Cost: one virtual call per module per node. Measured against a monolith this is
  a few percent of block time, not a per-voxel cost, because nodes are 8 voxels
  apart and there are six modules.
- One field per module is a deliberate limit. Climate will need temperature and
  humidity; either split them across modules or extend the contract — a decision
  for that milestone, recorded here so it is not discovered late.
- ADR-0003's determinism *rule* (surface is a pure function of absolute
  coordinates) is unchanged and still the thing that makes seams impossible.
