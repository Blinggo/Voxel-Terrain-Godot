class_name GenerationEngine
extends RefCounted

## Executes the module pipeline and turns its fields into column heights.
##
## [b]Two resolutions, on purpose.[/b]
##
## Geographic fields - continentalness, elevation, mountains, hills - vary over
## hundreds of voxels. Evaluating them per column would repeat almost the same
## answer 64 times inside one 16x16 block. The engine therefore evaluates them
## on a coarse [i]node grid[/i] (every [member get_stride] voxels), caches the
## nodes, and bilinearly interpolates between them. Cost per block becomes one
## evaluation per node instead of one per column.
##
## Fine detail cannot survive that grid, so modules that opt in through
## [member GenerationModule.contributes_columns] add their contribution per
## column at full resolution, after interpolation.
##
## [b]Seams cannot exist.[/b] Node positions are snapped to absolute multiples of
## the stride and interpolation weights are derived from absolute coordinates,
## so two blocks sharing a column compute that column through the same nodes and
## the same weights. Nothing depends on which block is being generated.
##
## [b]Threading.[/b] Voxel Tools generates blocks on worker threads. Sampling is
## read-only except for the node cache, which is guarded by a mutex and only ever
## stores values that are pure functions of the coordinate. A racing pair of
## threads may both compute the same node; they produce identical values, so the
## outcome is the same as if they had run in sequence.
##
## Module results must not be assumed to be in any particular unit; each module
## documents its own range.

## Field produced by the module that composes the final surface height in
## voxels. The engine interpolates this one and ignores the rest.
const SURFACE_FIELD := &"surface_height"

## Upper bound on cached nodes. A 128-voxel streaming radius is a few thousand
## nodes, so this is never reached in normal play; it exists so a long session
## cannot grow without limit.
const CACHE_CAPACITY := 8192

var _context: GenerationContext
var _registry: GenerationRegistry
var _modules: Array[GenerationModule] = []
var _column_modules: Array[GenerationModule] = []
var _field_count := 0
var _surface_index := -1
var _stride := GenerationEngine.DEFAULT_STRIDE
var _output_bounds := Vector2.ZERO

var _cache: Dictionary = {}
var _cache_mutex: Mutex
var _cache_enabled := true
var _cache_hits := 0
var _node_evaluations := 0

## Default node spacing, in voxels.
const DEFAULT_STRIDE := 8


## [param context] supplies seed and configuration; [param registry] must already
## be resolved.
func _init(context_ref: GenerationContext, registry: GenerationRegistry) -> void:
	assert(context_ref != null, "GenerationEngine requires a GenerationContext.")
	assert(registry != null, "GenerationEngine requires a registry.")
	_context = context_ref
	_registry = registry
	_cache_mutex = Mutex.new()

	if not registry.is_resolved():
		push_error("GenerationEngine: registry must be resolved before use.")
		return

	_modules = registry.get_ordered_modules()
	_field_count = registry.get_field_count()
	_surface_index = registry.get_field_index(SURFACE_FIELD)
	if _surface_index < 0:
		push_error("GenerationEngine: no module produces '%s'." % SURFACE_FIELD)

	for module in _modules:
		module.bind(_registry)
		module.configure(_context)
		if module.contributes_columns:
			_column_modules.append(module)

	_stride = maxi(1, int(context_ref.config.sampling_stride))
	if _surface_index >= 0:
		_output_bounds = _modules[_surface_index].get_output_bounds()


func get_stride() -> int:
	return _stride


func get_registry() -> GenerationRegistry:
	return _registry


## Enables or disables reuse of node values across blocks. Disabling it changes
## nothing about the values produced, only the cost of producing them; tests use
## that to prove the cache cannot alter terrain.
func set_cache_enabled(enabled: bool) -> void:
	_cache_mutex.lock()
	_cache_enabled = enabled
	if not enabled:
		_cache.clear()
	_cache_mutex.unlock()


func clear_cache() -> void:
	_cache_mutex.lock()
	_cache.clear()
	_cache_mutex.unlock()


## Cache counters, for diagnostics and tests. Advisory only: the numbers depend
## on thread interleaving, the resulting terrain does not.
func get_cache_stats() -> Dictionary:
	_cache_mutex.lock()
	var stats := {
		"entries": _cache.size(),
		"hits": _cache_hits,
		"evaluations": _node_evaluations,
		"enabled": _cache_enabled,
	}
	_cache_mutex.unlock()
	return stats


## All module values at one node, in field-slot order.
##
## The returned array is shared with the cache and must be treated as read-only.
func sample_node(x: int, z: int) -> PackedFloat32Array:
	var key := Vector2i(x, z)

	if _cache_enabled:
		_cache_mutex.lock()
		var cached: Variant = _cache.get(key)
		if cached != null:
			_cache_hits += 1
			_cache_mutex.unlock()
			return cached
		_cache_mutex.unlock()

	var values := PackedFloat32Array()
	values.resize(_field_count)
	for module in _modules:
		module.evaluate_node(x, z, values)

	if _cache_enabled:
		_cache_mutex.lock()
		_node_evaluations += 1
		if _cache.size() >= CACHE_CAPACITY:
			# Approximate eviction: cheap, bounded, and harmless because every
			# value is recomputed identically.
			_cache.clear()
		_cache[key] = values
		_cache_mutex.unlock()
	else:
		_cache_mutex.lock()
		_node_evaluations += 1
		_cache_mutex.unlock()

	return values


