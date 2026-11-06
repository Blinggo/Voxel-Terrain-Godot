# ADR-0001 — Engine and extension versions

**Status:** Accepted
**Date:** 2026-11-06

## Context

M0.1 mandates Godot 4.7.2 and Zylann Voxel Tools 1.7 as a GDExtension. The
extension ships two release lines that are easy to confuse, and using the wrong
one changes the project fundamentally.

## Decision

Use the **official, unmodified** Godot `4.7.2-stable`
(`4.7.2.stable.official.ed1daf0bf`) with the **standalone GDExtension** from the
Voxel Tools `v1.7x` release (`GodotVoxelExtension.zip`).

The `v1.7` release is *not* used: it is a prebuilt editor binary with Voxel
Tools compiled in as a custom engine module, which the milestone explicitly
excludes.

Both versions are pinned in `Documentation/Milestones/M00_01_PROJECT_FOUNDATION.md`
along with the checksums of what was actually installed.

## Consequences

- The project stays portable: it runs on any stock Godot 4.7.2, and the engine
  can be upgraded independently of the extension.
- The extension declares `compatibility_minimum = "4.4.1"`, so 4.7.2 is inside
  its supported range (verified loading, not assumed).
- Because the extension is a GDExtension, terrain generation from GDScript
  crosses the script/native boundary; this is the known cost of not using a
  custom module, and it is measured in the test report.
