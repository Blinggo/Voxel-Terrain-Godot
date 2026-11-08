extends RefCounted

## Integration tests: does Voxel Tools actually load, generate, and mesh the
## terrain described by [WorldConfig]?
##
## These run against the real `scenes/main.tscn`, so they cover the same node
## graph the project ships with.

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

## Wall-clock budget for a streaming region to finish meshing. Wall clock rather
## than frame count because software rendering can be far slower than a real GPU.
const STREAM_TIMEOUT_SECONDS := 45.0


static func run(report, tree: SceneTree) -> void:
	_test_extension_classes_registered(report)

	# The runner itself is still being set up when _ready runs, and the tree
	# refuses add_child() at that moment, so defer the insertion and let a frame
	# pass before touching the scene.
	var main = load(MAIN_SCENE_PATH).instantiate()
	tree.root.add_child.call_deferred(main)
	await _wait_frames(tree, 3)

	if not main.is_inside_tree():
		report.check("main scene enters the tree", false, "deferred add_child failed")
		return

	var world: VoxelWorld = main.world
	var camera: OrbitCamera = main.camera

	report.check("main scene wires its world reference", world != null)
	report.check("main scene wires its camera reference", camera != null)
	if world == null or camera == null:
		main.queue_free()
		return

	_test_terrain_configuration(report, world)

	# ---------------------------------------------------------------- generate
	var terrain := world.get_terrain()
	if terrain == null:
		report.check("terrain exists for further checks", false)
		main.queue_free()
		return

	var ready_ok := await _wait_for_area(tree, terrain, _sample_area())
	report.check("terrain block generation completes", ready_ok, _describe_stats(terrain))

	_test_geometry_exists(report, terrain)
	_test_voxels_match_the_height_field(report, world, terrain)
	_test_no_seams_in_live_terrain(report, world, terrain)

	# ------------------------------------------------------------- determinism
	var seed_a := 4242
	var hash_a := await _sample_hash_after_rebuild(tree, world, seed_a)
	var hash_a_repeat := await _sample_hash_after_rebuild(tree, world, seed_a)

	# -1 means the sample never became available. Without this guard the
	# equality check below would "pass" by comparing two failures.
	report.check("terrain was ready for determinism sampling", hash_a != -1)
	report.check("terrain was ready for repeat sampling", hash_a_repeat != -1)
	report.check_equal("same seed reproduces identical terrain", hash_a_repeat, hash_a)

	var hash_b := await _sample_hash_after_rebuild(tree, world, seed_a + 1)
	report.check("terrain was ready for alternate-seed sampling", hash_b != -1)
	report.check(
			"changing the seed changes the terrain",
			hash_b != hash_a,
			"seed %d -> %d, hash %d vs %d" % [seed_a, seed_a + 1, hash_a, hash_b]
	)

	# Restore the configured seed so the scene is left in a normal state.
	world.set_world_seed(world.config.world_seed)
	await _wait_frames(tree, 5)

	# ------------------------------------------------- air/sea visual ownership
	await _test_sea_plane_follows_the_camera(report, world, tree)

	# -------------------------------------------------------------- inspection
	_test_camera_input(report, tree, camera)

	main.queue_free()
	await _wait_frames(tree, 2)


static func _test_extension_classes_registered(report) -> void:
	var required := [
		"VoxelTerrain", "VoxelGeneratorScript", "VoxelMesherBlocky",
		"VoxelBlockyLibrary", "VoxelBuffer", "VoxelViewer", "VoxelFormat",
	]
	var missing := []
	for class_name_str in required:
		if not ClassDB.class_exists(class_name_str):
			missing.append(class_name_str)
	report.check(
			"Voxel Tools GDExtension classes are registered",
			missing.is_empty(),
			"missing: %s" % [missing]
	)