## One module's value at a coordinate, for debugging and tests.
func get_field_at(module_id: StringName, x: int, z: int) -> float:
	var index := _registry.get_module_output_index(module_id)
	if index < 0:
		return 0.0
	var values := sample_node(x, z)
	return values[index]


## Surface height of a single column, in voxels.
func sample_height(x: int, z: int) -> float:
	return sample_columns(Vector2i(x, z), Vector2i.ONE)[0]


## Surface height for every column of a rectangle, row-major, [param size].x
## values per row.
##
## This is what the voxel adapter consumes: one call per block instead of one
## call per column, so the node lookups and interpolation weights are shared.
func sample_columns(origin: Vector2i, size: Vector2i) -> PackedFloat32Array:
	var heights := PackedFloat32Array()
	heights.resize(size.x * size.y)
	if _surface_index < 0 or size.x <= 0 or size.y <= 0:
		return heights

	var stride := _stride
	var node_origin_x := _floor_to_multiple(origin.x, stride)
	var node_origin_z := _floor_to_multiple(origin.y, stride)

	# Enough nodes to bracket every column of the rectangle, plus one node past
	# the far edge to interpolate towards.
	var nodes_x := _floor_div(origin.x + size.x - 1 - node_origin_x, stride) + 2
	var nodes_z := _floor_div(origin.y + size.y - 1 - node_origin_z, stride) + 2

	var nodes: Array[PackedFloat32Array] = []
	nodes.resize(nodes_x * nodes_z)
	for j in range(nodes_z):
		var node_z := node_origin_z + j * stride
		for i in range(nodes_x):
			nodes[j * nodes_x + i] = sample_node(node_origin_x + i * stride, node_z)

	# Per-column node index and weight, shared by every row of the block.
	var column_index := PackedInt32Array()
	var column_weight := PackedFloat32Array()
	column_index.resize(size.x)
	column_weight.resize(size.x)
	for i in range(size.x):
		var rel := origin.x + i - node_origin_x
		var index := rel / stride
		column_index[i] = index
		column_weight[i] = float(rel - index * stride) / float(stride)

	var row_index := PackedInt32Array()
	var row_weight := PackedFloat32Array()
	row_index.resize(size.y)
	row_weight.resize(size.y)
	for j in range(size.y):
		var rel := origin.y + j - node_origin_z
		var index := rel / stride
		row_index[j] = index
		row_weight[j] = float(rel - index * stride) / float(stride)

	# Surface value of every node, grouped by node row. The inner loop then only
	# touches two flat packed arrays per row instead of indexing an array of
	# arrays four times per column - which, in GDScript, is most of the cost of
	# the whole function.
	var surface_index := _surface_index
	var rows: Array[PackedFloat32Array] = []
	rows.resize(nodes_z)
	for j in range(nodes_z):
		var row := PackedFloat32Array()
		row.resize(nodes_x)
		var base := j * nodes_x
		for i in range(nodes_x):
			row[i] = nodes[base + i][surface_index]
		rows[j] = row

	# Column modules are dispatched without iterating for the common case of
	# exactly one: a scripted call per column would dominate, a call per block
	# does not.
	var column_count := _column_modules.size()
	var single_column_module: GenerationModule = (
			_column_modules[0] if column_count == 1 else null
	)

	for j in range(size.y):
		var weight_z := row_weight[j]
		var top_row := rows[row_index[j]]
		var bottom_row := rows[row_index[j] + 1]
		var world_z := origin.y + j
		var out_row := j * size.x

		for i in range(size.x):
			var index := column_index[i]
			var weight_x := column_weight[i]

			# Bilinear blend of the four surrounding nodes.
			var height := lerpf(
					lerpf(top_row[index], top_row[index + 1], weight_x),
					lerpf(bottom_row[index], bottom_row[index + 1], weight_x),
					weight_z
			)

			heights[out_row + i] = height

	# Full-resolution terms are added to the interpolated surface in bulk, once
	# per module per block.
	if column_count == 1:
		single_column_module.add_columns(heights, origin, size)
	elif column_count > 1:
		for module in _column_modules:
			module.add_columns(heights, origin, size)

	# Finally enforce the composer's bounds, so nothing added after interpolation
	# can leave the terrain range the rest of the project assumes.
	var bounds := _output_bounds
	if bounds != Vector2.ZERO:
		for i in range(heights.size()):
			heights[i] = clampf(heights[i], bounds.x, bounds.y)

	return heights


## Field slot index of a module's output, for tests that want to reason about
## the per-node array directly.
func get_field_index(module_id: StringName) -> int:
	return _registry.get_module_output_index(module_id)


## Integer division rounding towards negative infinity. GDScript's `/` truncates
## towards zero, which would make the node grid shift at the origin.
static func _floor_div(value: int, divisor: int) -> int:
	var quotient := value / divisor
	if value % divisor != 0 and ((value < 0) != (divisor < 0)):
		quotient -= 1
	return quotient


static func _floor_to_multiple(value: int, multiple: int) -> int:
	return _floor_div(value, multiple) * multiple
