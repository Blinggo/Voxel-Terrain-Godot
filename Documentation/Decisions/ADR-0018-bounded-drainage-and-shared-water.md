# ADR-0018 — Bounded source-to-terminal drainage and shared water

Status: implemented foundation; overflow lake routing remains open.

## Decision
Extend the existing registry with hydrology (v1, dependency surface), retain the existing generation engine as the pre-carve source, and apply spatial shaping through GeographicSurface. Reconstruct complete bounded D8 source routes from absolute coordinates. Reject an entire unsupported/over-budget route rather than cutting it at a tile edge. Cache query indexes, never authoritative world state. Use enclosed connected-sublevel lakes below a minimax-measured saddle.

## Why
A full world raster and unbounded walk-to-ocean violate random-access performance constraints. Independent finite raster tiles with artificial edge outlets create false rivers at boundaries. Noise-only channels do not establish flow direction or meaningful sources. Complete bounded source support gives a finite halo and repeatable adjacent-region reconstruction.

## Consequences
Both existing adapters are unchanged. Rivers are short/local, with source-count accumulation rather than global drainage area. Unaccepted catchments are absent, and basin overflow is not yet solved. The 8-voxel lake raster and four-chord river approximation are visible quality limits. These are not to be presented as a complete watershed simulation.

## Ownership and performance
A measured repeated-column hotspot justifies a 512-entry final 16²-height cache. Registry back-references and the drainage engine link are weak to avoid RefCounted cycles. Native terrain is freed while attached to avoid out-of-tree transform lookups during teardown. See the M4 report for executed tests and platform-separated measurements.
