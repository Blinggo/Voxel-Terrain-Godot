extends RefCounted

## Tests for the M1 generation pipeline: determinism, fields, module system and
## integration with the voxel adapter.
##
## Everything here is engine-light except the last section, which writes real
## voxels through [TerrainBlockGenerator]. No streaming, no camera, no display.
##
## [b]Sampling discipline.[/b] Geographic fields are evaluated on a node grid
## spaced [code]sampling_stride[/code] voxels apart, and the engine caches nodes.
## The tests therefore sample at multiples of the stride wherever they only need
## field values, which keeps a run in the tens of milliseconds instead of
## thrashing the cache with off-grid lookups.

const STRIDE := 8

## Tolerances for statistical checks. They are set well inside the margins the
## current tuning actually achieves, so they detect a regression rather than
## encoding the exact numbers a specific seed happens to produce.
const MIN_SEED_DIFFERENCE := 0.95
const MIN_CLASS_ROUGHNESS_RATIO := 1.2
const MAX_ISOLATED_MOUNTAIN_FRACTION := 0.05
const MAX_COAST_TO_INLAND_ROUGHNESS := 0.8

## Mean height change between adjacent columns at the waterline, in voxels, that
## still counts as a beach rather than a step.
const MAX_SHORELINE_SLOPE := 0.5

## Steepest height change allowed between two adjacent columns, in voxels. Real
## terrain reaches about 4; a discontinuity in the field would produce far more.
const MAX_COLUMN_STEP := 8.0


static func run(report) -> void:
	_test_hash_is_pure(report)
	_test_hash_streams_are_independent(report)
	_test_hash_range(report)
	_test_module_seeds_are_per_module(report)
	_test_same_seed_is_identical(report)
	_test_seed_changes_terrain(report)
	_test_generation_version_changes_terrain(report)
	_test_negative_coordinates(report)
	_test_large_coordinates(report)
	_test_block_grouping_does_not_matter(report)
	_test_cache_does_not_change_terrain(report)
	_test_concurrent_sampling_matches_serial(report)

	_test_field_ranges(report)
	_test_continental_variety(report)
	_test_surface_bounds_across_seeds(report)
	_test_mountains_are_continuous(report)
	_test_landform_separation(report)
	_test_coastal_transition_is_smooth(report)
	_test_ocean_and_land_both_exist(report)

	_test_execution_order(report)
	_test_registry_rejects_duplicates(report)
	_test_registry_rejects_unknown_dependency(report)
	_test_registry_rejects_cycles(report)
	_test_module_is_independently_testable(report)
	_test_configuration_is_snapshotted(report)
	_test_adding_a_module_disturbs_nothing(report)

	_test_generator_matches_the_surface(report)
	_test_terrain_varies_within_a_region(report)


# --------------------------------------------------------------------- helpers

static func _make_config(world_seed: int = 1337) -> WorldConfig:
	var config := WorldConfig.new()
	config.world_seed = world_seed
	return config


static func _make_surface(world_seed: int = 1337) -> GeographicSurface:
	return GeographicSurface.new(_make_config(world_seed))


static func _make_context(world_seed: int = 1337) -> GenerationContext:
	var config := _make_config(world_seed)
	return GenerationContext.new(config.world_seed, config.generation_version, config)


## Node-aligned coordinates, so field lookups hit the cache the engine builds.
static func _aligned(x: int, z: int) -> Vector2i:
	return Vector2i(x * STRIDE, z * STRIDE)


static func _grid(count: int, origin: Vector2i = Vector2i.ZERO, stride: int = STRIDE) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for j in range(count):
		for i in range(count):
			points.append(origin + Vector2i(i * stride, j * stride))
	return points


# ------------------------------------------------------------------ determinism

static func _test_hash_is_pure(report) -> void:
	var mismatch := 0
	for i in range(1000):
		var x := (i * 37) % 4001 - 2000
		var z := (i * 91) % 3001 - 1500
		var a := TerrainHash.hash_coords(90210, 0x1234, 1, x, z)
		var b := TerrainHash.hash_coords(90210, 0x1234, 1, x, z)
		if a != b:
			mismatch += 1
	report.check_equal("coordinate hash is a pure function of its inputs", mismatch, 0)


