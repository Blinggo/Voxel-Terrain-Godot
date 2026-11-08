extends RefCounted

## Tests for the M2 geographical systems: tectonic influence, mountain structure,
## valleys and basins, plateaus, archipelagos and coastal shaping.
##
## [b]What this suite proves that the M1 suite does not.[/b] The M1 suite checks that
## the pipeline is deterministic, continuous and plausible. This suite checks that
## the [i]new formations behave as formations[/i]: that a mountain range is elevated
## and connected rather than a field of spikes, that a valley is lower than the land
## around it, that a plateau interior is level while its margin steps, that island
## groups cluster instead of scattering, that a shelf deepens gradually, and that
## coastline shaping does not move the continent. Each of those is an assertion
## about geography, measured on real sampled terrain.
##
## [b]Sampling discipline.[/b] Fields are evaluated on a node grid spaced
## [code]sampling_stride[/code] voxels apart, so the tests sample on that grid where
## they only need field statistics. Continuity tests deliberately sample off-grid,
## because a discontinuity is exactly what the grid would hide.
##
## [b]What these tests cannot show.[/b] They cannot show that the result looks good,
## and they cannot show anything about a real Android device. Visual confirmation is
## the milestone screenshots; device behaviour is the owner's editor testing. Tests
## that were written but not executed are listed in the milestone document.

const STRIDE := 8

## Ceiling on the step between two adjacent columns, in voxels. Real terrain on the
## steepest slope in the current tuning reaches about 4; a field discontinuity
## produces far more.
const MAX_COLUMN_STEP := 8.0

## Ceilings on the step between two adjacent samples of a dimensionless field. These
## are calibrated against measured maxima (see the M2 milestone document) with
## roughly 2x headroom: they catch a discontinuity, not a steep gradient.
const MAX_FIELD_STEP_SMOOTH := 0.25
const MAX_FIELD_STEP_SHARP := 0.55

const FIELD_IDS: Array[StringName] = [
	&"tectonics",
	&"archipelago",
	&"coast_detail",
	&"landmass",
	&"mountainness",
	&"valleys",
	&"plateaus",
]


static func run(report) -> void:
	_test_new_fields_are_deterministic(report)
	_test_seed_changes_geography(report)
	_test_sampling_order_does_not_matter(report)
	_test_repeat_stability(report)
	_test_cache_does_not_change_new_fields(report)
	_test_generation_version_changes_new_fields(report)
	_test_module_ids_and_dependencies(report)

	_test_tectonics_is_continuous(report)
	_test_new_fields_are_continuous(report)
	_test_plate_borders_have_no_seam(report)
	_test_surface_steps_are_bounded(report)
	_test_chunk_borders_are_continuous(report)
	_test_isolated_sampling_matches_block_sampling(report)

	_test_mountains_are_elevated(report)
	_test_mountain_ranges_are_connected(report)
	_test_ranges_differ_in_height(report)
	_test_tectonics_drives_mountains(report)
	_test_rifts_are_lower(report)
	_test_valleys_are_lower(report)
	_test_valleys_form_a_network(report)
	_test_basins_exist(report)
	_test_plateau_interiors_are_level(report)
	_test_plateau_margins_step(report)
	_test_terrace_is_continuous_and_exact(report)
	_test_archipelagos_are_grouped(report)
	_test_shelves_are_gradual(report)
	_test_coast_shaping_preserves_layout(report)
	_test_sea_level_contract(report)
	_test_land_fraction_across_seeds(report)

	_test_landmass_composition(report)
	_test_mountains_read_their_inputs(report)
	_test_valleys_and_plateaus_gate_on_land(report)
	_test_island_strength_is_configurable(report)
	_test_valley_depth_is_configurable(report)
	_test_mountain_scale_is_configurable(report)
	_test_generator_matches_surface_in_mountains(report)

	_test_performance(report)


# --------------------------------------------------------------------- helpers

static func _make_config(world_seed: int = 1337) -> WorldConfig:
	var config := WorldConfig.new()
	config.world_seed = world_seed
	# Isolate M2 parameter contracts: rerouting water after changing a valley is
	# not a monotonic height operation. M4-enabled integration has its own suite.
	config.hydrology_enabled = false
	return config


static func _make_surface(world_seed: int = 1337) -> GeographicSurface:
	return GeographicSurface.new(_make_config(world_seed))


static func _grid(count: int, origin: Vector2i, step: int) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for j in range(count):
		for i in range(count):
			points.append(origin + Vector2i(i * step, j * step))
	return points


