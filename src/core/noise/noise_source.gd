class_name NoiseSource
extends RefCounted

## Abstract source of a deterministic 2D scalar field.
##
## Contract for every implementation [b]and[/b] every subclass:
##
## [b]Pure.[/b] [method sample_2d] must be a pure function of its arguments and of
## configuration that is frozen before generation starts. The same (x, y) must
## always give the same value, for the whole life of the object.
##
## [b]Thread-safe.[/b] Voxel Tools calls generators from worker threads, so a
## single instance may be sampled concurrently. Implementations must not mutate
## state inside [method sample_2d] (no memoisation, no counters, no RNG draws).
## Configure in [method _init] only, never afterwards.
##
## [b]Coordinate based.[/b] The output must depend on the absolute world
## coordinate and not on the block currently being generated. This is what makes
## terrain continuous across block boundaries and independent of generation
## order.
##
## This indirection exists so the terrain height field is not welded to one noise
## implementation. Replacing simplex noise with a custom or native field
## requires a new subclass only; callers do not change.

## Returns a scalar in the range [-1.0, 1.0] for a world coordinate.
func sample_2d(_x: float, _y: float) -> float:
	push_error("NoiseSource.sample_2d() is abstract and must be overridden.")
	return 0.0