static func _test_hash_streams_are_independent(report) -> void:
	var differing_seed := 0
	var differing_module := 0
	var differing_x := 0
	var differing_z := 0
	var differing_version := 0
	var samples := 500

	for i in range(samples):
		var x := i * 13
		var z := i * -7
		var base := TerrainHash.hash_coords(1337, 0xAA, 1, x, z)
		if base != TerrainHash.hash_coords(1338, 0xAA, 1, x, z):
			differing_seed += 1
		if base != TerrainHash.hash_coords(1337, 0xBB, 1, x, z):
			differing_module += 1
		if base != TerrainHash.hash_coords(1337, 0xAA, 1, x + 1, z):
			differing_x += 1
		if base != TerrainHash.hash_coords(1337, 0xAA, 1, x, z + 1):
			differing_z += 1
		if base != TerrainHash.hash_coords(1337, 0xAA, 2, x, z):
			differing_version += 1

	for pair in [
		["changing the world seed changes every stream", differing_seed],
		["different module ids produce independent streams", differing_module],
		["adjacent x coordinates hash differently", differing_x],
		["adjacent z coordinates hash differently", differing_z],
		["changing the generation version reshuffles the stream", differing_version],
	]:
		var differing := int(pair[1])
		report.check(
				String(pair[0]),
				differing >= int(samples * 0.995),
				"%d of %d samples differ" % [differing, samples]
		)


static func _test_hash_range(report) -> void:
	var out_of_range := 0
	var negative_input_failures := 0
	for i in range(2000):
		var x := i * 4999 - 5000000
		var z := i * -1237 + 3000000
		var unit := TerrainHash.unit_at(4242, 0x5EED, 1, x, z)
		if unit < 0.0 or unit >= 1.0:
			out_of_range += 1
		var large := TerrainHash.hash_coords(4242, 0x5EED, 1, -1000000000, 1000000000)
		if large < 0:
			negative_input_failures += 1

	report.check_equal("hashed unit values stay in [0, 1)", out_of_range, 0)
	report.check_equal("hash of extreme coordinates stays a positive 32-bit value", negative_input_failures, 0)


static func _test_module_seeds_are_per_module(report) -> void:
	# Two instances of the same module must agree...
	var a := TerrainHash.module_seed(1337, TerrainHash.hash_string("continentalness"), 1)
	var b := TerrainHash.module_seed(1337, TerrainHash.hash_string("continentalness"), 1)
	report.check_equal("module seeds are stable across instances", a, b)

	# ...and two different modules must not share a stream.
	var ids := ["detail", "continentalness", "elevation", "mountainness", "hills", "surface"]
	var seeds := {}
	var duplicates := 0
	for id in ids:
		var value := TerrainHash.module_seed(1337, TerrainHash.hash_string(id), 1)
		if seeds.has(value):
			duplicates += 1
		seeds[value] = id
	report.check_equal("every module gets a distinct noise seed", duplicates, 0, "ids=%s" % String(", ".join(ids)))

	# A module version bump must not touch other modules.
	var bumped := TerrainHash.module_seed(1337, TerrainHash.hash_string("continentalness"), 2)
	var untouched := TerrainHash.module_seed(1337, TerrainHash.hash_string("elevation"), 1)
	report.check("bumping one module's version changes its seed", bumped != a)
	report.check(
			"bumping one module's version leaves other modules alone",
			untouched == TerrainHash.module_seed(1337, TerrainHash.hash_string("elevation"), 1)
	)


static func _test_same_seed_is_identical(report) -> void:
	var first := _make_surface(2024)
	var second := _make_surface(2024)

	var mismatched := 0
	var compared := 0
	for point in _grid(24, Vector2i(-96, -96)):
		compared += 1
		if first.get_surface_height(point.x, point.y) != second.get_surface_height(point.x, point.y):
			mismatched += 1
	report.check_equal("same seed produces identical heights from independent pipelines", mismatched, 0, "%d columns" % compared)

	var field_mismatch := 0
	for point in _grid(12, Vector2i(-48, 24)):
		if first.get_field_at(&"continentalness", point.x, point.y) != second.get_field_at(&"continentalness", point.x, point.y):
			field_mismatch += 1
		if first.get_field_at(&"mountainness", point.x, point.y) != second.get_field_at(&"mountainness", point.x, point.y):
			field_mismatch += 1
		if first.get_field_at(&"hills", point.x, point.y) != second.get_field_at(&"hills", point.x, point.y):
			field_mismatch += 1
	report.check_equal("same seed produces identical module fields", field_mismatch, 0)