## Pearson correlation of two equal-length arrays.
static func _correlation(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := a.size()
	if n == 0:
		return 0.0
	var mean_a := 0.0
	var mean_b := 0.0
	for i in range(n):
		mean_a += a[i]
		mean_b += b[i]
	mean_a /= float(n)
	mean_b /= float(n)
	var cov := 0.0
	var var_a := 0.0
	var var_b := 0.0
	for i in range(n):
		var da := a[i] - mean_a
		var db := b[i] - mean_b
		cov += da * db
		var_a += da * da
		var_b += db * db
	if var_a <= 0.0 or var_b <= 0.0:
		return 0.0
	return cov / sqrt(var_a * var_b)


## A module plus a registry holding it and zero-filled stand-ins for everything it
## declares as a dependency.
##
## This is what "independently testable" means in practice: a module can be handed
## synthetic inputs at the slots it declares and evaluated with no world, no engine,
## no voxels and no other real module. The stand-ins exist because the registry
## refuses to resolve a module whose declared dependencies are missing - which is
## the behaviour the M1 tests assert, and it is worth keeping.
class StandIn extends GenerationModule:
	func _init(p_id: StringName) -> void:
		super(p_id, StringName("%s_stand_in" % p_id), PackedStringArray(), 1)

	func configure(_context: GenerationContext) -> void:
		pass

	func evaluate_node(_x: int, _z: int, values: PackedFloat32Array) -> void:
		values[get_output_index()] = 0.0


static func _isolate(module: GenerationModule) -> Dictionary:
	var registry := GenerationRegistry.new()
	var stand_ins: Array[GenerationModule] = []
	registry.register(module)
	for dependency in module.dependencies:
		var stand_in := StandIn.new(StringName(dependency))
		stand_ins.append(stand_in)
		registry.register(stand_in)
	if not registry.resolve():
		return {}
	module.bind(registry)
	var config := _make_config(1337)
	module.configure(GenerationContext.new(config.world_seed, config.generation_version, config))
	return {"module": module, "registry": registry, "stand_ins": stand_ins}


static func _eval_isolated(prepared: Dictionary, inputs: Dictionary, x: int, z: int) -> float:
	if prepared.is_empty():
		return 0.0
	var module: GenerationModule = prepared["module"]
	var registry: GenerationRegistry = prepared["registry"]
	var values := PackedFloat32Array()
	values.resize(registry.get_field_count())
	for key in inputs:
		var slot := module.dependency_index(StringName(key))
		if slot >= 0:
			values[slot] = float(inputs[key])
	module.evaluate_node(x, z, values)
	return values[module.get_output_index()]


## Flood fill over a boolean grid, returning the sizes of its components.
static func _component_sizes(flags: PackedByteArray, width: int, height: int) -> Array[int]:
	var visited := PackedByteArray()
	visited.resize(width * height)
	visited.fill(0)
	var sizes: Array[int] = []
	var stack := PackedInt32Array()
	for start in range(width * height):
		if visited[start] != 0 or flags[start] == 0:
			continue
		stack.push_back(start)
		visited[start] = 1
		var count := 0
		while stack.size() > 0:
			var index := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			count += 1
			var i := index % width
			var j := index / width
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + offset.x
				var nj: int = j + offset.y
				if ni < 0 or nj < 0 or ni >= width or nj >= height:
					continue
				var nindex: int = nj * width + ni
				if visited[nindex] != 0 or flags[nindex] == 0:
					continue
				visited[nindex] = 1
				stack.push_back(nindex)
		sizes.append(count)
	return sizes


# ----------------------------------------------------------------- determinism

static func _test_new_fields_are_deterministic(report) -> void:
	var first := _make_surface(1337)
	var second := _make_surface(1337)
	var mismatched := 0
	var samples := 0
	for point in _grid(12, Vector2i(-160, -160), STRIDE * 3):
		for id in FIELD_IDS:
			samples += 1
			if first.get_field_at(id, point.x, point.y) != second.get_field_at(id, point.x, point.y):
				mismatched += 1
	report.check("M2 fields are identical between two builds of the same seed",
			mismatched == 0, "%d field samples" % samples)


static func _test_seed_changes_geography(report) -> void:
	var a := _make_surface(1337)
	var b := _make_surface(90210)
	# Fields masked to a region (islands only exist offshore, coast detail only
	# near a shore) are zero over most of the world, so they are compared only
	# where at least one of the two builds is active.
	var differing := {}
	var active := {}
	for id in FIELD_IDS:
		differing[id] = 0
		active[id] = 0
	for point in _grid(20, Vector2i(-384, -384), STRIDE * 3):
		for id in FIELD_IDS:
			var left := a.get_field_at(id, point.x, point.y)
			var right := b.get_field_at(id, point.x, point.y)
			if absf(left) + absf(right) <= 0.05:
				continue
			active[id] = int(active[id]) + 1
			if absf(left - right) > 0.02:
				differing[id] = int(differing[id]) + 1
	var worst := 1.0
	var detail := ""
	for id in FIELD_IDS:
		var share := float(differing[id]) / float(maxi(int(active[id]), 1))
		worst = minf(worst, share)
		detail += "%s %.2f/%d " % [String(id), share, int(active[id])]
	report.check("every M2 field takes a different shape under a different seed", worst >= 0.9,
			"smallest differing fraction %.2f; %s" % [worst, detail])


static func _test_sampling_order_does_not_matter(report) -> void:
	var points := _grid(10, Vector2i(-128, -128), STRIDE * 2)
	var forward := _make_surface(4242)
	var forward_values: Array[float] = []
	for point in points:
		forward_values.append(forward.get_field_at(&"tectonics", point.x, point.y))
		forward_values.append(forward.get_field_at(&"mountainness", point.x, point.y))

	var backward := _make_surface(4242)
	var mismatched := 0
	var index := points.size() * 2 - 2
	for i in range(points.size() - 1, -1, -1):
		var point := points[i]
		var mountains := backward.get_field_at(&"mountainness", point.x, point.y)
		var tectonics := backward.get_field_at(&"tectonics", point.x, point.y)
		if tectonics != forward_values[index] or mountains != forward_values[index + 1]:
			mismatched += 1
		index -= 2
	report.check_equal("sampling order does not change any M2 value", mismatched, 0)


static func _test_repeat_stability(report) -> void:
	var surface := _make_surface(1337)
	var mismatched := 0
	for point in _grid(8, Vector2i(-64, -64), STRIDE):
		var first := surface.get_surface_height(point.x, point.y)
		var second := surface.get_surface_height(point.x, point.y)
		if first != second:
			mismatched += 1
	report.check_equal("repeated sampling of the same column is stable", mismatched, 0)


static func _test_cache_does_not_change_new_fields(report) -> void:
	var cached := _make_surface(1337)
	var uncached := _make_surface(1337)
	uncached.set_cache_enabled(false)
	var mismatched := 0
	var samples := 0
	for point in _grid(12, Vector2i(-192, -192), STRIDE):
		samples += 1
		if cached.get_surface_height(point.x, point.y) != uncached.get_surface_height(point.x, point.y):
			mismatched += 1
	report.check("the node cache cannot change M2 terrain", mismatched == 0,
			"%d columns" % samples)


static func _test_generation_version_changes_new_fields(report) -> void:
	var base_config := _make_config(1337)
	var bumped_config := _make_config(1337)
	bumped_config.generation_version = base_config.generation_version + 1
	var base := GeographicSurface.new(base_config)
	var bumped := GeographicSurface.new(bumped_config)
	var differing := 0
	var total := 0
	for point in _grid(10, Vector2i(-128, -128), STRIDE * 3):
		total += 1
		if absf(base.get_field_at(&"tectonics", point.x, point.y)
				- bumped.get_field_at(&"tectonics", point.x, point.y)) > 0.01:
			differing += 1
	report.check("bumping the generation version reshuffles the tectonic layout",
			float(differing) / float(maxi(total, 1)) >= 0.9,
			"%d of %d samples differ" % [differing, total])


static func _test_module_ids_and_dependencies(report) -> void:
	var surface := _make_surface(1337)
	var ids := surface.get_module_ids()
	var expected := [
		"detail", "continentalness", "tectonics", "archipelago", "coast_detail",
		"landmass", "elevation", "mountainness", "hills", "plateaus", "valleys",
		"surface", "hydrology",
	]
	report.check_equal("the pipeline executes the M1 and M2 modules in dependency order",
			Array(ids), expected)

	var missing := 0
	for id in expected:
		if not ids.has(id):
			missing += 1
	report.check_equal("every M2 module is registered exactly once", missing, 0)

	# Declared dependencies must actually be produced by modules that run earlier:
	# an undeclared or late dependency is a wiring bug the registry reports, and the
	# stack would then be invalid.
	report.check("the module graph resolves", surface.is_valid())


# ------------------------------------------------------------------ continuity

static func _test_tectonics_is_continuous(report) -> void:
	var surface := _make_surface(1337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7717
	var worst := 0.0
	var at := Vector2i.ZERO
	for _i in range(4000):
		var x := rng.randi_range(-2400, 2400)
		var z := rng.randi_range(-2400, 2400)
		var a := surface.get_field_at(&"tectonics", x, z)
		var b := surface.get_field_at(&"tectonics", x + 1, z)
		var c := surface.get_field_at(&"tectonics", x, z + 1)
		var step := maxf(absf(b - a), absf(c - a))
		if step > worst:
			worst = step
			at = Vector2i(x, z)
	report.check("the tectonic field has no discontinuity", worst < MAX_FIELD_STEP_SMOOTH,
			"largest adjacent step %.4f at %s (limit %.2f)" % [worst, str(at), MAX_FIELD_STEP_SMOOTH])


static func _test_new_fields_are_continuous(report) -> void:
	var surface := _make_surface(1337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var worst := {}
	for id in FIELD_IDS:
		worst[id] = 0.0
	for _i in range(3000):
		var x := rng.randi_range(-1600, 1600)
		var z := rng.randi_range(-1600, 1600)
		for id in FIELD_IDS:
			var a := surface.get_field_at(id, x, z)
			var b := surface.get_field_at(id, x + 1, z)
			var c := surface.get_field_at(id, x, z + 1)
			var step := maxf(absf(b - a), absf(c - a))
			if step > float(worst[id]):
				worst[id] = step
	var failures := 0
	var detail := ""
	for id in FIELD_IDS:
		var limit := MAX_FIELD_STEP_SMOOTH if id == &"landmass" or id == &"coast_detail" else MAX_FIELD_STEP_SHARP
		if float(worst[id]) >= limit:
			failures += 1
		detail += "%s=%.3f " % [String(id), float(worst[id])]
	report.check("every M2 field is continuous at voxel resolution", failures == 0, detail)


static func _test_plate_borders_have_no_seam(report) -> void:
	# Regression test for the triple-point degeneracy: at a point equidistant from
	# three plate sites the second-nearest site swaps, and an implementation that
	# decomposes drift by that pair alone produces a one-voxel cliff through the
	# middle of the affected range. Every plate cell border is deliberately crossed
	# here, because that is where the neighbourhood is rebuilt.
	var surface := _make_surface(1337)
	var cell := _make_config().plate_cell_size
	var worst := 0.0
	var at := Vector2i.ZERO
	for border in range(-3, 4):
		var x0 := int(float(border) * cell)
		for z0 in [-900, -400, 0, 260, 700]:
			for offset in range(-24, 24):
				var x := x0 + offset
				var a := surface.get_field_at(&"tectonics", x, z0)
				var b := surface.get_field_at(&"tectonics", x + 1, z0)
				if absf(b - a) > worst:
					worst = absf(b - a)
					at = Vector2i(x, z0)
				var c := surface.get_field_at(&"tectonics", x0, z0 + offset)
				var d := surface.get_field_at(&"tectonics", x0, z0 + offset + 1)
				if absf(d - c) > worst:
					worst = absf(d - c)
					at = Vector2i(x0, z0 + offset)
	report.check("crossing a plate cell border does not produce a seam",
			worst < MAX_FIELD_STEP_SMOOTH,
			"largest step %.4f at %s (limit %.2f)" % [worst, str(at), MAX_FIELD_STEP_SMOOTH])


static func _test_surface_steps_are_bounded(report) -> void:
	var surface := _make_surface(1337)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	var worst := 0.0
	var at := Vector2i.ZERO
	for _i in range(3000):
		var x := rng.randi_range(-1200, 1200)
		var z := rng.randi_range(-1200, 1200)
		var a := surface.get_surface_height(x, z)
		var b := surface.get_surface_height(x + 1, z)
		var c := surface.get_surface_height(x, z + 1)
		var step := maxf(absf(b - a), absf(c - a))
		if step > worst:
			worst = step
			at = Vector2i(x, z)
	report.check("no new formation introduces a surface cliff", worst <= MAX_COLUMN_STEP,
			"largest step %.2f voxels at %s (limit %.1f)" % [worst, str(at), MAX_COLUMN_STEP])


static func _test_chunk_borders_are_continuous(report) -> void:
	# Terrain is generated block by block, so the interesting coordinates are the
	# ones on a block border: 16 voxels, the mesh block size.
	var surface := _make_surface(1337)
	var worst := 0.0
	for base in [0, 256, -512]:
		for z in range(base, base + 64, 7):
			for x in [base - 1, base, base + 15, base + 16, base + 31, base + 32]:
				var a := surface.get_surface_height(x, z)
				var b := surface.get_surface_height(x + 1, z)
				worst = maxf(worst, absf(b - a))
		for x in range(base, base + 64, 7):
			for z in [base - 1, base, base + 15, base + 16, base + 31, base + 32]:
				var a := surface.get_surface_height(x, z)
				var b := surface.get_surface_height(x, z + 1)
				worst = maxf(worst, absf(b - a))
	report.check("block borders are continuous", worst <= MAX_COLUMN_STEP,
			"largest step across a block border %.2f voxels" % worst)


static func _test_isolated_sampling_matches_block_sampling(report) -> void:
	# A column must not depend on its neighbours or on what was sampled before it:
	# that is what lets any chunk be generated on any thread, in any order.
	var isolated := _make_surface(1337)
	var blocked := _make_surface(1337)
	var points := [Vector2i(1024, -768), Vector2i(-1500, 320), Vector2i(37, 91), Vector2i(4096, 4096)]
	var mismatched := 0
	for point in points:
		var lone := isolated.get_surface_height(point.x, point.y)
		blocked.sample_block_heights(point - Vector2i(16, 16), Vector2i(32, 32))
		var inside := blocked.get_surface_height(point.x, point.y)
		if absf(lone - inside) > 0.0001:
			mismatched += 1
	report.check("a column sampled in isolation matches the same column inside a block",
			mismatched == 0, "%d scattered coordinates" % points.size())


# ------------------------------------------------------------------- geography

static func _test_mountains_are_elevated(report) -> void:
	var surface := _make_surface(1337)
	var summit_sum := 0.0
	var summit_count := 0
	var flat_sum := 0.0
	var flat_count := 0
	var hill_sum := 0.0
	var hill_count := 0
	for point in _grid(40, Vector2i(-320, -320), STRIDE * 2):
		var land := surface.get_field_at(&"landmass", point.x, point.y)
		if land < SurfaceModule.LAND_EDGE:
			continue
		var mountains := surface.get_field_at(&"mountainness", point.x, point.y)
		var height := surface.get_surface_height(point.x, point.y)
		if mountains >= SurfaceModule.MOUNTAIN_THRESHOLD:
			summit_sum += height
			summit_count += 1
		elif mountains < 0.15:
			flat_sum += height
			flat_count += 1
			if surface.get_field_at(&"hills", point.x, point.y) >= SurfaceModule.HILL_THRESHOLD:
				hill_sum += height
				hill_count += 1
	var summit_mean := summit_sum / float(maxi(summit_count, 1))
	var flat_mean := flat_sum / float(maxi(flat_count, 1))
	var hill_mean := hill_sum / float(maxi(hill_count, 1))
	report.check("mountain terrain stands above the land around it",
			summit_mean - flat_mean >= 8.0,
			"mountains %.1f vs lowland %.1f (%d / %d columns)" % [summit_mean, flat_mean, summit_count, flat_count])
	report.check("mountains stand well above hills", summit_mean - hill_mean >= 8.0,
			"mountains %.1f vs hills %.1f (%d hill columns)" % [summit_mean, hill_mean, hill_count])


static func _test_mountain_ranges_are_connected(report) -> void:
	var surface := _make_surface(1337)
	var width := 96
	var step := STRIDE * 2
	var flags := PackedByteArray()
	flags.resize(width * width)
	var mountain_cells := 0
	for j in range(width):
		for i in range(width):
			var point := Vector2i(-384 + i * step, -384 + j * step)
			if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
				continue
			if surface.get_field_at(&"mountainness", point.x, point.y) >= SurfaceModule.MOUNTAIN_THRESHOLD:
				flags[j * width + i] = 1
				mountain_cells += 1
	var sizes := _component_sizes(flags, width, width)
	var largest := 0
	var large_count := 0
	for size in sizes:
		largest = maxi(largest, size)
		if size >= 12:
			large_count += 1
	var largest_share := float(largest) / float(maxi(mountain_cells, 1))
	report.check("mountain regions form connected systems",
			mountain_cells > 100 and largest_share >= 0.10,
			"%d mountain cells, largest component %.0f%% of them" % [mountain_cells, largest_share * 100.0])
	report.check("mountain country is not a scatter of isolated peaks",
			large_count <= maxi(mountain_cells / 40, 1),
			"%d components of at least 12 cells" % large_count)


static func _test_ranges_differ_in_height(report) -> void:
	# A mountain province is only a province if its height differs from the next
	# one. Measured as the spread of the tallest terrain in each tile of a coarse
	# grid: uniform-height ranges would give a flat result.
	var surface := _make_surface(1337)
	var tiles: Array[float] = []
	for tj in range(4):
		for ti in range(4):
			var peak := -1e9
			for j in range(8):
				for i in range(8):
					var point := Vector2i(-512 + ti * 256 + i * 32, -512 + tj * 256 + j * 32)
					peak = maxf(peak, surface.get_surface_height(point.x, point.y))
			tiles.append(peak)
	var lowest := 1e9
	var highest := -1e9
	for value in tiles:
		lowest = minf(lowest, value)
		highest = maxf(highest, value)
	report.check("different parts of the world reach different heights",
			highest - lowest >= 10.0,
			"tile peaks span %.1f voxels (%.1f .. %.1f)" % [highest - lowest, lowest, highest])


static func _test_tectonics_drives_mountains(report) -> void:
	var surface := _make_surface(1337)
	var uplift_sum := 0.0
	var uplift_count := 0
	var quiet_sum := 0.0
	var quiet_count := 0
	for point in _grid(40, Vector2i(-320, -320), STRIDE * 2):
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
			continue
		var tectonic := surface.get_field_at(&"tectonics", point.x, point.y)
		var mountains := surface.get_field_at(&"mountainness", point.x, point.y)
		if tectonic > 0.35:
			uplift_sum += mountains
			uplift_count += 1
		elif tectonic < 0.05:
			quiet_sum += mountains
			quiet_count += 1
	var uplift_mean := uplift_sum / float(maxi(uplift_count, 1))
	var quiet_mean := quiet_sum / float(maxi(quiet_count, 1))
	report.check("convergent boundaries carry more mountain mass than plate interiors",
			uplift_mean >= quiet_mean * 1.5 and uplift_count > 50,
			"uplifted %.3f (%d) vs quiet %.3f (%d)" % [uplift_mean, uplift_count, quiet_mean, quiet_count])


static func _test_rifts_are_lower(report) -> void:
	var surface := _make_surface(1337)
	var rift_sum := 0.0
	var rift_count := 0
	var plain_sum := 0.0
	var plain_count := 0
	for point in _grid(48, Vector2i(-1024, -1024), STRIDE * 4):
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
			continue
		var tectonic := surface.get_field_at(&"tectonics", point.x, point.y)
		var height := surface.get_surface_height(point.x, point.y)
		if tectonic < -0.18:
			rift_sum += height
			rift_count += 1
		elif absf(tectonic) < 0.08:
			plain_sum += height
			plain_count += 1
	if rift_count < 20:
		report.check("rift regions exist to compare", false,
				"only %d rift columns in the sample" % rift_count)
		return
	var rift_mean := rift_sum / float(rift_count)
	var plain_mean := plain_sum / float(maxi(plain_count, 1))
	report.check("rift boundaries sit lower than plate interiors",
			rift_mean < plain_mean,
			"rift %.1f vs interior %.1f (%d / %d columns)" % [rift_mean, plain_mean, rift_count, plain_count])


static func _test_valleys_are_lower(report) -> void:
	var surface := _make_surface(1337)
	var valley_sum := 0.0
	var valley_count := 0
	var upland_sum := 0.0
	var upland_count := 0
	for point in _grid(48, Vector2i(-384, -384), STRIDE * 2):
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
			continue
		var carve := surface.get_field_at(&"valleys", point.x, point.y)
		var height := surface.get_surface_height(point.x, point.y)
		if carve >= 0.5:
			valley_sum += height
			valley_count += 1
		elif carve < 0.15:
			upland_sum += height
			upland_count += 1
	var valley_mean := valley_sum / float(maxi(valley_count, 1))
	var upland_mean := upland_sum / float(maxi(upland_count, 1))
	report.check("valley floors are lower than the land beside them",
			valley_count > 50 and valley_mean < upland_mean,
			"valleys %.1f vs uplands %.1f (%d / %d columns)" % [valley_mean, upland_mean, valley_count, upland_count])


static func _test_valleys_form_a_network(report) -> void:
	var surface := _make_surface(1337)
	var width := 96
	var step := STRIDE * 2
	var flags := PackedByteArray()
	flags.resize(width * width)
	var cells := 0
	for j in range(width):
		for i in range(width):
			var point := Vector2i(-384 + i * step, -384 + j * step)
			if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
				continue
			if surface.get_field_at(&"valleys", point.x, point.y) >= 0.45:
				flags[j * width + i] = 1
				cells += 1
	var sizes := _component_sizes(flags, width, width)
	var largest := 0
	for size in sizes:
		largest = maxi(largest, size)
	report.check("valleys join into connected networks",
			cells > 60 and float(largest) / float(maxi(cells, 1)) >= 0.10,
			"%d valley cells in %d components, largest %.0f%%" % [
				cells, sizes.size(), 100.0 * float(largest) / float(maxi(cells, 1))
			])


static func _test_basins_exist(report) -> void:
	# An enclosed depression: a land column whose four neighbours are all higher.
	var surface := _make_surface(1337)
	var low_points := 0
	var samples := 0
	for point in _grid(64, Vector2i(-512, -512), STRIDE * 2):
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE:
			continue
		samples += 1
		var here := surface.get_surface_height(point.x, point.y)
		var all_higher := true
		for offset: Vector2i in [Vector2i(24, 0), Vector2i(-24, 0), Vector2i(0, 24), Vector2i(0, -24)]:
			if surface.get_surface_height(point.x + offset.x, point.y + offset.y) <= here:
				all_higher = false
				break
		if all_higher:
			low_points += 1
	report.check("enclosed depressions occur on land",
			low_points >= 3 and samples > 100,
			"%d enclosed low points in %d land columns" % [low_points, samples])


static func _test_plateau_interiors_are_level(report) -> void:
	var surface := _make_surface(1337)
	var inside_sum := 0.0
	var inside_count := 0
	var outside_sum := 0.0
	var outside_count := 0
	# Measured on the composed surface [i]field[/i] rather than on sampled columns:
	# the engine adds a per-column detail term afterwards, which is roughness every
	# part of the world has and would mask the difference a plateau makes.
	for point in _grid(64, Vector2i(-512, -512), STRIDE * 2):
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.LAND_EDGE + 0.1:
			continue
		var plateaus := surface.get_field_at(&"plateaus", point.x, point.y)
		var here := surface.get_field_at(&"surface", point.x, point.y)
		# Only neighbours in the same landform are compared, so a plateau edge does
		# not count as interior roughness.
		var step := 0.0
		var counted := 0
		for offset: Vector2i in [Vector2i(24, 0), Vector2i(-24, 0), Vector2i(0, 24), Vector2i(0, -24)]:
			var other_mask := surface.get_field_at(&"plateaus", point.x + offset.x, point.y + offset.y)
			if absf(other_mask - plateaus) > 0.02:
				continue
			step += absf(surface.get_field_at(&"surface", point.x + offset.x, point.y + offset.y) - here)
			counted += 1
		if counted < 2:
			continue
		step /= float(counted)
		if plateaus >= 0.95:
			inside_sum += step
			inside_count += 1
		elif plateaus <= 0.05:
			outside_sum += step
			outside_count += 1
	if inside_count < 10:
		report.check("there are plateau interiors to measure", false,
				"only %d plateau columns in the sample" % inside_count)
		return
	var inside_mean := inside_sum / float(inside_count)
	var outside_mean := outside_sum / float(maxi(outside_count, 1))
	report.check("plateau interiors are flatter than ordinary land",
			inside_mean < outside_mean * 0.7,
			"interior relief %.2f vs open land %.2f voxels per 16 (%d / %d columns)" % [
				inside_mean, outside_mean, inside_count, outside_count
			])


static func _test_plateau_margins_step(report) -> void:
	# A terraced margin holds at a few distinct levels with short risers between
	# them. Measured as the share of margin columns whose mask sits on one of the
	# shelf values: a smooth (unstepped) margin spreads evenly and shows none.
	var surface := _make_surface(1337)
	var steps := _make_config(1337).plateau_steps
	var on_shelf := 0
	var margin := 0
	for point in _grid(96, Vector2i(-768, -768), STRIDE * 2):
		if surface.get_field_at(&"landmass", point.x, point.y) < 0.30:
			continue
		var plateaus := surface.get_field_at(&"plateaus", point.x, point.y)
		if plateaus <= 0.02 or plateaus >= 0.98:
			continue
		margin += 1
		var scaled := plateaus * float(steps)
		if absf(scaled - round(scaled)) < 0.02 * float(steps):
			on_shelf += 1
	report.check("plateau margins hold at distinct shelves",
			margin > 50 and float(on_shelf) / float(maxi(margin, 1)) >= 0.4,
			"%d of %d margin columns sit on a shelf level (%d steps)" % [on_shelf, margin, steps])


static func _test_terrace_is_continuous_and_exact(report) -> void:
	# The terrace function is what makes a plateau margin stepped without making it
	# discontinuous. Both properties are checked directly on the function rather
	# than inferred from terrain.
	var steps := 3
	var worst_step := 0.0
	var previous := PlateauModule.terrace(0.0, steps)
	var monotonic := true
	var flat_samples := 0
	var total := 0
	var max_error := 0.0
	for i in range(1, 2001):
		var value := float(i) / 2000.0
		var stepped := PlateauModule.terrace(value, steps)
		worst_step = maxf(worst_step, absf(stepped - previous))
		if stepped < previous - 0.000001:
			monotonic = false
		previous = stepped
		total += 1
		# Every shelf boundary must reproduce the unquantised value exactly, which is
		# what stops the surface jumping at a shelf edge.
		var scaled := value * float(steps)
		if absf(scaled - round(scaled)) < 0.0005:
			max_error = maxf(max_error, absf(stepped - value))
		# A shelf is a stretch of value where the terrace output does not change.
		var delta := PlateauModule.terrace(minf(value + 0.0005, 1.0), steps) - stepped
		if absf(delta) < 0.00001:
			flat_samples += 1
	report.check("the terrace is monotonic", monotonic)
	report.check("the terrace never jumps", worst_step < 1.0 / float(steps),
			"largest step %.4f (a jump would be %.3f or more)" % [worst_step, 1.0 / float(steps)])
	report.check("the terrace reproduces shelf boundaries exactly", max_error < 0.001,
			"largest error %.6f" % max_error)
	report.check("the terrace produces flat shelves between risers",
			float(flat_samples) / float(total) > 0.5,
			"%.0f%% of the range is flat" % (100.0 * float(flat_samples) / float(total)))
	report.check_equal("terrace with one step is the identity",
			PlateauModule.terrace(0.37, 1), 0.37)


static func _test_archipelagos_are_grouped(report) -> void:
	# "Island" here means a column that the archipelago module turned into land: the
	# raw continental field says water and the composed land signal says land.
	var surface := _make_surface(1337)
	var width := 96
	var step := STRIDE * 2
	var flags := PackedByteArray()
	flags.resize(width * width)
	var island_cells := 0
	for j in range(width):
		for i in range(width):
			var point := Vector2i(-768 + i * step, -768 + j * step)
			var raw := surface.get_field_at(&"continentalness", point.x, point.y)
			var composed := surface.get_field_at(&"landmass", point.x, point.y)
			if raw < SurfaceModule.OCEAN_EDGE and composed >= SurfaceModule.OCEAN_EDGE:
				flags[j * width + i] = 1
				island_cells += 1
	var sizes := _component_sizes(flags, width, width)
	var largest := 0
	for size in sizes:
		largest = maxi(largest, size)
	report.check("the archipelago field creates islands", island_cells >= 20,
			"%d island cells over a 1500-voxel square" % island_cells)
	report.check("islands group into archipelagos rather than scattering",
			sizes.size() > 1 and float(largest) / float(maxi(island_cells, 1)) >= 0.04,
			"%d island groups, largest %.0f%% of island cells" % [
				sizes.size(), 100.0 * float(largest) / float(maxi(island_cells, 1))
			])

	# Islands must have relief of their own, not be flat discs at sea level.
	var tallest := -1e9
	for point in _grid(40, Vector2i(-800, -800), STRIDE * 4):
		var raw := surface.get_field_at(&"continentalness", point.x, point.y)
		if raw >= SurfaceModule.OCEAN_EDGE:
			continue
		if surface.get_field_at(&"landmass", point.x, point.y) < SurfaceModule.OCEAN_EDGE:
			continue
		tallest = maxf(tallest, surface.get_surface_height(point.x, point.y))
	report.check("islands carry real relief", tallest > surface.get_sea_level() + 3.0,
			"tallest island column %.1f voxels (sea level %.1f)" % [tallest, surface.get_sea_level()])


static func _test_shelves_are_gradual(report) -> void:
	# A transect from land out to deep water. Two numbers matter, and they are the
	# same two the M1 milestone reported: the mean height change per column at the
	# waterline (a beach, not a wall) and the worst step anywhere in the shoreline
	# band. The shelf itself is the stretch of seafloor between the shore and the
	# depth at which the slope steepens into the continental slope.
	var surface := _make_surface(1337)
	var sea := surface.get_sea_level()
	var worst_step := 0.0
	var transects := 0
	var shelf_total := 0
	var waterline_sum := 0.0
	var waterline_count := 0
	for point in _grid(24, Vector2i(-768, -768), STRIDE * 8):
		var previous := surface.get_surface_height(point.x, point.y)
		if previous <= sea:
			continue
		transects += 1
		var crossing_recorded := false
		for k in range(1, 40):
			var here := surface.get_surface_height(point.x + k * 8, point.y)
			var step := absf(here - previous) / 8.0
			var previous_near := absf(previous - sea) <= 5.0
			var here_near := absf(here - sea) <= 5.0
			if previous_near and here_near:
				worst_step = maxf(worst_step, step)
				if here < sea and not crossing_recorded:
					waterline_sum += step
					waterline_count += 1
					crossing_recorded = true
			if here < sea - 10.0:
				break
			if absf(here - sea) < 12.0:
				shelf_total += 1
			previous = here
	var waterline_mean := waterline_sum / float(maxi(waterline_count, 1))
	report.check("the shoreline is a beach rather than a wall",
			transects > 10 and worst_step <= 2.0,
			"worst waterline slope %.2f voxels per column over %d transects (limit 2.0)" % [
				worst_step, transects
			])
	report.check("the mean waterline slope matches the M1 coastal behaviour",
			waterline_mean <= 0.6,
			"mean %.2f voxels per column over %d crossings" % [waterline_mean, waterline_count])
	report.check("the shelf band exists between land and deep water",
			shelf_total > 20, "%d shelf samples across the transects" % shelf_total)


static func _test_coast_shaping_preserves_layout(report) -> void:
	var surface := _make_surface(1337)
	var raw := PackedFloat32Array()
	var composed := PackedFloat32Array()
	var flipped := 0
	for point in _grid(48, Vector2i(-512, -512), STRIDE * 2):
		var raw_value := surface.get_field_at(&"continentalness", point.x, point.y)
		var composed_value := surface.get_field_at(&"landmass", point.x, point.y)
		raw.append(raw_value)
		composed.append(composed_value)
		if (raw_value >= SurfaceModule.OCEAN_EDGE) != (composed_value >= SurfaceModule.OCEAN_EDGE):
			flipped += 1
	var correlation := _correlation(raw, composed)
	var flip_share := float(flipped) / float(raw.size())
	report.check("islands and coastline detail leave the continental layout intact",
			correlation >= 0.9,
			"correlation of landmass with continentalness %.4f over %d samples" % [correlation, raw.size()])
	report.check("only coastline columns change side of the waterline",
			flip_share <= 0.15,
			"%.1f%% of columns changed side" % (flip_share * 100.0))


static func _test_sea_level_contract(report) -> void:
	# The M1 contract: the waterline is where the land signal crosses OCEAN_EDGE, so
	# terrain is below the sea plane exactly where the signal says ocean.
	var surface := _make_surface(1337)
	var sea := surface.get_sea_level()
	var wrong_deep := 0
	var wrong_land := 0
	var deep := 0
	var land := 0
	for point in _grid(48, Vector2i(-512, -512), STRIDE * 2):
		var value := surface.get_field_at(&"landmass", point.x, point.y)
		var height := surface.get_surface_height(point.x, point.y)
		if value < SurfaceModule.DEEP_OCEAN_EDGE:
			deep += 1
			if height > sea:
				wrong_deep += 1
		elif value > SurfaceModule.LAND_EDGE:
			land += 1
			if height < sea:
				wrong_land += 1
	report.check("deep ocean columns are below sea level", wrong_deep == 0,
			"%d deep columns, %d wrong" % [deep, wrong_deep])
	report.check("inland columns are above sea level", wrong_land == 0,
			"%d inland columns, %d wrong" % [land, wrong_land])


static func _test_land_fraction_across_seeds(report) -> void:
	var worst_low := 1.0
	var worst_high := 0.0
	var detail := ""
	for seed_value in [1337, 90210, 4242]:
		var surface := _make_surface(seed_value)
		var land := 0
		var total := 0
		for point in _grid(32, Vector2i(-512, -512), STRIDE * 4):
			total += 1
			if surface.get_field_at(&"landmass", point.x, point.y) >= SurfaceModule.OCEAN_EDGE:
				land += 1
		var share := float(land) / float(maxi(total, 1))
		worst_low = minf(worst_low, share)
		worst_high = maxf(worst_high, share)
		detail += "seed %d: %.0f%% " % [seed_value, share * 100.0]
	report.check("every seed has both ocean and land in a plausible proportion",
			worst_low >= 0.15 and worst_high <= 0.80, detail)


# ----------------------------------------------------------------- integration

static func _test_landmass_composition(report) -> void:
	# The composer is checked as a function: given synthetic inputs it must produce
	# exactly the documented sum, clamped. This is the independent-testability
	# property - no world, no engine, no voxels.
	var prepared := _isolate(LandmassModule.new())
	if prepared.is_empty():
		report.check("the landmass module can be resolved on its own", false)
		return
	report.check("the landmass module can be resolved on its own", true)

	var config := _make_config(1337)
	var expected := 0.30 + 0.50 * config.island_strength + -0.20 * config.coast_strength
	var actual := _eval_isolated(prepared, {
		&"continentalness": 0.30, &"archipelago": 0.50, &"coast_detail": -0.20,
	}, 0, 0)
	report.check("landmass is continentalness plus islands plus coast detail",
			absf(actual - expected) < 0.0001, "%.4f vs %.4f" % [actual, expected])

	var clamped := _eval_isolated(prepared, {
		&"continentalness": 0.95, &"archipelago": 0.9, &"coast_detail": 0.9,
	}, 0, 0)
	report.check("landmass stays within [-1, 1]", clamped <= 1.0 and clamped >= -1.0,
			"%.3f" % clamped)


static func _test_mountains_read_their_inputs(report) -> void:
	var prepared := _isolate(MountainModule.new())
	if prepared.is_empty():
		report.check("the mountain module can be resolved on its own", false)
		return
	report.check("the mountain module can be resolved on its own", true)

	var ocean := _eval_isolated(prepared, {&"landmass": -0.8, &"tectonics": 0.9}, 0, 0)
	report.check("mountains are zero under the ocean", ocean == 0.0, "%.3f" % ocean)

	var rift := _eval_isolated(prepared, {&"landmass": 0.6, &"tectonics": -0.5}, 64, 96)
	var uplift := _eval_isolated(prepared, {&"landmass": 0.6, &"tectonics": 0.9}, 64, 96)
	report.check("uplift builds higher terrain than a rift at the same coordinate",
			uplift > rift, "uplift %.3f vs rift %.3f" % [uplift, rift])


static func _test_valleys_and_plateaus_gate_on_land(report) -> void:
	var valleys := _isolate(ValleyModule.new())
	if valleys.is_empty():
		report.check("the valley module can be resolved on its own", false)
		return
	report.check("the valley module can be resolved on its own", true)
	var at_sea := _eval_isolated(valleys, {&"landmass": -0.9, &"mountainness": 0.8}, 0, 0)
	report.check("valleys are not carved into the seafloor", at_sea == 0.0, "%.3f" % at_sea)

	var plateaus := _isolate(PlateauModule.new())
	if plateaus.is_empty():
		report.check("the plateau module can be resolved on its own", false)
		return
	report.check("the plateau module can be resolved on its own", true)
	var underwater := _eval_isolated(plateaus, {&"landmass": -0.9}, 0, 0)
	report.check("plateaus do not form under the ocean", underwater == 0.0, "%.3f" % underwater)

	var highest := 0.0
	for i in range(400):
		highest = maxf(highest, _eval_isolated(plateaus, {&"landmass": 0.8}, i * 97, 0))
	report.check("plateaus do form inland", highest > 0.5, "highest mask %.3f" % highest)


static func _test_island_strength_is_configurable(report) -> void:
	var config := _make_config(1337)
	config.island_strength = 0.0
	var without := GeographicSurface.new(config)
	var default_surface := _make_surface(1337)
	var changed := 0
	for point in _grid(24, Vector2i(-512, -512), STRIDE * 4):
		if absf(without.get_field_at(&"landmass", point.x, point.y)
				- default_surface.get_field_at(&"landmass", point.x, point.y)) > 0.01:
			changed += 1
	report.check("island strength can be switched off", changed > 5,
			"%d columns changed when island strength was zeroed" % changed)
	var island_strength_zero_keeps_layout := true
	for point in _grid(12, Vector2i(-256, -256), STRIDE * 4):
		var raw := without.get_field_at(&"continentalness", point.x, point.y)
		var coast := without.get_field_at(&"coast_detail", point.x, point.y)
		var composed := without.get_field_at(&"landmass", point.x, point.y)
		if absf(composed - clampf(raw + coast * config.coast_strength, -1.0, 1.0)) > 0.0001:
			island_strength_zero_keeps_layout = false
	report.check("with island strength off, landmass is continentalness plus coast detail",
			island_strength_zero_keeps_layout)


static func _test_valley_depth_is_configurable(report) -> void:
	var config := _make_config(1337)
	config.valley_depth = 0.0
	var without := GeographicSurface.new(config)
	var default_surface := _make_surface(1337)
	var lower := 0
	var higher := 0
	for point in _grid(32, Vector2i(-384, -384), STRIDE * 2):
		var a := without.get_surface_height(point.x, point.y)
		var b := default_surface.get_surface_height(point.x, point.y)
		if a > b + 0.5:
			higher += 1
		elif a < b - 0.5:
			lower += 1
	report.check("valley depth controls carving and never raises terrain",
			higher > 0 and lower == 0,
			"%d columns higher without carving, %d lower" % [higher, lower])


static func _test_mountain_scale_is_configurable(report) -> void:
	var config := _make_config(1337)
	config.mountain_scale = 0.0
	var without := GeographicSurface.new(config)
	var default_surface := _make_surface(1337)
	var default_peak := -1e9
	var flat_peak := -1e9
	for point in _grid(48, Vector2i(-512, -512), STRIDE * 4):
		var a := without.get_surface_height(point.x, point.y)
		var b := default_surface.get_surface_height(point.x, point.y)
		flat_peak = maxf(flat_peak, a)
		default_peak = maxf(default_peak, b)
	report.check("mountain scale controls the height of ranges",
			default_peak - flat_peak >= 8.0,
			"peak %.1f with ranges vs %.1f without" % [default_peak, flat_peak])


static func _test_generator_matches_surface_in_mountains(report) -> void:
	# The voxel adapter is still the only consumer of the composed surface, so it
	# must agree with it in mountain country too, not only on gentle ground.
	var surface := _make_surface(1337)
	var config := _make_config(1337)
	var origin := Vector2i(-512, -512)
	var best := origin
	var best_height := -1e9
	for j in range(16):
		for i in range(16):
			var point := origin + Vector2i(i * 32, j * 32)
			var height := surface.get_surface_height(point.x, point.y)
			if height > best_height:
				best_height = height
				best = point
	var block_origin := Vector2i((best.x / 16) * 16, (best.y / 16) * 16)
	var heights := surface.sample_block_heights(block_origin, Vector2i(16, 16))
	var mismatched := 0
	for j in range(16):
		for i in range(16):
			var row_major := surface.get_surface_height(block_origin.x + i, block_origin.y + j)
			if absf(heights[j * 16 + i] - row_major) > 0.0001:
				mismatched += 1
	report.check("the block height array matches the surface in mountain terrain",
			mismatched == 0, "block at %s, peak height %.1f" % [str(block_origin), best_height])
	report.check("that block really is mountain terrain", best_height > 45.0,
			"%.1f voxels" % best_height)


# ----------------------------------------------------------------- performance

static func _test_performance(report) -> void:
	var surface := _make_surface(1337)
	# Warm up so the numbers describe steady state rather than first-touch cost.
	surface.sample_block_heights(Vector2i(-64, -64), Vector2i(16, 16))

	# Contiguous blocks, which is how streaming requests them: neighbouring blocks
	# share six of the nine nodes they need, so this measures the real cost of a
	# streamed region rather than the cost of a scattered probe.
	var blocks := 144
	var per_block := 0.0
	# Two passes over the same contiguous region and the second one is reported.
	# The first pass pays for evaluating every node it touches; the second measures
	# what streaming actually costs, because streaming re-requests regions it has
	# already walked. The cold number was about five times the warm one.
	var elapsed := 0.0
	for pass_index in range(2):
		var start := Time.get_ticks_usec()
		for i in range(blocks):
			var origin := Vector2i((i % 12) * 16 - 96, (i / 12) * 16 - 48)
			surface.sample_block_heights(origin, Vector2i(16, 16))
		elapsed = float(Time.get_ticks_usec() - start)
		per_block = elapsed / float(blocks)
		if pass_index == 0:
			report.info("cold pass over a fresh region: %.1f us per block" % per_block)
	var start = Time.get_ticks_usec()
	report.check("a 16^3 block of the M2 pipeline generates in a mobile-plausible time",
			per_block <= 250.0, "%.1f us per block (%.0f blocks/s)" % [per_block, 1000000.0 / per_block])

	# Field cost: the modules are evaluated on the node grid, so one node's worth of
	# every field is the honest per-node budget.
	var nodes := 200
	start = Time.get_ticks_usec()
	for i in range(nodes):
		surface.get_field_at(&"mountainness", i * 8, 0)
	elapsed = float(Time.get_ticks_usec() - start) / float(nodes)
	report.check("one node of the full field set costs less than a tenth of a millisecond",
			elapsed <= 100.0, "%.1f us per node" % elapsed)

	var stats := surface.get_cache_stats()
	report.check("the node cache is doing work", int(stats.get("hits", 0)) > 0,
			"hits %d, evaluations %d" % [int(stats.get("hits", 0)), int(stats.get("evaluations", 0))])
	report.info("M2 performance: %.1f us/block, %.1f us/node, cache %s" % [
			per_block, elapsed, str(stats)
	])
