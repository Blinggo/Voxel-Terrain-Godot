# ADR-0007 — No autoload singletons; wiring belongs to the scene

**Status:** Accepted
**Date:** 2026-11-06

## Context

Godot projects drift towards autoloads that everything reaches into, which makes
systems impossible to instantiate twice and impossible to test in isolation.

## Decision

No autoloads. Three plain participants, wired by the scene root:

- `VoxelWorld` — owns terrain lifetime and generation state;
- `OrbitCamera` — owns the view and carries the `VoxelViewer`;
- `DebugPanel` — owns the debug UI and emits intent.

`main_scene.gd` holds the only knowledge of all three. Its responsibilities are
limited to connecting signals, forwarding a regeneration request into a
`WorldConfig`, and refreshing the status display.

The one shared lookup in the project is the `voxel_viewers` node group, used so
`VoxelWorld` can push streaming settings to a viewer it does not own, without
the world needing a reference to the camera.

## Consequences

- Tests instantiate the real `main.tscn` (or a bare `VoxelWorld`) directly, with
  no global setup and no teardown ordering problems. The benchmark does exactly
  this.
- The debug panel can be deleted without touching generation code.
- A second world is one more instance, not a configuration flag.