static func _test_seed_changes_terrain(report) -> void:
	var first := _make_surface(1111)
	var second := _make_surface(2222)

	var differing := 0
	var total := 0
	for point in _grid(20, Vector2i(-80, -80)):
		total += 1
		if absf(first.get_surface_height(point.x, point.y) - second.get_surface_height(point.x, point.y)) > 0.001:
			differing += 1

	var fraction := float(differing) / float(maxi(total, 1))
	report.check(
			"different seeds produce different terrain",
			fraction > MIN_SEED_DIFFERENCE,
			"%.1f%% of %d columns differ" % [fraction * 100.0, total]
	)


static func _test_generation_version_changes_terrain(report) -> void:
	var base_config := _make_config(4242)
	var bumped_config := _make_config(4242)
	bumped_config.generation_version = base_config.generation_version + 1

	var base := GeographicSurface.new(base_config)
	var bumped := GeographicSurface.new(bumped_config)

	var differing := 0
	var total := 0
	for point in _grid(16, Vector2i(-64, -64)):
		total += 1
		if absf(base.get_surface_height(point.x, point.y) - bumped.get_surface_height(point.x, point.y)) > 0.001:
			differing += 1

	var fraction := float(differing) / float(maxi(total, 1))
	report.check(
			"bumping the generation version changes the world",
			fraction > MIN_SEED_DIFFERENCE,
			"%.1f%% of %d columns differ" % [fraction * 100.0, total]
	)


static func _test_negative_coordinates(report) -> void:
	var first := _make_surface(777)
	var second := _make_surface(777)

	var mismatched := 0
	var out_of_bounds := 0
	var checked := 0
	for point in _grid(16, Vector2i(-1024, -1024)):
		checked += 1
		var height := first.get_surface_height(point.x, point.y)
		if height != second.get_surface_height(point.x, point.y):
			mismatched += 1
		if not is_finite(height) or height < SurfaceModule.MIN_HEIGHT or height > SurfaceModule.MAX_HEIGHT:
			out_of_bounds += 1

	report.check_equal("negative coordinates are deterministic", mismatched, 0, "%d columns" % checked)
	report.check_equal("negative coordinates stay within the height bounds", out_of_bounds, 0)

	# The node grid must not shift sign-dependent interpolation on either side of
	# the origin: sweeping across x = 0 must stay finite and bounded.
	var crossing_issues := 0
	for x in range(-16, 17):
		var height := first.get_surface_height(x, -1)
		if not is_finite(height) or height < SurfaceModule.MIN_HEIGHT or height > SurfaceModule.MAX_HEIGHT:
			crossing_issues += 1
	report.check_equal("the surface is well defined across the origin", crossing_issues, 0)


static func _test_large_coordinates(report) -> void:
	var first := _make_surface(31337)
	var second := _make_surface(31337)

	var mismatched := 0
	var out_of_bounds := 0
	var checked := 0
	for raw_base in [1000000, -1000000, 1000000000, -1000000000]:
		var base: int = raw_base
		for i in range(40):
			checked += 1
			var x := base + i * 17
			var z := -base - i * 29
			var height := first.get_surface_height(x, z)
			if height != second.get_surface_height(x, z):
				mismatched += 1
			if not is_finite(height) or height < SurfaceModule.MIN_HEIGHT or height > SurfaceModule.MAX_HEIGHT:
				out_of_bounds += 1

	report.check_equal("large coordinates are deterministic", mismatched, 0, "%d columns" % checked)
	report.check_equal("large coordinates stay within the height bounds", out_of_bounds, 0)

	# Honest limitation check: float32 noise coordinates lose resolution far from
	# the origin, so terrain is still defined there but coarser. Recorded rather
	# than asserted tightly.
	var differing := 0
	for i in range(40):
		var x := 1000000000 + i * 512
		if absf(first.get_surface_height(x, 0) - first.get_surface_height(x + 1, 0)) > 0.0001:
			differing += 1
	report.info("far from the origin, %d of 40 adjacent columns still differ (height stays valid)" % differing)


