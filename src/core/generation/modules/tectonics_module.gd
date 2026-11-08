class_name TectonicsModule
extends GenerationModule

## A lightweight tectonic influence field: approximate plate regions, their
## boundaries, and how hard each boundary pushes.
##
## Output: [code]-1.0 .. 1.0[/code], signed. Positive is uplift (plates driven
## together), negative is subsidence (plates pulled apart), and a small positive
## or negative tail is transform shear. Away from every boundary the value falls
## to a small plate-interior bias instead of zero, so whole plates sit slightly
## high or slightly low relative to each other.
##
## [b]What this is.[/b] A deterministic description of [i]where[/i] tectonic
## influence is and [i]which kind[/i] it is. It is not a simulation: there is no
## crust, no mass, no time, no plate motion integration and no persistent map.
## Each sample is a pure function of the coordinate, so it stays order- and
## thread-independent like every other field in the pipeline, and it costs no
## memory beyond a bounded lookup cache.
##
## [b]How plates are represented.[/b] A jittered square grid places one site per
## cell; a coordinate belongs to the plate of its nearest site, which makes the
## plates a Voronoi diagram on a jittered lattice - irregular, but without the
## cost of enumerating neighbours in a point set that is not bounded. Each site
## also owns a drift vector (a heading and a speed) and an interior bias, all
## derived from the world seed by hashing the cell coordinate. Since the sites
## are generated, there is nothing to store between runs: the same seed gives the
## same plates on any machine, in any order, in any chunk.
##
## [b]How boundaries are found.[/b] A node samples its own cell and the eight
## around it; the two nearest sites describe the boundary it is closest to. The
## distance to the bisector of those two sites is approximately
## [code](d2 - d1) / 2[/code] for distances d1 and d2 to the nearest and second
## nearest sites, which is the standard cheap Voronoi edge distance and stays
## continuous where the pair changes, because both distances are continuous.
## Sites are confined to their own cell, so the nearest site is always inside the
## 3x3 neighbourhood and that half of the estimate is exact.
##
## [b]How the boundary character is decided.[/b] Given the unit normal n pointing
## from the nearest site towards the second, and the drift vectors of the two
## plates, the relative drift v = drift(second) - drift(nearest) is decomposed
## into [code]along = v . n[/code] and [code]across = v x n[/code]. Approaching
## plates ([code]along < 0[/code]) uplift; separating plates
## ([code]along > 0[/code]) subside into a rift; sideways motion shears. Both
## terms flip sign if the two sites are swapped, so the same edge reads the same
## from either side.
##
## [b]Why a cache, and why a cache of neighbourhoods.[/b] Hashing is far more
## expensive than evaluating noise here: measured on the development container,
## one [method TerrainHash.hash_coords] costs about 2.3 us while one three-octave
## noise sample costs about 0.1 us. Recomputing the nine cells of a node on every
## sample would cost roughly 41 us per node - about twenty times the whole M1
## per-node budget. Every node inside one plate cell, however, needs exactly the
## same nine cell records: at the configured cell size that is tens of thousands
## of nodes per neighbourhood, so one dictionary lookup per node replaces eighteen
## hashes. The bound and the concurrency rules match the engine's node cache: a
## fixed capacity, cleared when exceeded, guarded by a mutex.
##
## Precedent: the plate/region idea follows the Voronoi-plate generators described
## publicly by several projects (see the M2 milestone document for the licence
## review); the boundary decomposition into convergence, divergence and shear is
## the textbook classification of plate boundaries. No code was copied.

const MODULE_ID := &"tectonics"
const OUTPUT_FIELD := &"tectonics"

## Fields per cached cell record: site x, site z, drift x, drift z, interior bias.
const CELL_STRIDE := 5

## Streams mixed into the per-cell hashes, so placement and motion are
## independent draws from the same seed.
const STREAM_SITE := 1
const STREAM_DRIFT := 2

## How many plate neighbourhoods to keep. One neighbourhood is 45 floats, so this
## is tens of kilobytes. Cleared wholesale when exceeded, like the engine cache:
## sampling is spatially coherent, so a single clear is cheaper than tracking
## recency.
const HOOD_CAPACITY := 256

