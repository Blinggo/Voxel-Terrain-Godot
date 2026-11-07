extends RefCounted

## Engine-light tests for the generation core.
##
## These exercise [GeographicSurface], [BlockPalette] and
## [TerrainBlockGenerator] by writing voxels into standalone [VoxelBuffer]s. No
## terrain node, no viewer and no streaming are involved, so a failure here
## points at generation logic rather than at Voxel Tools setup.
##
## Since M1 the surface is produced by the module pipeline in
## `src/core/generation/`; the suite that tests that pipeline's determinism,
## fields and registry lives in `generation_suite.gd`. This suite covers the
## contract between the surface and the voxel adapter: pure sampling, block
## content, and seams.

const GRID_ORIGIN := Vector2i(-64, -64)
const GRID_SIZE := Vector2i(128, 128)
const BLOCK_SIZE := 32

## Columns sampled on each side of the shared block plane x = 32. The last
## column of the left block and the first column of the right block are adjacent
## in world space, so comparing both against the same analytic field is what
## detects a seam.
const _LEFT_SAMPLE_COLUMNS: Array[int] = [0, 15, 31]
const _RIGHT_SAMPLE_COLUMNS: Array[int] = [0, 1, 15]


static func run(report) -> void:
	_test_surface_contract(report)
	_test_seed_determinism(report)
	_test_seed_changes_terrain(report)
	_test_surface_shape(report)
	_test_palette_layers(report)
	_test_block_content_is_order_independent(report)
	_test_no_seams_between_adjacent_blocks(report)
	_test_concurrent_sampling_matches_serial(report)


static func _make_surface(world_seed: int) -> GeographicSurface:
	var config := WorldConfig.new()
	config.world_seed = world_seed
	return GeographicSurface.new(config)


static func _make_generator(surface: GeographicSurface) -> TerrainBlockGenerator:
	var generator := TerrainBlockGenerator.new()
	generator.configure(surface, BlockPalette.new())
	return generator


static func _generate_block(generator: TerrainBlockGenerator, origin: Vector3i) -> VoxelBuffer:
	var buffer := VoxelBuffer.new()
	buffer.create(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_16_BIT)
	generator._generate_block(buffer, origin, 0)
	return buffer


## Flattens a buffer into a comparable array, so two blocks can be compared
## exactly rather than by sampling.
static func _block_fingerprint(buffer: VoxelBuffer) -> PackedByteArray:
	return buffer.get_channel_as_byte_array(VoxelBuffer.CHANNEL_TYPE)


static func _test_surface_contract(report) -> void:
	var surface := _make_surface(1234)

	var finite := true
	var in_bounds := true
	for z in range(-32, 32, 3):
		for x in range(-32, 32, 3):
			var height := surface.get_surface_height(x, z)
			if is_nan(height) or is_inf(height):
				finite = false
			if height < SurfaceModule.MIN_HEIGHT or height > SurfaceModule.MAX_HEIGHT:
				in_bounds = false
	report.check("surface heights are finite", finite)
	report.check("surface heights stay within the documented bounds", in_bounds)

	var a := surface.get_surface_height(12, -7)
	var b := surface.get_surface_height(12, -7)
	report.check_equal("surface height is a pure function of its coordinates", a, b)

	report.check("the surface reports a valid module pipeline", surface.is_valid())
	report.info("execution order: %s" % String(", ".join(surface.get_module_ids())))


static func _test_seed_determinism(report) -> void:
	var surface_a := _make_surface(98765)
	var surface_b := _make_surface(98765)

	var mismatch := 0
	var compared := 0
	for z in range(GRID_ORIGIN.y, GRID_ORIGIN.y + GRID_SIZE.y, 7):
		for x in range(GRID_ORIGIN.x, GRID_ORIGIN.x + GRID_SIZE.x, 7):
			compared += 1
			if surface_a.get_surface_height(x, z) != surface_b.get_surface_height(x, z):
				mismatch += 1
	report.check_equal("same seed produces identical heights from independent instances", mismatch, 0)
	report.info("compared %d columns across two independent surfaces" % compared)