static func _test_block_grouping_does_not_matter(report) -> void:
	var surface := _make_surface(5150)
	var origin := Vector2i(-64, -32)

	# One 64x64 request.
	var whole := surface.sample_block_heights(origin, Vector2i(64, 64))

	# Sixteen 16x16 requests, walked in reverse so the order is not the natural one.
	var pieces := PackedFloat32Array()
	pieces.resize(64 * 64)
	for block_z in range(3, -1, -1):
		for block_x in range(3, -1, -1):
			var block := surface.sample_block_heights(
					origin + Vector2i(block_x * 16, block_z * 16), Vector2i(16, 16)
			)
			for j in range(16):
				for i in range(16):
					pieces[(block_z * 16 + j) * 64 + block_x * 16 + i] = block[j * 16 + i]

	var piece_mismatch := 0
	for i in range(whole.size()):
		if whole[i] != pieces[i]:
			piece_mismatch += 1
	report.check_equal(
			"heights do not depend on how the area is split into blocks", piece_mismatch, 0)


	# And single-column queries agree with the block path.
	var column_mismatch := 0
	for j in range(0, 64, 7):
		for i in range(0, 64, 7):
			if surface.get_surface_height(origin.x + i, origin.y + j) != whole[j * 64 + i]:
				column_mismatch += 1
	report.check_equal("single-column queries agree with block heights", column_mismatch, 0)


static func _test_cache_does_not_change_terrain(report) -> void:
	var surface := _make_surface(8642)

	var cached := surface.sample_block_heights(Vector2i(0, 0), Vector2i(48, 48))
	surface.set_cache_enabled(false)
	var uncached := surface.sample_block_heights(Vector2i(0, 0), Vector2i(48, 48))
	surface.set_cache_enabled(true)

	var mismatched := 0
	for i in range(cached.size()):
		if cached[i] != uncached[i]:
			mismatched += 1
	report.check_equal("disabling the node cache does not change a single height", mismatched, 0)


static func _test_concurrent_sampling_matches_serial(report) -> void:
	var surface := _make_surface(31337)

	var serial: Array[float] = []
	for i in range(512):
		serial.append(surface.get_surface_height(i - 256, 128 - i))

	var results := []
	results.resize(4)
	var threads: Array[Thread] = []

	for t in range(4):
		var slot := t
		var thread := Thread.new()
		threads.append(thread)
		thread.start(func() -> void:
			var out: Array[float] = []
			for i in range(512):
				out.append(surface.get_surface_height(i - 256, 128 - i))
			results[slot] = out
		)

	for thread in threads:
		thread.wait_to_finish()

	var mismatched := 0
	for t in range(4):
		var out: Array = results[t]
		if out.size() != serial.size():
			mismatched += 1
			continue
		for i in range(serial.size()):
			if out[i] != serial[i]:
				mismatched += 1
	report.check_equal(
			"concurrent sampling matches serial results on 4 threads", mismatched, 0,
			"shared node cache included"
	)


# ---------------------------------------------------------------------- fields

static func _test_field_ranges(report) -> void:
	var surface := _make_surface(1337)

	var continents_out := 0
	var elevation_out := 0
	var mountains_out := 0
	var hills_out := 0
	for point in _grid(24, Vector2i(-96, -96)):
		var continentalness := surface.get_field_at(&"continentalness", point.x, point.y)
		var elevation := surface.get_field_at(&"elevation", point.x, point.y)
		var mountainness := surface.get_field_at(&"mountainness", point.x, point.y)
		var hilliness := surface.get_field_at(&"hills", point.x, point.y)

		if continentalness < -1.0 or continentalness > 1.0:
			continents_out += 1
		if elevation < -1.0 or elevation > 1.0:
			elevation_out += 1
		if mountainness < 0.0 or mountainness > 1.0:
			mountains_out += 1
		if hilliness < 0.0 or hilliness > 1.0:
			hills_out += 1

	report.check_equal("continentalness stays within [-1, 1]", continents_out, 0)
	report.check_equal("elevation stays within [-1, 1]", elevation_out, 0)
	report.check_equal("mountainness stays within [0, 1]", mountains_out, 0)
	report.check_equal("hills stay within [0, 1]", hills_out, 0)


