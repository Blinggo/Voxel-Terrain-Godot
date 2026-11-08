class_name DrainageNetwork
extends RefCounted

## Reconstructible, bounded source-to-terminal drainage. Tiles are query indexes,
## never routing boundaries. Entire over-budget/unclosed routes are rejected.
## One mutex serializes preprocessing, not the per-column shape loop. Published
## tile arrays are immutable and remain valid after cache eviction.
const STEP := 32
const SOURCE_STEP := 128
const TILE := 128
const MAX_STEPS := 16
const LAKE_STEP := 8
const LAKE_RADIUS := 128
const HALO := MAX_STEPS * STEP + LAKE_RADIUS + 48
const TILE_CAPACITY := 32
const ROUTE_CAPACITY := 1024
const NODE_CAPACITY := 8192
const DIRECTIONS := [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0), Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]
var _engine: WeakRef
var _seed: int
var _sea: float
var _source_rise: float
var _width: float
var _tiles: Dictionary = {}
var _routes: Dictionary = {}
var _nodes: Dictionary = {}
var _lakes: Dictionary = {}
var _mutex := Mutex.new()
var _builds := 0
var _hits := 0
var _build_usec := 0
var _rejected := 0

func configure(engine: GenerationEngine, context: GenerationContext, version: int) -> void:
	_engine = weakref(engine)
	_seed = context.module_seed(&"hydrology", version)
	_sea = context.config.sea_level
	_source_rise = context.config.hydrology_source_rise
	_width = clampf(context.config.hydrology_width_scale, 0.5, 1.25)

func _height(p: Vector2i) -> float:
	var engine: GenerationEngine = _engine.get_ref()
	return engine.sample_height(p.x, p.y)

func _node(cell: Vector2i) -> Dictionary:
	if _nodes.has(cell):
		return _nodes[cell]
	var p := cell * STEP
	var h := _height(p)
	var receiver := cell
	var best_slope := 0.0
	var lowest := INF
	for d in DIRECTIONS:
		var q: Vector2i = cell + d
		var nh := _height(q * STEP)
		lowest = minf(lowest, nh)
		var slope := (h - nh) / Vector2(d).length()
		if slope > best_slope + 0.00001:
			best_slope = slope
			receiver = q
	var result := {"cell": cell, "point": Vector2(p), "height": h, "receiver": receiver, "rim": lowest}
	if _nodes.size() >= NODE_CAPACITY:
		_nodes.clear()
	_nodes[cell] = result
	return result

## Finite connected-sublevel flood: no square boundary is accepted as a shore.
## No complete basin inside the search area => no lake, not a clipped lake.
func _lake(cell: Vector2i) -> Dictionary:
	if _lakes.has(cell):
		return _lakes[cell]
	var n := _node(cell)
	var base: float = n.height
	var level := base + 12.0
	var result: Dictionary = {}
	var center := cell * STEP
	if level > base + 0.6:
		var grid: Dictionary = {}
		for z in range(-16, 17):
			for x in range(-16, 17):
				var c := Vector2i(x,z)
				grid[c] = _height(center + c * LAKE_STEP)
		# Minimax escape cost finds the lowest saddle to the finite domain edge.
		# Keep water below that saddle; do not assume the domain edge is an outlet.
		var spill := _spill_level(grid)
		level = minf(base + 12.0, spill - 0.2)
		for attempt in range(3):
			if level <= base + 0.6:
				break
			var queue: Array[Vector2i] = [Vector2i.ZERO]
			var visited := {Vector2i.ZERO: true}
			var open := false
			var cursor := 0
			while cursor < queue.size():
				var c := queue[cursor]
				cursor += 1
				if absi(c.x) == 16 or absi(c.y) == 16:
					open = true
					break
				for d in DIRECTIONS:
					var next: Vector2i = c + d
					if not visited.has(next) and float(grid[next]) < level:
						visited[next] = true
						queue.append(next)
			if not open and visited.size() >= 3:
				var cells: Dictionary = {}
				for c in visited:
					cells[center / LAKE_STEP + c] = true
				result = {"id": "lake:%d:%d" % [cell.x, cell.y], "level": level, "cells": cells, "center": Vector2(center), "bottom": base, "spill_level": spill}
				break
			level = lerpf(base, level, 0.5)
	if _lakes.size() >= 512:
		_lakes.clear()
	_lakes[cell] = result
	return result

