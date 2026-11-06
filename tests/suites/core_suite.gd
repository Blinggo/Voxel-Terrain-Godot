extends RefCounted

## Engine-light tests for the generation core.
##
## These exercise [NoiseSource], [TerrainHeightField], [BlockPalette] and
## [TerrainBlockGenerator] by writing voxels into standalone [VoxelBuffer]s. No
## terrain node, no viewer and no streaming are involved, so a failure here
## points at generation logic rather than at Voxel Tools setup.

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
	_test_noise_contract(report)
	_test_seed_determinism(report)
	_test_seed_changes_terrain(report)
	_test_height_field_shape(report)
	_test_palette_layers(report)
	_test_block_content_is_order_independent(report)
	_test_no_seams_between_adjacent_blocks(report)
	_test_concurrent_sampling_matches_serial(report)


static func _make_height_field(world_seed: int, amplitude: float = 26.0, frequency: float = 0.008) -> TerrainHeightField:
	var noise := FastNoiseLiteSource.new(world_seed, frequency, 4)
	return TerrainHeightField.new(noise, 24.0, amplitude)


static func _make_generator(height_field: TerrainHeightField) -> TerrainBlockGenerator:
	var generator := TerrainBlockGenerator.new()
	generator.configure(height_field, BlockPalette.new())
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


static func _test_noise_contract(report) -> void:
	var source := FastNoiseLiteSource.new(1234, 0.01, 4)
	var in_range := true
	var finite := true
	for z in range(-32, 32, 3):
		for x in range(-32, 32, 3):
			var v := source.sample_2d(float(x), float(z))
			if v < -1.0 or v > 1.0:
				in_range = false
			if is_nan(v) or is_inf(v):
				finite = false
	report.check("noise output is finite", finite)
	report.check("noise output stays within [-1, 1]", in_range)

	var a := source.sample_2d(12.5, -7.25)
	var b := source.sample_2d(12.5, -7.25)
	report.check_equal("noise is a pure function of its arguments", a, b)


static func _test_seed_determinism(report) -> void:
	var field_a := _make_height_field(98765)
	var field_b := _make_height_field(98765)

	var mismatch := 0
	for z in range(GRID_ORIGIN.y, GRID_ORIGIN.y + GRID_SIZE.y, 7):
		for x in range(GRID_ORIGIN.x, GRID_ORIGIN.x + GRID_SIZE.x, 7):
			if field_a.get_surface_height(x, z) != field_b.get_surface_height(x, z):
				mismatch += 1
	report.check_equal("same seed produces identical heights from independent instances", mismatch, 0)
	report.info("compared %d columns across two independent height fields" % ((GRID_SIZE.y / 7) * (GRID_SIZE.x / 7)))


static func _test_seed_changes_terrain(report) -> void:
	var field_a := _make_height_field(1111)
	var field_b := _make_height_field(2222)

	var differing := 0
	var total := 0
	for z in range(GRID_ORIGIN.y, GRID_ORIGIN.y + GRID_SIZE.y, 7):
		for x in range(GRID_ORIGIN.x, GRID_ORIGIN.x + GRID_SIZE.x, 7):
			total += 1
			if absf(field_a.get_surface_height(x, z) - field_b.get_surface_height(x, z)) > 0.001:
				differing += 1

	# Noise could coincidentally agree on a few columns; requiring that the vast
	# majority differ is enough to prove the seed is actually applied.
	var fraction := float(differing) / float(maxi(total, 1))
	report.check(
			"different seeds produce different terrain",
			fraction > 0.95,
			"%.1f%% of %d columns differ" % [fraction * 100.0, total]
	)


static func _test_height_field_shape(report) -> void:
	var flat := _make_height_field(42, 0.0, 0.008)
	report.check_equal("zero amplitude yields a flat surface at base height", flat.get_surface_height(500, -300), 24.0)

	var bumpy := _make_height_field(42, 26.0, 0.008)
	var within_bounds := true
	var max_deviation := 0.0
	for z in range(-200, 200, 11):
		for x in range(-200, 200, 11):
			var h := bumpy.get_surface_height(x, z)
			max_deviation = maxf(max_deviation, absf(h - 24.0))
			if h < 24.0 - 26.0 - 0.001 or h > 24.0 + 26.0 + 0.001:
				within_bounds = false
	report.check("surface stays within base_height +/- amplitude", within_bounds, "max deviation %.2f" % max_deviation)
	report.check("amplitude actually varies the surface", max_deviation > 1.0, "max deviation %.2f" % max_deviation)


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
	var generator := _make_generator(_make_height_field(2024))
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
	var field := _make_height_field(777)
	var generator := _make_generator(field)

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
			var expected_left := _expected_top_in_block(field.get_surface_height(x, z))
			var actual_left := _top_solid_voxel(left, x, z)
			if expected_left != actual_left:
				mismatches += 1
				report.info("mismatch at x=%d z=%d: expected top %d, got %d" % [x, z, expected_left, actual_left])
			checked += 1
		for x_local in _RIGHT_SAMPLE_COLUMNS:
			var expected_right := _expected_top_in_block(field.get_surface_height(BLOCK_SIZE + x_local, z))
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
			var expected := _expected_top_in_stack(field.get_surface_height(x, z))
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


## Sampling the height field from several threads at once must give exactly the
## same answers as sampling it serially. This is the property Voxel Tools relies
## on when it generates blocks on the thread pool.
static func _test_concurrent_sampling_matches_serial(report) -> void:
	var field := _make_height_field(31337)

	var serial: Array[float] = []
	for i in range(512):
		serial.append(field.get_surface_height(i - 256, 128 - i))

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
				out.append(field.get_surface_height(i - 256, 128 - i))
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