static func _test_continental_variety(report) -> void:
	var surface := _make_surface(1337)
	var ocean := 0
	var land := 0
	var total := 0
	for point in _grid(32, Vector2i(-128, -128)):
		total += 1
		if surface.get_field_at(&"continentalness", point.x, point.y) < SurfaceModule.OCEAN_EDGE:
			ocean += 1
		else:
			land += 1

	# "No repeating island patterns" is hard to assert directly; variety is the
	# honest proxy: a field that is all land or all ocean at this scale would mean
	# the field is not doing its job in the visible area.
	report.check("ocean covers a meaningful part of the sampled area", ocean > total / 10, "%d of %d" % [ocean, total])
	report.check("land covers a meaningful part of the sampled area", land > total / 10, "%d of %d" % [land, total])


static func _test_surface_bounds_across_seeds(report) -> void:
	var out_of_bounds := 0
	var checked := 0
	for raw_seed in [0, 1, 1337, 90210, -77]:
		var world_seed: int = raw_seed
		var surface := _make_surface(world_seed)
		for point in _grid(16, Vector2i(-64, -64)):
			checked += 1
			var height := surface.get_surface_height(point.x, point.y)
			if not is_finite(height) or height < SurfaceModule.MIN_HEIGHT or height > SurfaceModule.MAX_HEIGHT:
				out_of_bounds += 1
	report.check_equal(
			"surface height stays within the documented bounds for every seed",
			out_of_bounds, 0, "%d columns over 5 seeds" % checked
	)


static func _test_mountains_are_continuous(report) -> void:
	var surface := _make_surface(1337)
	var cells := {}
	var count := 48
	for j in range(count):
		for i in range(count):
			var point := _aligned(i - count / 2, j - count / 2)
			if surface.get_field_at(&"mountainness", point.x, point.y) >= SurfaceModule.MOUNTAIN_THRESHOLD:
				cells[Vector2i(i, j)] = true

	var isolated := 0
	for key in cells:
		var cell: Vector2i = key
		var has_neighbour := false
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				if cells.has(Vector2i(cell.x + dx, cell.y + dz)):
					has_neighbour = true
					break
			if has_neighbour:
				break
		if not has_neighbour:
			isolated += 1

	var fraction := float(isolated) / float(maxi(cells.size(), 1))
	report.check(
			"mountains form continuous ranges rather than isolated spikes",
			cells.size() > 0 and fraction < MAX_ISOLATED_MOUNTAIN_FRACTION,
			"%d mountain cells, %.1f%% isolated" % [cells.size(), fraction * 100.0]
	)


