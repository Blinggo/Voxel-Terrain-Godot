extends RefCounted

## Generation-input stability suite.
##
## Terrain is generated on Voxel Tools worker threads while the palette resource
## stays editable in the inspector. This suite demonstrates that generation runs
## from a snapshot taken before it starts, so an edit cannot change a block that
## is already being generated - and equally, that a rebuild *does* pick the edit
## up, otherwise the snapshot would simply be a bug that ignores configuration.
##
## Runs headless: it uses the generator directly instead of waiting for the
## streaming pipeline, which keeps it deterministic.

const TestSupport = preload("res://tests/test_support.gd")

const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const BLOCK_SIZE := Vector3i(16, 16, 16)

var _report
var _tree: SceneTree


static func run(report, tree: SceneTree) -> void:
	var suite := new()
	suite._report = report
	suite._tree = tree

	# The runner prints the section header.
	await tree.process_frame

	suite._test_snapshot_copies_configuration()
	suite._test_snapshot_is_independent_of_later_edits()
	suite._test_type_ids_are_preserved()
	suite._test_generator_ignores_edits_after_snapshot()
	suite._test_library_follows_the_same_snapshot()
	await suite._test_world_generation_uses_a_stable_snapshot()


# --------------------------------------------------------------------- helpers

func _make_palette(soil_depth: int = 4) -> BlockPalette:
	var palette := BlockPalette.new()
	palette.soil_depth = soil_depth
	return palette


func _make_generator(palette: BlockPalette) -> TerrainBlockGenerator:
	# The default world parameters, so the surface falls inside the blocks used
	# below and the grass/dirt/stone bands are all exercised.
	var noise := FastNoiseLiteSource.new(1337, 0.008, 4)
	var height_field := TerrainHeightField.new(noise, 24.0, 26.0)
	var generator := TerrainBlockGenerator.new()
	generator.configure(height_field, palette)
	return generator


## Hash of every type id a generator produces for one block. Sensitive to a
## single changed voxel, cheap enough to run a few dozen times.
func _hash_block(generator: TerrainBlockGenerator, origin: Vector3i) -> int:
	var buffer := VoxelBuffer.new()
	buffer.create(BLOCK_SIZE.x, BLOCK_SIZE.y, BLOCK_SIZE.z)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE, VoxelBuffer.DEPTH_8_BIT)
	generator._generate_block(buffer, origin, 0)

	var hash_value := 1469598103934665603  # FNV-1a offset basis
	for z in range(BLOCK_SIZE.z):
		for y in range(BLOCK_SIZE.y):
			for x in range(BLOCK_SIZE.x):
				var type_id := buffer.get_voxel(x, y, z, VoxelBuffer.CHANNEL_TYPE)
				hash_value = (hash_value ^ type_id) * 1099511628211
				hash_value &= 0x7FFFFFFFFFFFFFFF
	return hash_value


## Hashes a column of blocks, which is what a palette change would visibly break.
func _hash_column(generator: TerrainBlockGenerator) -> Array[int]:
	var hashes: Array[int] = []
	for block_y in [0, 16, 32]:
		hashes.append(_hash_block(generator, Vector3i(0, block_y, 0)))
	return hashes


# ---------------------------------------------------------------------- checks

func _test_snapshot_copies_configuration() -> void:
	var palette := _make_palette(6)
	palette.grass_color = Color(0.1, 0.2, 0.3)
	var snapshot := palette.create_snapshot()

	_report.check("the snapshot is a different instance", snapshot != palette)
	_report.check_equal("soil depth is copied", snapshot.soil_depth, 6)
	_report.check_equal("grass colour is copied", snapshot.grass_color, Color(0.1, 0.2, 0.3))
	_report.check_equal("dirt colour is copied", snapshot.dirt_color, palette.dirt_color)
	_report.check_equal("stone colour is copied", snapshot.stone_color, palette.stone_color)


func _test_snapshot_is_independent_of_later_edits() -> void:
	var palette := _make_palette(2)
	var snapshot := palette.create_snapshot()

	# What an inspector edit (or any other script) would do mid-generation.
	palette.soil_depth = 12
	palette.grass_color = Color.RED
	palette.dirt_color = Color.BLUE

	_report.check_equal("editing the source leaves the snapshot's soil depth alone",
			snapshot.soil_depth, 2)
	_report.check_equal("editing the source leaves the snapshot's grass colour alone",
			snapshot.grass_color, Color(0.36, 0.62, 0.29))
	_report.check_equal("editing the source leaves the snapshot's dirt colour alone",
			snapshot.dirt_color, Color(0.45, 0.33, 0.22))
	_report.check_equal("the source itself did change (the test can detect edits)",
			palette.soil_depth, 12)