static func _test_seed_changes_terrain(report) -> void:
	var surface_a := _make_surface(1111)
	var surface_b := _make_surface(2222)

	var differing := 0
	var total := 0
	for z in range(GRID_ORIGIN.y, GRID_ORIGIN.y + GRID_SIZE.y, 7):
		for x in range(GRID_ORIGIN.x, GRID_ORIGIN.x + GRID_SIZE.x, 7):
			total += 1
			if absf(surface_a.get_surface_height(x, z) - surface_b.get_surface_height(x, z)) > 0.001:
				differing += 1

	# Terrain could coincidentally agree on a few columns; requiring that the vast
	# majority differ is enough to prove the seed is actually applied.
	var fraction := float(differing) / float(maxi(total, 1))
	report.check(
			"different seeds produce different terrain",
			fraction > 0.95,
			"%.1f%% of %d columns differ" % [fraction * 100.0, total]
	)


static func _test_surface_shape(report) -> void:
	var surface := _make_surface(42)
	var minimum := INF
	var maximum := -INF
	for z in range(-200, 200, 11):
		for x in range(-200, 200, 11):
			var height := surface.get_surface_height(x, z)
			minimum = minf(minimum, height)
			maximum = maxf(maximum, height)

	report.check(
			"surface stays within the composed height bounds",
			minimum >= SurfaceModule.MIN_HEIGHT and maximum <= SurfaceModule.MAX_HEIGHT,
			"range %.2f..%.2f" % [minimum, maximum]
	)
	report.check(
			"the surface actually has relief",
			maximum - minimum > 10.0,
			"range %.2f..%.2f" % [minimum, maximum]
	)


static func _test_palette_layers(report) -> void:
	var palette := BlockPalette.new()
	palette.soil_depth = 4
	var surface := 20.0
	report.check_equal("voxel above the surface is air", palette.classify(21, surface), BlockPalette.AIR)
	report.check_equal("voxel at the surface is grass", palette.classify(20, surface), BlockPalette.GRASS)
	report.check_equal("voxel one below the surface is dirt", palette.classify(19, surface), BlockPalette.DIRT)
	report.check_equal("voxel at soil depth is dirt", palette.classify(16, surface), BlockPalette.DIRT)
	report.check_equal("voxel below soil depth is stone", palette.classify(15, surface), BlockPalette.STONE)


## The core guarantee: a block's content depends only on where it is, never on
## what was generated before it. Generating neighbours first must not change it.
static func _test_block_content_is_order_independent(report) -> void:
	var generator := _make_generator(_make_surface(2024))
	var origin := Vector3i(0, 0, 0)

	var isolated := _generate_block(generator, origin)

	# Regenerate eight neighbours first, then the same block again.
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			_generate_block(generator, origin + Vector3i(dx * BLOCK_SIZE, 0, dz * BLOCK_SIZE))
	var after_neighbours := _generate_block(generator, origin)

	report.check(
			"block content is independent of generation order",
			_block_fingerprint(isolated) == _block_fingerprint(after_neighbours)
	)