static func _test_terrain_configuration(report, world: VoxelWorld) -> void:
	var terrain := world.get_terrain()
	report.check("VoxelTerrain node was created", terrain != null)
	if terrain == null:
		return

	report.check("terrain has a generator", terrain.generator != null)
	report.check("generator is our custom TerrainBlockGenerator", terrain.generator is TerrainBlockGenerator)
	report.check("terrain uses the blocky mesher", terrain.mesher is VoxelMesherBlocky)

	var mesher := terrain.mesher as VoxelMesherBlocky
	report.check("blocky mesher has a library", mesher != null and mesher.library != null)
	if mesher != null and mesher.library != null:
		var expected := world.palette.max_type_id() + 1
		report.check_equal(
				"block library contains every palette type plus air",
				mesher.library.get_models().size(),
				expected
		)

	var format := terrain.format
	var type_depth := format.get_channel_depth(VoxelBuffer.CHANNEL_TYPE) if format != null else -1
	report.check_equal(
			"terrain format uses a 16-bit type channel",
			type_depth,
			VoxelBuffer.DEPTH_16_BIT
	)


static func _test_geometry_exists(report, terrain: VoxelTerrain) -> void:
	# Voxel Tools stores block meshes as RIDs rather than MeshInstance3D nodes,
	# so there is nothing to count from GDScript. `is_area_meshed` reports
	# whether every mesh block in a region has had a mesh applied, which is the
	# API-visible proof that generation + meshing actually ran.
	var area := _sample_area()
	report.check(
			"terrain mesh blocks are meshed around the origin",
			terrain.is_area_meshed(area),
			"area=%s" % str(area)
	)
	report.check(
			"terrain voxel data exists around the origin",
			terrain.has_data_block(Vector3i.ZERO),
			"data block at origin"
	)


## Every sampled column must be solid below the analytic surface and air above
## it. This is the check that proves the generated voxels are the terrain we
## asked for rather than arbitrary data.
static func _test_voxels_match_the_height_field(report, world: VoxelWorld, terrain: VoxelTerrain) -> void:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)

	var checked := 0
	var above_violations := 0
	var below_violations := 0
	var type_violations := 0

	for z in range(-24, 25, 8):
		for x in range(-24, 25, 8):
			var surface := world.get_surface_height(x, z)
			var top := int(floor(surface))

			var above := tool.get_voxel(Vector3i(x, top + 2, z))
			if above != BlockPalette.AIR:
				above_violations += 1

			var below := tool.get_voxel(Vector3i(x, top - 8, z))
			if below == BlockPalette.AIR:
				below_violations += 1

			var at_top := tool.get_voxel(Vector3i(x, top, z))
			if at_top != BlockPalette.GRASS:
				type_violations += 1

			checked += 1

	report.check_equal("voxels above the surface are air", above_violations, 0)
	report.check_equal("voxels below the surface are solid", below_violations, 0)
	report.check_equal("the top voxel of every column is the grass type", type_violations, 0)
	report.info("checked %d columns through the live terrain" % checked)


## Same seam check as the core suite, but read back through Voxel Tools from the
## terrain's actual voxel data, across the x = 0 and x = 32 boundaries.
static func _test_no_seams_in_live_terrain(report, world: VoxelWorld, terrain: VoxelTerrain) -> void:
	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)

	var mismatches := 0
	var checked := 0
	# -33..33 crosses the x = -32, x = 0 and x = 32 block planes.
	for x in range(-33, 34):
		for z in [-17, 0, 17]:
			var expected := int(floor(world.get_surface_height(x, z)))
			var actual := _scan_top_solid(tool, x, z, expected)
			if actual != expected:
				mismatches += 1
			checked += 1

	report.check_equal(
			"live terrain has no seam across block boundaries",
			mismatches,
			0
	)
	report.info("scanned %d columns across three block boundaries" % checked)


static func _scan_top_solid(tool: VoxelTool, x: int, z: int, expected: int) -> int:
	# Only inspect a window around the expected surface; scanning the full
	# column would be slow and prove nothing extra.
	for y in range(expected + 4, expected - 6, -1):
		if tool.get_voxel(Vector3i(x, y, z)) != BlockPalette.AIR:
			return y
	return -9999