func _route(source_cell: Vector2i) -> Dictionary:
	if _routes.has(source_cell):
		return _routes[source_cell]
	# One seed-selected coarse cell inside each source parcel. Elevated eligibility
	# prevents uniform lowland starts. No mutable RNG and no precipitation model.
	var h := TerrainHash.hash_coords(_seed, 917, 1, source_cell.x, source_cell.y)
	var cell := source_cell * 4 + Vector2i(int(h & 3), int((h >> 3) & 3))
	var nodes: Array[Dictionary] = []
	var terminal: Dictionary = {}
	if float(_node(cell).height) >= _sea + _source_rise:
		for i in range(MAX_STEPS + 1):
			var n := _node(cell)
			nodes.append(n)
			if float(n.height) <= _sea:
				terminal = {"id": "ocean", "level": _sea}
				break
			if n.receiver == cell:
				terminal = _lake(cell)
				break
			cell = n.receiver
	var result: Dictionary = {}
	if not terminal.is_empty() and nodes.size() >= 3:
		result = {"source": source_cell, "nodes": nodes, "terminal": terminal}
	elif not nodes.is_empty():
		_rejected += 1
	if _routes.size() >= ROUTE_CAPACITY:
		_routes.clear()
	_routes[source_cell] = result
	return result

func tile_at(point: Vector2i) -> Dictionary:
	var key := Vector2i(floori(float(point.x) / TILE), floori(float(point.y) / TILE))
	_mutex.lock()
	if _tiles.has(key):
		_hits += 1
		var cached: Dictionary = _tiles[key]
		_mutex.unlock()
		return cached
	var started := Time.get_ticks_usec()
	var tile := _build_tile(key)
	_build_usec += Time.get_ticks_usec() - started
	_builds += 1
	if _tiles.size() >= TILE_CAPACITY:
		_tiles.erase(_tiles.keys()[0])
	_tiles[key] = tile
	_mutex.unlock()
	return tile

func _build_tile(key: Vector2i) -> Dictionary:
	var rect := Rect2(Vector2(key * TILE), Vector2(TILE,TILE)).grow(48.0)
	var lo := Vector2i(floori((rect.position.x - HALO) / SOURCE_STEP), floori((rect.position.y - HALO) / SOURCE_STEP))
	var hi := Vector2i(floori((rect.end.x + HALO) / SOURCE_STEP), floori((rect.end.y + HALO) / SOURCE_STEP))
	var edges: Dictionary = {}
	var lakes: Dictionary = {}
	var node_flow: Dictionary = {}
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var route := _route(Vector2i(x,z))
			if route.is_empty():
				continue
			var terminal: Dictionary = route.terminal
			if terminal.has("cells") and rect.grow(LAKE_RADIUS).has_point(terminal.center):
				lakes[terminal.id] = terminal
			var nodes: Array = route.nodes
			for n in nodes:
				var cell: Vector2i = n.cell
				node_flow[cell] = int(node_flow.get(cell, 0)) + 1
			for i in range(nodes.size() - 1):
				var a: Dictionary = nodes[i]
				var b: Dictionary = nodes[i+1]
				var bounds := Rect2(a.point, Vector2.ZERO).expand(b.point)
				if not rect.intersects(bounds.grow(1.0)):
					continue
				if not edges.has(a.cell):
					edges[a.cell] = {"a": a.point, "b": b.point, "ac": a.cell, "bc": b.cell,
						"ya": maxf(float(terminal.level), float(a.height) - 0.5),
						"yb": maxf(float(terminal.level), float(b.height) - 0.5), "body": terminal.id, "reach_id": "reach:%d:%d" % [a.cell.x, a.cell.y]}
	var segments: Array[Dictionary] = []
	for edge in edges.values():
		var fa := float(node_flow.get(edge.ac, 1))
		var fb := float(node_flow.get(edge.bc, 1))
		edge["flow_a"] = fa
		edge["flow_b"] = fb
		edge["wa"] = minf(8.0, 1.5 + sqrt(fa)) * _width
		edge["wb"] = minf(8.0, 1.5 + sqrt(fb)) * _width
		edge["drop"] = float(edge.ya) - float(edge.yb)
		edge["waterfall"] = float(edge.drop) >= 8.0 and float(edge.drop) / Vector2(edge.b - edge.a).length() > 0.2
		# Cubic endpoint tangents agree at shared nodes. Four chords approximate
		# curvature; no coordinate randomness or chunk-local curves are introduced.
		var a: Vector2 = edge.a
		var b: Vector2 = edge.b
		var downstream := _node(edge.bc)
		var c: Vector2 = Vector2(Vector2i(downstream.receiver) * STEP)
		var tangent := (c - b).normalized() if c != b else (b - a).normalized()
		var p1 := a + (b-a) / 3.0
		var p2 := b - tangent * a.distance_to(b) / 3.0
		var last := a
		for i in range(4):
			var t0 := float(i)/4.0
			var t1 := float(i+1)/4.0
			var end := a.bezier_interpolate(p1,p2,b,t1)
			var part: Dictionary = edge.duplicate()
			part.a = last
			part.b = end
			part.wa = lerpf(float(edge.wa),float(edge.wb),t0)
			part.wb = lerpf(float(edge.wa),float(edge.wb),t1)
			# Concentrate only genuine steep drops into a ledge. Data preserves
			# the reach drop; a future waterfall renderer can consume it.
			part.ya = lerpf(float(edge.ya),float(edge.yb),smoothstep(0.25,0.75,t0) if edge.waterfall else t0)
			part.yb = lerpf(float(edge.ya),float(edge.yb),smoothstep(0.25,0.75,t1) if edge.waterfall else t1)
			segments.append(part)
			last = end
	# 16-voxel spatial bins eliminate irrelevant reach distance tests from the
	# ordinary column path. Halo bins support exact shared-border comparisons.
	var bins: Dictionary = {}
	for z in range(-1,10):
		for x in range(-1,10):
			var bin_key := key*8 + Vector2i(x,z)
			var bin_rect := Rect2(Vector2(bin_key*16), Vector2(16,16))
			var candidates: Array[Dictionary] = []
			for segment in segments:
				var bounds := Rect2(segment.a,Vector2.ZERO).expand(segment.b).grow(40.1)
				if bin_rect.intersects(bounds):
					candidates.append(segment)
			bins[bin_key] = candidates
	return {"key": key, "segments": segments, "lakes": lakes.values(), "bins": bins}