## Seam test at the data level: reconstruct each column's surface from voxels
## written by two different blocks and compare against the analytic height.
## If shared or adjacent columns disagreed, terrain would show a seam.
static func _test_no_seams_between_adjacent_blocks(report) -> void:
	var surface := _make_surface(777)
	var generator := _make_generator(surface)

	# Blocks that share the plane x = 32, plus a vertical neighbour pair so that
	# both horizontal and vertical boundaries are covered.
	var left := _generate_block(generator, Vector3i(0, 0, 0))
	var right := _generate_block(generator, Vector3i(BLOCK_SIZE, 0, 0))
	var upper := _generate_block(generator, Vector3i(0, BLOCK_SIZE, 0))

	var checked := 0
	var mismatches := 0

	# Vertical continuity across the x boundary: the topmost solid voxel of a
	# column must equal floor(surface) regardless of which block wrote it.
	for z in range(0, BLOCK_SIZE, 5):
		for x in _LEFT_SAMPLE_COLUMNS:
			var expected_left := _expected_top_in_block(surface.get_surface_height(x, z))
			var actual_left := _top_solid_voxel(left, x, z)
			if expected_left != actual_left:
				mismatches += 1
				report.info("mismatch at x=%d z=%d: expected top %d, got %d" % [x, z, expected_left, actual_left])
			checked += 1
		for x_local in _RIGHT_SAMPLE_COLUMNS:
			var expected_right := _expected_top_in_block(surface.get_surface_height(BLOCK_SIZE + x_local, z))
			var actual_right := _top_solid_voxel(right, x_local, z)
			if expected_right != actual_right:
				mismatches += 1
				report.info("mismatch at x=%d z=%d: expected top %d, got %d" % [
					BLOCK_SIZE + x_local, z, expected_right, actual_right
				])
			checked += 1

	report.check_equal("column surfaces reconstructed from block data match the analytic height field", mismatches, 0)
	report.info("checked %d columns across the x=%d block boundary" % [checked, BLOCK_SIZE])

	# Vertical seam: the column must not change shape depending on the block.
	var vertical_mismatch := 0
	var vertical_checked := 0
	for z in range(0, BLOCK_SIZE, 5):
		for x in range(0, BLOCK_SIZE, 5):
			var expected := _expected_top_in_stack(surface.get_surface_height(x, z))
			# Reconstruct the full column by stacking the two vertical blocks.
			var combined := _top_solid_voxel_stacked(left, upper, x, z)
			if expected != combined:
				vertical_mismatch += 1
				report.info("vertical mismatch at x=%d z=%d: expected %d, got %d" % [x, z, expected, combined])
			vertical_checked += 1
	report.check_equal("columns spanning a vertical block boundary are continuous", vertical_mismatch, 0)
	report.info("checked %d columns across the y=%d block boundary" % [vertical_checked, BLOCK_SIZE])


## Topmost solid voxel a single block of this height can contain for a column
## whose surface is at [param surface]. Columns that are entirely below the
## block (surface above it) clamp to the block's top voxel; columns entirely
## above the surface (surface below the block) contain no solid voxels.
static func _expected_top_in_block(surface: float) -> int:
	var top := int(floor(surface))
	if top < 0:
		return -1
	if top >= BLOCK_SIZE:
		return BLOCK_SIZE - 1
	return top


## As [method _expected_top_in_block], but for a stack of two blocks.
static func _expected_top_in_stack(surface: float) -> int:
	var top := int(floor(surface))
	var height := BLOCK_SIZE * 2
	if top < 0:
		return -1
	if top >= height:
		return height - 1
	return top


static func _top_solid_voxel(buffer: VoxelBuffer, x: int, z: int) -> int:
	for y in range(BLOCK_SIZE - 1, -1, -1):
		if buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) != BlockPalette.AIR:
			return y
	return -1


static func _top_solid_voxel_stacked(lower: VoxelBuffer, upper: VoxelBuffer, x: int, z: int) -> int:
	for y in range(BLOCK_SIZE - 1, -1, -1):
		if upper.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE) != BlockPalette.AIR:
			return BLOCK_SIZE + y
	return _top_solid_voxel(lower, x, z)


## Sampling the surface from several threads at once must give exactly the same
## answers as sampling it serially. This is the property Voxel Tools relies on
## when it generates blocks on the thread pool - and since M1 it also exercises
## the mutex-guarded node cache those threads share.
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

	var mismatch := 0
	for t in range(4):
		var out: Array = results[t]
		if out.size() != serial.size():
			mismatch += 1
			continue
		for i in range(serial.size()):
			if out[i] != serial[i]:
				mismatch += 1
	report.check_equal("concurrent height sampling matches serial results on 4 threads", mismatch, 0)
