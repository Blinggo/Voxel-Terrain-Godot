class_name TerrainHeightField
extends RefCounted

## Height field for M0.1: a single band of layered noise mapped to world height.
##
## This is intentionally the simplest possible surface model that still produces
## real, continuous, seed-dependent terrain. It exists to prove the pipeline
## works end to end; it is not the climate/hydrology/biome architecture, and it
## is not designed to be one. Later systems can replace or wrap it without
## touching the voxel integration layer, because that layer only calls
## [method get_surface_height].
##
## [b]Deterministic and order independent.[/b] The height of a column depends
## only on its absolute world (x, z). It does not depend on the block being
## generated, on neighbours already generated, or on which thread asks. This is
## the property that guarantees generation seams cannot exist: two adjacent
## blocks compute the same value for the voxels they share.
##
## [b]Thread-safe.[/b] No mutable state. Safe to call from several worker
## threads at once, which is what Voxel Tools does.

var _noise: NoiseSource
var _base_height: float
var _height_amplitude: float


## [param noise] supplies the underlying scalar field.
## [param base_height] is the average surface height in voxels.
## [param height_amplitude] is how far the surface may deviate from
## [param base_height], in voxels, in each direction.
func _init(noise: NoiseSource, base_height: float, height_amplitude: float) -> void:
	assert(noise != null, "TerrainHeightField requires a NoiseSource.")
	_noise = noise
	_base_height = base_height
	_height_amplitude = maxf(height_amplitude, 0.0)


## Surface height of the column at world coordinate ([param x], [param z]),
## in voxels. Fractional: a value of 10.4 means the topmost solid voxel of that
## column is the one at y = 10.
func get_surface_height(x: int, z: int) -> float:
	# NoiseSource contract: range [-1, 1], pure, coordinate based.
	var n := _noise.sample_2d(float(x), float(z))
	return _base_height + n * _height_amplitude


## Convenience wrapper for callers holding a 2D vector.
func get_surface_height_at(column: Vector2i) -> float:
	return get_surface_height(column.x, column.y)


func get_base_height() -> float:
	return _base_height


func get_height_amplitude() -> float:
	return _height_amplitude