## Terrain types must be told apart by the landscape, not only by their labels.
##
## Two measurements, because plains, hills and mountains differ along two
## different axes:
## - [b]close-range roughness[/b], the mean height change between adjacent
##   columns, which is what separates flat plains from rolling hills;
## - [b]mean height[/b], which is what separates hills from mountains. Mountains
##   are not rougher than hills at a one-voxel scale - their slopes are long and
##   smooth - they simply rise much further, which is the property a viewer sees.
##
## Measured over a 384x384 area so a single mountain belt cannot dominate the
## averages.
static func _test_landform_separation(report) -> void:
	var surface := _make_surface(1337)
	var size := 384
	var origin := Vector2i(-192, -192)
	var heights := surface.sample_block_heights(origin, Vector2i(size, size))

	var roughness_sums := {}
	var height_sums := {}
	var counts := {}
	for j in range(0, size - 8, 4):
		for i in range(0, size - 8, 4):
			var kind := surface.classify_at(origin.x + i, origin.y + j)
			var here := heights[j * size + i]
			roughness_sums[kind] = float(roughness_sums.get(kind, 0.0)) + absf(heights[j * size + i + 1] - here)
			height_sums[kind] = float(height_sums.get(kind, 0.0)) + here
			counts[kind] = int(counts.get(kind, 0)) + 1

	var roughness := {}
	var mean_height := {}
	for kind in counts:
		roughness[kind] = float(roughness_sums[kind]) / float(counts[kind])
		mean_height[kind] = float(height_sums[kind]) / float(counts[kind])

	var plains := float(roughness.get(&"plains", 0.0))
	var hills := float(roughness.get(&"hills", 0.0))
	var plains_height := float(mean_height.get(&"plains", 0.0))
	var hills_height := float(mean_height.get(&"hills", 0.0))
	var mountains_height := float(mean_height.get(&"mountains", 0.0))

	report.check(
			"plains, hills and mountains all appear in the sampled area",
			int(counts.get(&"plains", 0)) > 0
					and int(counts.get(&"hills", 0)) > 0
					and int(counts.get(&"mountains", 0)) > 0,
			"plains=%d hills=%d mountains=%d" % [
				int(counts.get(&"plains", 0)),
				int(counts.get(&"hills", 0)),
				int(counts.get(&"mountains", 0)),
			]
	)
	report.check(
			"hills are visibly rougher than plains at close range",
			hills > plains * MIN_CLASS_ROUGHNESS_RATIO,
			"plains %.3f, hills %.3f (ratio %.2f)" % [plains, hills, hills / maxf(plains, 0.0001)]
	)
	report.check(
			"hills sit above plains",
			hills_height > plains_height + 2.0,
			"plains mean %.1f, hills mean %.1f" % [plains_height, hills_height]
	)
	report.check(
			"mountains rise well above hills",
			mountains_height > hills_height + 8.0,
			"hills mean %.1f, mountains mean %.1f" % [hills_height, mountains_height]
	)


## A coastline must not be a wall. Two checks, because a ratio alone can be made
## to pass by roughening the inland terrain:
## - [b]absolute[/b]: at the waterline the mean change between adjacent columns is
##   a small fraction of a voxel, i.e. a beach apron rather than a step;
## - [b]relative[/b]: the shoreline is gentler than the terrain inland.
##
## A third check scans the whole sampled area for column-to-column drops large
## enough to look like a cut face, which is what a discontinuity in the height
## field would produce.
static func _test_coastal_transition_is_smooth(report) -> void:
	var surface := _make_surface(1337)
	var sea_level := surface.get_sea_level()
	var near_sum := 0.0
	var near_count := 0
	var far_sum := 0.0
	var far_count := 0

	for j in range(0, 200, 2):
		for i in range(0, 200, 2):
			var x := i - 100
			var z := j - 100
			var here := surface.get_surface_height(x, z)
			var east := surface.get_surface_height(x + 1, z)
			var delta := absf(east - here)
			# Only columns that are themselves at the waterline: this is where a
			# naive implementation would produce a shear cliff.
			if absf(here - sea_level) < 2.0 and absf(east - sea_level) < 2.0:
				near_sum += delta
				near_count += 1
			else:
				far_sum += delta
				far_count += 1

	var near_mean := near_sum / maxf(float(near_count), 1.0)
	var far_mean := far_sum / maxf(float(far_count), 1.0)

	report.check(
			"the waterline is a gentle apron, not a step",
			near_count > 100 and near_mean < MAX_SHORELINE_SLOPE,
			"mean %.3f voxels per column (n=%d)" % [near_mean, near_count]
	)
	report.check(
			"the shoreline is gentler than the terrain inland",
			near_count > 100 and near_mean < far_mean * MAX_COAST_TO_INLAND_ROUGHNESS,
			"near sea %.3f, elsewhere %.3f" % [near_mean, far_mean]
	)

	# No column-to-column walls anywhere in the sampled area.
	var size := 256
	var heights := surface.sample_block_heights(Vector2i(-128, -128), Vector2i(size, size))
	var worst := 0.0
	for j in range(size):
		for i in range(size - 1):
			worst = maxf(worst, absf(heights[j * size + i + 1] - heights[j * size + i]))
	report.check(
			"no column-to-column cliff exists anywhere in the terrain",
			worst < MAX_COLUMN_STEP,
			"steepest step %.2f voxels (limit %.1f)" % [worst, MAX_COLUMN_STEP]
	)


