# ADR-0009 — Measure frames, memory and named phases; never invent statistics

**Status:** Accepted
**Date:** 2026-11-07

## Context

Optimisation without measurement is guesswork, and the next milestone candidates
(climate, hydrology, erosion) all add per-block work that must be affordable on a
phone. The overlay already reported a status snapshot; it reported nothing about
cost.

Two constraints shaped the design. The debug overlay is the only place such
numbers belong, and it must stay removable — no autoloads (ADR-0007) and nothing
in `src/core/`, `src/voxel/` or `src/world/` may depend on profiling. And Voxel
Tools 1.7x exposes far less than one would like: `VoxelTerrain.get_statistics()`
returns seven keys, with no block counts and no per-block generation timings.
Anything displayed has to be something that actually exists.

## Decision

`PerformanceSampler` (`src/debug/performance_sampler.gd`) is a `RefCounted` owned
by `DebugPanel`:

- **frame timing** over a rolling 1 s window: fps, average frame time, maximum
  frame time (`sample(delta)` every frame — the maximum is meaningless otherwise);
- **Godot memory and object counts** via `Performance.get_monitor()`;
- **pass-through** of `VoxelTerrain.get_statistics()`, unmodified;
- **named sections** via `record_section(name, ms)`, with last/average/max per
  name. Phase timing is deliberately generic: a generation module records its own
  phase and the overlay shows it with no new code.

`VoxelWorld.rebuild()` reports its own main-thread duration through
`get_status()["last_rebuild_ms"]`; the world is the only place that knows when a
rebuild begins and ends.

Display is four 11 px lines, refreshed on the overlay's existing 0.25 s cadence,
toggled with **F4** or `set_profiling_enabled(false)`. Disabled means sampling
stops entirely, not that the label is hidden.

**Nothing is displayed that the extension does not provide.** Missing keys render
as `-`. `updated_blocks` is known to be dead in 1.7x and is not shown.

**Godot memory is not process memory.** The overlay reports Godot's static
allocator and object counts. Device RSS requires `adb shell dumpsys meminfo` and
the two are never presented as interchangeable.

## Consequences

- Costs a few float operations per frame plus three monitor reads per 0.25 s;
  zero beyond a boolean test when disabled.
- Frame time is measured, not attributed: the sampler does not say *where* the
  time goes. That needs a profiler, and this ADR does not pretend otherwise.
- `tests/suites/perf_suite.gd` pins the arithmetic (window closing, maximum,
  disabled state) and the statistics schema, so a Voxel Tools upgrade that
  renames a key fails a test instead of silently showing `-` forever.
- If block counts become available upstream, they are added by extending the
  pass-through; no other layer changes.