## Rebuilds the world with a given seed, waits for it to stream, and returns a
## hash of the sampled column heights.
static func _sample_hash_after_rebuild(tree: SceneTree, world: VoxelWorld, world_seed: int) -> int:
	world.set_world_seed(world_seed)
	var terrain := world.get_terrain()
	var ok := await _wait_for_area(tree, terrain, _sample_area())
	if not ok:
		return -1

	var tool: VoxelTool = terrain.get_voxel_tool()
	tool.set_channel(VoxelBuffer.CHANNEL_TYPE)

	var values: Array[int] = []
	for z in range(-20, 21, 5):
		for x in range(-20, 21, 5):
			var expected := int(floor(world.get_surface_height(x, z)))
			values.append(_scan_top_solid(tool, x, z, expected))

	return hash(values)


static func _test_camera_input(report, tree: SceneTree, camera: OrbitCamera) -> void:
	var before := camera.global_transform

	# Simulate a left-button drag the way the desktop target receives it.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(640, 360)
	tree.root.push_input(press)

	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(760, 360)
	tree.root.push_input(motion)

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(760, 360)
	tree.root.push_input(release)

	var after := camera.global_transform
	report.check(
			"camera responds to inspection input",
			before.origin != after.origin,
			"moved from %v to %v" % [before.origin, after.origin]
	)

	var distance_before := camera.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(640, 360)
	tree.root.push_input(wheel)
	report.check(
			"camera zooms on wheel input",
			camera.distance < distance_before,
			"%.1f -> %.1f" % [distance_before, camera.distance]
	)


## The sea plane used to be pinned to the world origin, which meant a viewer more
## than half a plane away from it saw terrain floating over the background with a
## sliver of blue at the horizon. The plane must sit under the streaming viewer.
## Regression test for that defect: these assertions fail on the old code as soon as
## the camera is not at the origin, which it never is in the shipped scene.
static func _test_sea_plane_follows_the_camera(report, world, tree: SceneTree) -> void:
	var plane := world.get_node_or_null("SeaPlane") as MeshInstance3D
	report.check("the world puts a sea plane in the scene", plane != null)
	if plane == null:
		return

	await _wait_frames(tree, 2)
	var viewer: Vector3 = world.get_viewer_position()
	report.check(
			"the sea plane is centred under the streaming viewer",
			absf(plane.position.x - viewer.x) <= 1.0 and absf(plane.position.z - viewer.z) <= 1.0,
			"plane (%.0f, %.0f) viewer (%.0f, %.0f), origin distance %.0f"
					% [plane.position.x, plane.position.z, viewer.x, viewer.z, plane.position.length()]
	)
	var expected_y: float = world.config.sea_level + 0.02
	report.check(
			"the sea plane sits at sea level",
			absf(plane.position.y - expected_y) <= 0.001,
			"y=%.2f expected %.2f" % [plane.position.y, expected_y]
	)


# --------------------------------------------------------------------- helpers

static func _sample_area() -> AABB:
	# Must sit entirely inside the region the camera's VoxelViewer streams:
	# 128 voxels horizontally and (vertical ratio 0.5) 64 vertically around the
	# camera, which hovers near y = 82. A box reaching down to y = 0 would fall
	# outside that band and the wait could never be satisfied.
	return AABB(Vector3(-32.0, 32.0, -32.0), Vector3(64.0, 64.0, 64.0))


static func _wait_for_area(tree: SceneTree, terrain: VoxelTerrain, area: AABB) -> bool:
	if terrain == null:
		return false
	var deadline := Time.get_ticks_msec() + int(STREAM_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if terrain.is_area_meshed(area):
			return true
		await tree.process_frame
	return terrain.is_area_meshed(area)


static func _wait_frames(tree: SceneTree, count: int) -> void:
	for _i in range(count):
		await tree.process_frame


static func _describe_stats(terrain: VoxelTerrain) -> String:
	if terrain == null:
		return "no terrain"
	return "statistics=%s" % [terrain.get_statistics()]