static func _test_ocean_and_land_both_exist(report) -> void:
	var surface := _make_surface(1337)
	var sea_level := surface.get_sea_level()
	var below := 0
	var above := 0
	var total := 0
	for point in _grid(32, Vector2i(-128, -128)):
		total += 1
		if surface.get_surface_height(point.x, point.y) < sea_level:
			below += 1
		else:
			above += 1

	report.check("some terrain is below sea level", below > total / 5, "%d of %d columns" % [below, total])
	report.check("some terrain is above sea level", above > total / 5, "%d of %d columns" % [above, total])


# --------------------------------------------------------------- module system

static func _test_execution_order(report) -> void:
	var surface := _make_surface()
	var order := surface.get_module_ids()
	var expected := ["detail", "continentalness", "elevation", "mountainness", "hills", "surface"]

	var missing := PackedStringArray()
	for id in expected:
		if not order.has(id):
			missing.append(id)
	report.check(
			"all M1 modules are registered",
			missing.is_empty(),
			"registered order: %s" % String(", ".join(order))
	)

	var registry := TerrainGenerationStack.new(_make_config()).registry
	var violations := 0
	var modules := registry.get_ordered_modules()
	for i in range(modules.size()):
		var module := modules[i]
		for dependency in module.dependencies:
			var dependency_index := registry.get_module_output_index(StringName(dependency))
			if dependency_index < 0 or dependency_index >= i:
				violations += 1
				report.info("'%s' runs before its dependency '%s'" % [module.id, dependency])
	report.check_equal("every module runs after the modules it depends on", violations, 0)


static func _test_registry_rejects_duplicates(report) -> void:
	var registry := GenerationRegistry.new()
	var first := DummyModule.new(&"dummy", &"dummy_field", PackedStringArray())
	var duplicate := DummyModule.new(&"dummy", &"other_field", PackedStringArray())

	report.check("the first registration succeeds", registry.register(first))
	report.check("a duplicate module id is rejected", not registry.register(duplicate))

	var shared_field := DummyModule.new(&"other", &"dummy_field", PackedStringArray())
	report.check("a duplicate output field is rejected", not registry.register(shared_field))


static func _test_registry_rejects_unknown_dependency(report) -> void:
	var registry := GenerationRegistry.new()
	registry.register(DummyModule.new(&"needs_ghost", &"field_a", PackedStringArray(["ghost"])))
	# Expected to report an error to the log; what matters is the refusal.
	report.check("a dependency on an unregistered module fails resolution", not registry.resolve())


static func _test_registry_rejects_cycles(report) -> void:
	var registry := GenerationRegistry.new()
	registry.register(DummyModule.new(&"alpha", &"field_a", PackedStringArray(["beta"])))
	registry.register(DummyModule.new(&"beta", &"field_b", PackedStringArray(["alpha"])))
	report.check("a dependency cycle fails resolution", not registry.resolve())


static func _test_module_is_independently_testable(report) -> void:
	# A module can be configured and evaluated on its own, with no engine, no
	# world and no voxel tooling involved. That is what makes each field testable.
	var context := _make_context(1337)
	var module := ContinentalnessModule.new()
	module.bind(TerrainGenerationStack.new(_make_config()).registry)
	module.configure(context)
	module.assign_output_index(0)

	var values := PackedFloat32Array()
	values.resize(1)
	var out_of_range := 0
	var repeated_mismatch := 0
	for point in _grid(8, Vector2i(-32, -32)):
		module.evaluate_node(point.x, point.y, values)
		var value := values[0]
		if value < -1.0 or value > 1.0:
			out_of_range += 1
		module.evaluate_node(point.x, point.y, values)
		if values[0] != value:
			repeated_mismatch += 1

	report.check_equal("a module can be evaluated in isolation", out_of_range, 0)
	report.check_equal("a module evaluated twice at the same node is stable", repeated_mismatch, 0)


static func _test_configuration_is_snapshotted(report) -> void:
	var config := _make_config(2718)
	var surface := GeographicSurface.new(config)

	var points := _grid(10, Vector2i(0, 0))
	var before: Array[float] = []
	for point in points:
		before.append(surface.get_surface_height(point.x, point.y))

	# Edit the live resource after the surface was built.
	config.world_seed = 999999
	config.terrain_height = 1.0
	config.sea_level = -50.0

	var mismatched := 0
	for i in range(points.size()):
		var point := points[i]
		if surface.get_surface_height(point.x, point.y) != before[i]:
			mismatched += 1

	report.check_equal(
			"editing the configuration after build does not change the terrain", mismatched, 0)
	report.check_equal(
			"the surface reports the configuration it was built with",
			surface.get_sea_level(), WorldConfig.new().sea_level
	)