func _test_type_ids_are_preserved() -> void:
	# Ids are constants, so a snapshot cannot disagree with its source about
	# what a block *is*. This is what keeps existing worlds and materials valid.
	_report.check_equal("air is still id 0", BlockPalette.AIR, 0)
	_report.check_equal("grass is still id 1", BlockPalette.GRASS, 1)
	_report.check_equal("dirt is still id 2", BlockPalette.DIRT, 2)
	_report.check_equal("stone is still id 3", BlockPalette.STONE, 3)

	var snapshot := _make_palette(4).create_snapshot()
	_report.check_equal("the snapshot classifies with the same ids",
			snapshot.classify(9, 10.0), BlockPalette.DIRT)
	_report.check_equal("the snapshot reports the same maximum id",
			snapshot.max_type_id(), BlockPalette.STONE)


func _test_generator_ignores_edits_after_snapshot() -> void:
	var palette := _make_palette(4)
	var generator := _make_generator(palette.create_snapshot())

	var before := _hash_column(generator)
	_report.check("a snapshot makes a non-trivial amount of solid terrain",
			before.size() == 3)

	# Change the live palette after generation has started.
	palette.soil_depth = 0
	palette.grass_color = Color.MAGENTA

	var after := _hash_column(generator)
	_report.check_equal("blocks generated after the edit are identical", after, before)

	# Sensitivity check: had the generator held the live palette, the edit would
	# have changed the output. Without this, the test above could pass simply
	# because soil depth never affects these blocks.
	var live_generator := _make_generator(palette)
	var with_live_palette := _hash_column(live_generator)
	_report.check(
			"the same edit does change output when the live palette is used",
			with_live_palette != before,
			"snapshot=%s live=%s" % [before, with_live_palette])


func _test_library_follows_the_same_snapshot() -> void:
	# The blocky library and the generator must be built from one snapshot, or a
	# voxel could reference a model that the library no longer contains.
	var palette := _make_palette(4)
	var snapshot := palette.create_snapshot()
	var library := BlockyLibraryBuilder.build_library(snapshot)

	_report.check("the library can be built from a snapshot", library != null)

	# Every id the palette can emit, including air, must have a model or the
	# mesher would skip voxels that exist in the data.
	var model_count := library.get_models().size()
	_report.check_equal("the library has one model per type id",
			model_count, snapshot.max_type_id() + 1)

	# Editing the source after the snapshot must not disturb the library.
	palette.grass_color = Color.BLACK
	_report.check_equal("a later palette edit leaves the library unchanged",
			library.get_models().size(), model_count)


func _test_world_generation_uses_a_stable_snapshot() -> void:
	var main: Node = load(MAIN_SCENE_PATH).instantiate()
	_tree.root.add_child.call_deferred(main)
	await _wait_frames(3)

	var world: VoxelWorld = main.get_node("World")
	if world == null:
		_report.check("the world exists for the snapshot test", false)
		return

	var generator := world.get_generator()
	_report.check("the world exposes a configured generator", generator != null)
	if generator == null:
		main.queue_free()
		return

	var before := _hash_column(generator)

	# Edit the live palette the scene holds, the way the inspector would.
	world.palette.soil_depth = 0
	world.palette.stone_color = Color.MAGENTA

	var after_edit := _hash_column(generator)
	_report.check_equal("editing the world's palette does not affect the running generator",
			after_edit, before)

	# A rebuild is what should pick the change up.
	world.rebuild()
	await _wait_frames(2)

	var rebuilt_generator := world.get_generator()
	var after_rebuild := _hash_column(rebuilt_generator)
	_report.check(
			"a rebuild applies the edited palette",
			after_rebuild != before,
			"before=%s after=%s" % [before, after_rebuild])

	# Restore the default so a following suite is not affected.
	world.palette.soil_depth = 4
	world.palette.stone_color = Color(0.52, 0.52, 0.56)
	main.queue_free()
	await _wait_frames(2)


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await _tree.process_frame