## Plate interior bias range, in units of the field. Small on purpose: a plate's
## character should colour the continent, not decide where the coastline runs.
const INTERIOR_RANGE := 0.12

## Relative drift magnitude that counts as a fully energetic boundary. Drift
## vectors have length 0.4..1.0, so their difference is at most 2.0.
const DRIFT_SCALE := 0.55

## Distance over which two candidate second-nearest sites are considered tied, in
## voxels. Wider blends more of the region around a triple point, narrower leaves a
## sharper but still continuous change of boundary character there.
const TIE_WIDTH := 30.0

## Fraction of a cell that a site may be jittered within, counted from the cell
## centre. 0.5 means "anywhere in the cell", 0.25 means "the central half".
##
## Not a full-cell jitter on purpose. Two neighbouring cells could then place their
## sites a few voxels apart, and a boundary between two nearly coincident sites has
## no well-defined normal: the relative drift decomposition degenerates and the
## two sides of that boundary disagree by up to the full field range. Restricting
## the jitter to the central half keeps every pair of sites at least half a cell
## apart, which makes the degeneracy impossible by construction rather than by
## tolerance. It costs little: the plates are still irregular, because the jitter
## still moves each site by a quarter of a cell in both axes.
const JITTER_SPAN := 0.25

## Shear translation into uplift units. Shear is real but builds far less relief
## than convergence, so it contributes a little and cannot on its own make a
## mountain range.
const SHEAR_WEIGHT := 0.16

## Rift subsidence relative to convergent uplift. Rifts are narrower and shallower
## than the ranges they mirror.
const RIFT_WEIGHT := 0.85

var _cell_size := 520.0
var _boundary_width := 150.0

var _stream_seed := 0

var _hoods: Dictionary = {}
var _mutex := Mutex.new()


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray(), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	_cell_size = maxf(config.plate_cell_size, 64.0)
	_boundary_width = clampf(config.plate_boundary_width, 8.0, _cell_size)
	# Mixing the module id and both versions into one 32-bit stream seed keeps the
	# per-cell hashes cheap while still reshuffling when either version changes.
	_stream_seed = context.module_seed(MODULE_ID, version)
	_mutex.lock()
	_hoods.clear()
	_mutex.unlock()


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	values[get_output_index()] = sample(x, z)


## The field value at a world coordinate, without the engine's value array.
##
## Public so the field can be tested on its own, with no world, no mesher and no
## neighbouring chunk: the tests evaluate single scattered coordinates.
func sample(x: int, z: int) -> float:
	var own := Vector2i(floori(float(x) / _cell_size), floori(float(z) / _cell_size))
	var hood := _get_hood(own)

	var best := INF
	var second := INF
	var third := INF
	var best_index := 0
	var second_index := 0
	var third_index := 0
	for i in range(9):
		var base := i * CELL_STRIDE
		var dx := float(x) - hood[base]
		var dz := float(z) - hood[base + 1]
		var d := dx * dx + dz * dz
		if d < best:
			third = second
			third_index = second_index
			second = best
			second_index = best_index
			best = d
			best_index = i
		elif d < second:
			third = second
			third_index = second_index
			second = d
			second_index = i
		elif d < third:
			third = d
			third_index = i

	# Distance from the bisector of the two nearest sites. Zero on the boundary,
	# rising to half the plate size in the middle of a plate. Continuous even where
	# the pair changes, because both distances are continuous.
	var edge := (sqrt(second) - sqrt(best)) * 0.5
	var proximity := 1.0 - smoothstep(0.0, _boundary_width, edge)

	var interior := (hood[best_index * CELL_STRIDE + 4] - 0.5) * INTERIOR_RANGE * (1.0 - proximity)
	if proximity <= 0.0:
		return interior

	# Boundary character, blended across the third site.
	#
	# Where three plates meet, the second-nearest site swaps from one side of the
	# first to the other, and with it the normal along which the drift is
	# decomposed. Distance to the second site is continuous through that swap, but
	# the direction is not: without the blend below, the same coordinate reads as a
	# convergent boundary on one side of the medial axis and a diverging one on the
	# other, which puts a one-voxel cliff through the middle of a range. Averaging
	# the two candidate pairs, weighted by how nearly tied the second and third
	# sites are, is continuous by construction: at the tie the weight is symmetric,
	# and away from it only one candidate has any weight.
	var with_second := _pair_terms(hood, best_index, second_index)
	var with_third := _pair_terms(hood, best_index, third_index)
	var tie := smoothstep(0.0, TIE_WIDTH, sqrt(third) - sqrt(second))

	var along := lerpf(0.5 * (with_second.x + with_third.x), with_second.x, tie)
	var across := lerpf(0.5 * (with_second.y + with_third.y), with_second.y, tie)
	var rate := lerpf(0.5 * (with_second.z + with_third.z), with_second.z, tie)

	var uplift := smoothstep(0.0, DRIFT_SCALE, -along)
	var rift := smoothstep(0.0, DRIFT_SCALE, along)
	var shear := smoothstep(0.0, DRIFT_SCALE * 1.1, absf(across))

	var stress := (uplift - rift * RIFT_WEIGHT + shear * SHEAR_WEIGHT) * proximity * rate
	return clampf(stress + interior, -1.0, 1.0)