## Packed per-column query: x=shaped ground, y=water level, z=half-width,
## w=kind (0 dry, 1 ocean, 2 river, 3 lake). No paths searched in this loop.
func sample(point: Vector2, original: float, tile: Dictionary) -> Vector4:
	var ground := original
	var water := -INF
	var kind := 0.0
	var width := 0.0
	for edge in tile.bins.get(Vector2i(floori(point.x/16.0),floori(point.y/16.0)), []):
		var a: Vector2 = edge.a
		var ab: Vector2 = edge.b - a
		var t := clampf((point-a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var distance := point.distance_to(a + t * ab)
		var w := lerpf(float(edge.wa), float(edge.wb), t)
		var level := lerpf(float(edge.ya), float(edge.yb), t)
		var depth := 1.5 + w * 0.3
		# Valley width grows with flow but is suppressed on steep reaches.
		var flood := w * (2.0 + 2.0 / (1.0 + float(edge.drop)))
		if distance < flood:
			var bank := smoothstep(w, flood, distance)
			var bed := level - depth * (1.0 - smoothstep(0.0, w, distance))
			ground = minf(ground, lerpf(bed, original, bank))
		if distance < w and level > water:
			water = level
			width = w
			kind = 2.0
	for lake in tile.lakes:
		var c := Vector2i(roundi(point.x / LAKE_STEP), roundi(point.y / LAKE_STEP))
		if lake.cells.has(c) and original < float(lake.level) and float(lake.level) > water:
			water = lake.level
			kind = 3.0
			width = 0.0
	if ground < _sea and _sea > water:
		water = _sea
		kind = 1.0
	if water <= ground + 0.02:
		water = -INF
		kind = 0.0
	return Vector4(ground, water, width, kind)

func stats() -> Dictionary:
	_mutex.lock()
	var result := {"tiles": _tiles.size(), "routes": _routes.size(), "nodes": _nodes.size(), "lakes": _lakes.size(), "builds": _builds, "hits": _hits, "build_usec": _build_usec, "rejected_routes": _rejected}
	_mutex.unlock()
	return result


## Bounded minimax Dijkstra / priority-flood-style escape search. Independent
## implementation from the mathematical recurrence, no external source copied.
static func _spill_level(grid: Dictionary) -> float:
	var heap: Array[Vector3] = []
	_heap_push(heap, Vector3(float(grid[Vector2i.ZERO]),0,0))
	var seen: Dictionary = {}
	while not heap.is_empty():
		var item := _heap_pop(heap)
		var c := Vector2i(int(item.y),int(item.z))
		if seen.has(c):
			continue
		seen[c] = true
		if absi(c.x) == 16 or absi(c.y) == 16:
			return item.x
		for d in DIRECTIONS:
			var q: Vector2i = c+d
			if not seen.has(q):
				_heap_push(heap,Vector3(maxf(item.x,float(grid[q])),q.x,q.y))
	return INF

static func _heap_push(heap: Array[Vector3], value: Vector3) -> void:
	var i := heap.size()
	heap.append(value)
	while i > 0:
		var parent := (i-1)/2
		if heap[parent].x <= value.x:
			break
		heap[i] = heap[parent]
		i = parent
	heap[i] = value

static func _heap_pop(heap: Array[Vector3]) -> Vector3:
	var first := heap[0]
	var last: Vector3 = heap.pop_back()
	if heap.is_empty():
		return first
	var i := 0
	while i*2+1 < heap.size():
		var child := i*2+1
		if child+1 < heap.size() and heap[child+1].x < heap[child].x:
			child += 1
		if heap[child].x >= last.x:
			break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return first

## Inspection seam: immutable accepted source routes for a finite parcel rectangle.
## Not used by ordinary terrain sampling or rendering.
func inspect_routes(parcels: Rect2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	_mutex.lock()
	for z in range(parcels.position.y, parcels.end.y):
		for x in range(parcels.position.x, parcels.end.x):
			var route := _route(Vector2i(x,z))
			if not route.is_empty():
				result.append(route.duplicate(true))
	_mutex.unlock()
	return result
