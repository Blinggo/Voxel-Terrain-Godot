class_name GeographicSurface
extends RefCounted

## The surface a voxel pipeline consumes: heights, plus the fields behind them.
##
## This is the M1 replacement for [code]TerrainHeightField[/code], and it keeps
## the same one-method contract the voxel layer relied on
## ([method get_surface_height]). What changed is what is behind it: a pipeline
## of registered modules rather than one noise band.
##
## [b]Deterministic and order independent.[/b] The height of a column depends only
## on its absolute world (x, z) and on the frozen configuration. Not on the block
## being generated, not on the neighbours, not on the thread that asks. That is
## what makes block seams impossible by construction.
##
## [b]Thread-safe.[/b] Sampling mutates nothing except the engine's node cache,
## which is mutex-guarded and stores values that are pure functions of their
## coordinates. Two threads racing on the same node compute the same number.
##
## [b]Read-only after construction.[/b] Configuration is snapshotted at
## construction; a live [WorldConfig] edit cannot change a surface in flight.

var _stack: TerrainGenerationStack
var _config: WorldConfig


func _init(world_config: WorldConfig) -> void:
	_config = world_config.duplicate_config() if world_config != null else WorldConfig.new()
	_stack = TerrainGenerationStack.new(_config)


func is_valid() -> bool:
	return _stack.is_valid()


# --- Surface -----------------------------------------------------------------

## Surface height of the column at world coordinate ([param x], [param z]), in
## voxels. Fractional: 10.4 means the topmost solid voxel of the column is at
## y = 10.
func get_surface_height(x: int, z: int) -> float:
	if not is_valid():
		return _config.base_height
	return _stack.engine.sample_height(x, z)


## Convenience wrapper for callers holding a 2D vector (x, z).
func get_surface_height_at(column: Vector2i) -> float:
	return get_surface_height(column.x, column.y)


## Heights for every column of a rectangle, row-major, [param size].x per row.
##
## The voxel adapter calls this once per block: the node lookups and the
## interpolation weights are then shared by all columns instead of recomputed per
## column.
func sample_block_heights(origin: Vector2i, size: Vector2i) -> PackedFloat32Array:
	if not is_valid():
		var fallback := PackedFloat32Array()
		fallback.resize(size.x * size.y)
		fallback.fill(_config.base_height)
		return fallback
	return _stack.engine.sample_columns(origin, size)


# --- Fields ------------------------------------------------------------------

## Raw value of one module's field at a coordinate. For the debug overlay and for
## tests that assert on a field rather than on the composed height.
func get_field_at(module_id: StringName, x: int, z: int) -> float:
	if not is_valid():
		return 0.0
	return _stack.engine.get_field_at(module_id, x, z)


## Terrain type at a coordinate, as one of the [method SurfaceModule.classify]
## names: [code]deep_ocean[/code], [code]shallow_ocean[/code], [code]coast[/code],
## [code]mountains[/code], [code]plateau[/code], [code]valley[/code],
## [code]hills[/code], [code]plains[/code].
func classify_at(x: int, z: int) -> StringName:
	return SurfaceModule.classify(
			get_field_at(&"landmass", x, z),
			get_field_at(&"mountainness", x, z),
			get_field_at(&"hills", x, z),
			get_field_at(&"plateaus", x, z),
			get_field_at(&"valleys", x, z)
	)


## Everything the debug overlay and the tests want to know about one place.
##
## [code]continentalness[/code] is the raw layout field; [code]landmass[/code] is
## what the pipeline actually used, after islands and coastline shaping. Both are
## reported because the difference between them is exactly what M2 added.
func describe_at(x: int, z: int) -> Dictionary:
	var continents := get_field_at(&"continentalness", x, z)
	var landmass := get_field_at(&"landmass", x, z)
	var elevation := get_field_at(&"elevation", x, z)
	var mountains := get_field_at(&"mountainness", x, z)
	var hills := get_field_at(&"hills", x, z)
	var plateaus := get_field_at(&"plateaus", x, z)
	var valleys := get_field_at(&"valleys", x, z)
	return {
		"terrain_type": SurfaceModule.classify(
				landmass, mountains, hills, plateaus, valleys
		),
		"continentalness": continents,
		"landmass": landmass,
		"elevation": elevation,
		"mountainness": mountains,
		"hills": hills,
		"plateaus": plateaus,
		"valleys": valleys,
		"tectonics": get_field_at(&"tectonics", x, z),
		"surface_height": get_surface_height(x, z),
	}


# --- Configuration and diagnostics -------------------------------------------

func get_config() -> WorldConfig:
	return _config


func get_sea_level() -> float:
	return _config.sea_level


func get_base_height() -> float:
	return _config.base_height


func get_height_amplitude() -> float:
	return _config.terrain_height


func get_sampling_stride() -> int:
	return _stack.engine.get_stride()


func get_module_ids() -> PackedStringArray:
	return _stack.get_execution_order()


## Cache counters. Advisory: they depend on thread interleaving and on which
## blocks were requested first, never on the values produced.
func get_cache_stats() -> Dictionary:
	if not is_valid():
		return {}
	return _stack.engine.get_cache_stats()


## Turns node caching off or on. Same terrain either way; used by tests to prove
## the cache cannot influence results.
func set_cache_enabled(enabled: bool) -> void:
	if is_valid():
		_stack.engine.set_cache_enabled(enabled)