## Relative-motion terms for the pair of plates at [param first] and [param other],
## as [code](along, across, rate)[/code].
##
## [code]along[/code] is positive when the plates separate and negative when they
## approach, [code]across[/code] is the sideways component, and [code]rate[/code] is
## a bounded magnitude. Every term is invariant under swapping the two plates, so a
## boundary reads the same from either side.
func _pair_terms(hood: PackedFloat32Array, first: int, other: int) -> Vector3:
	var a := first * CELL_STRIDE
	var b := other * CELL_STRIDE
	var sx := hood[b] - hood[a]
	var sz := hood[b + 1] - hood[a + 1]
	var span := sqrt(sx * sx + sz * sz)
	if span < 1e-3:
		return Vector3.ZERO
	var nx := sx / span
	var nz := sz / span
	var vx := hood[b + 2] - hood[a + 2]
	var vz := hood[b + 3] - hood[a + 3]
	var along := vx * nx + vz * nz
	var across := vx * nz - vz * nx
	var rate := clampf((absf(along) + absf(across) * 0.5) / DRIFT_SCALE, 0.12, 1.0)
	return Vector3(along, across, rate)


## Nine cell records for the neighbourhood of [param own], from the cache.
func _get_hood(own: Vector2i) -> PackedFloat32Array:
	_mutex.lock()
	var existing: Variant = _hoods.get(own)
	if existing != null:
		_mutex.unlock()
		return existing
	if _hoods.size() >= HOOD_CAPACITY:
		_hoods.clear()
	var built := _build_hood(own)
	_hoods[own] = built
	_mutex.unlock()
	return built


## Builds the row-major 3x3 neighbourhood of cell records around [param own].
##
## Called once per plate cell crossed, not per node: the hashes here are the
## expensive part and they do not depend on the query point.
func _build_hood(own: Vector2i) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(9 * CELL_STRIDE)
	var index := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cell := Vector2i(own.x + dx, own.y + dz)
			var site_hash := TerrainHash.hash_coords(
					_stream_seed, STREAM_SITE, 0, cell.x, cell.y
			)
			var drift_hash := TerrainHash.hash_coords(
					_stream_seed, STREAM_DRIFT, 0, cell.x, cell.y
			)
			# Site inside the central half of its own cell, so the nearest site to any
			# point is always in that point's 3x3 neighbourhood (see JITTER_SPAN).
			var jitter_x := TerrainHash.unit_from_hash(site_hash)
			var jitter_z := TerrainHash.unit_slice(site_hash, 2)
			var heading := TerrainHash.unit_from_hash(drift_hash) * TAU
			var speed := 0.40 + 0.60 * TerrainHash.unit_slice(drift_hash, 2)
			data[index] = (float(cell.x) + 0.5 + JITTER_SPAN * (jitter_x * 2.0 - 1.0)) * _cell_size
			data[index + 1] = (float(cell.y) + 0.5 + JITTER_SPAN * (jitter_z * 2.0 - 1.0)) * _cell_size
			data[index + 2] = cos(heading) * speed
			data[index + 3] = sin(heading) * speed
			data[index + 4] = TerrainHash.unit_slice(drift_hash, 3)
			index += CELL_STRIDE
	return data