## Extensibility, tested rather than asserted: registering an unrelated module
## must not change any value the existing modules produce.
static func _test_adding_a_module_disturbs_nothing(report) -> void:
	var config := _make_config(1337)

	var plain := TerrainGenerationStack.new(config)
	var before: Array[float] = []
	for point in _grid(10, Vector2i(-40, -40)):
		before.append(plain.engine.get_field_at(&"continentalness", point.x, point.y))

	var extended := TerrainGenerationStack.new(config)
	var added := extended.registry.register(
			DummyModule.new(&"extra_field_module", &"extra", PackedStringArray(["continentalness"]))
	)
	var resolved := extended.registry.resolve()

	report.check("an additional module can be registered and resolved", added and resolved)

	# Rebuild the engine so it picks up the new graph, then compare.
	var engine := GenerationEngine.new(extended.context, extended.registry)
	var mismatched := 0
	var index := 0
	for point in _grid(10, Vector2i(-40, -40)):
		if engine.get_field_at(&"continentalness", point.x, point.y) != before[index]:
			mismatched += 1
		index += 1

	report.check_equal("adding a module leaves existing module values untouched", mismatched, 0)


# ----------------------------------------------------------------- integration

static func _test_generator_matches_the_surface(report) -> void:
	var surface := _make_surface(1337)
	var generator := TerrainBlockGenerator.new()
	generator.configure(surface, BlockPalette.new())
	var block_size := 16

	var checked := 0
	var mismatched := 0
	for block_index in range(4):
		var origin := Vector3i(block_index * block_size, 0, 0)
		var buffer := VoxelBuffer.new()
		buffer.create(block_size, block_size, block_size)
		buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
		generator._generate_block(buffer, origin, 0)

		for z in range(0, block_size, 5):
			for x in range(0, block_size, 5):
				var world_x := origin.x + x
				var height := surface.get_surface_height(world_x, z)
				var expected_top := int(floor(height))
				var actual_top := -1
				for y in range(block_size - 1, -1, -1):
					if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) != BlockPalette.AIR:
						actual_top = y
						break
				# The block spans y = 0..15; a surface above it clamps to the top.
				var clamped_expected := mini(expected_top, block_size - 1)
				checked += 1
				if actual_top != clamped_expected:
					mismatched += 1
					report.info(
							"block %d column (%d, %d): expected top %d, got %d"
							% [block_index, world_x, z, clamped_expected, actual_top]
					)

	report.check(
			"Voxel Tools receives the surface the pipeline reports",
			mismatched == 0,
			"%d columns across 4 blocks, %d mismatched" % [checked, mismatched]
	)


static func _test_terrain_varies_within_a_region(report) -> void:
	var surface := _make_surface(1337)
	var heights := surface.sample_block_heights(Vector2i(-64, -64), Vector2i(128, 128))
	var minimum := INF
	var maximum := -INF
	for height in heights:
		minimum = minf(minimum, height)
		maximum = maxf(maximum, height)

	# A single noise band would also vary; what this catches is a pipeline that
	# silently collapses to one field (for example a composer that never reads
	# mountainness), which shows up as a much smaller range.
	report.check(
			"the composed surface has real relief across a streamed region",
			maximum - minimum > 20.0,
			"range %.1f..%.1f (%.1f voxels)" % [minimum, maximum, maximum - minimum]
	)


## Minimal module used to exercise registration and extensibility. It reads a
## declared dependency and writes one field, which is the whole module contract.
class DummyModule:
	extends GenerationModule

	func _init(
			p_id: StringName,
			p_output: StringName,
			p_dependencies: PackedStringArray
	) -> void:
		super(p_id, p_output, p_dependencies, 1)

	func configure(_context: GenerationContext) -> void:
		pass

	func evaluate_node(_x: int, _z: int, values: PackedFloat32Array) -> void:
		values[get_output_index()] = 0.5
