class_name VoxelWorld
extends Node3D

## Owns the lifetime of the terrain: builds the generation stack, creates the
## [VoxelTerrain] node, and rebuilds everything when the seed or shape changes.
##
## It is a plain node referenced by the scene, not an autoload singleton, so a
## second world (for comparison, or in a test) is just another instance.
##
## [b]Why rebuilding instead of mutating.[/b] Voxel Tools caches generated voxel
## blocks and the meshes derived from them; swapping the generator on a live
## terrain does not invalidate that cache, so the previous seed's blocks would
## keep showing. Recreating the terrain node is the only public-API way to
## guarantee that a new seed produces a new world, so that is what
## [method rebuild] does. It also means generation state is never shared between
## two configurations.

signal terrain_rebuilt(world_seed: int)

## Scene nodes carrying [VoxelViewer] join this group so the world can push
## streaming settings to them without the world owning the camera.
const VIEWER_GROUP := "voxel_viewers"

## Generation parameters. Editable in the inspector; the debug panel also
## overrides them at runtime through [method apply_config].
@export var config: WorldConfig

## Material rules for the surface.
@export var palette: BlockPalette

## Build a terrain as soon as the node enters the tree.
@export var build_on_ready: bool = true

## Vertical extent of the streaming region, as a fraction of the horizontal
## view distance. A heightmap world is mostly air above and stone below, so
## shrinking this cuts a large amount of needless generation on mobile.
@export var viewer_vertical_ratio: float = 0.5

var _terrain: VoxelTerrain
var _height_field: TerrainHeightField
var _generator: TerrainBlockGenerator
var _library: VoxelBlockyLibrary
var _build_count := 0


func _ready() -> void:
	if config == null:
		config = WorldConfig.new()
	if palette == null:
		palette = BlockPalette.new()
	if build_on_ready:
		rebuild()


## The live terrain node, or null before the first build.
func get_terrain() -> VoxelTerrain:
	return _terrain


func get_height_field() -> TerrainHeightField:
	return _height_field


func get_generator() -> TerrainBlockGenerator:
	return _generator


func get_build_count() -> int:
	return _build_count


## Replaces the current settings and rebuilds the world.
func apply_config(new_config: WorldConfig) -> void:
	if new_config == null:
		return
	config = new_config
	rebuild()


## Changes the seed and rebuilds. Convenience over [method apply_config] for the
## debug panel and tests.
func set_world_seed(value: int) -> void:
	if config == null:
		config = WorldConfig.new()
	config.world_seed = value
	rebuild()


## Surface height of a column, in voxels. Safe before the first build.
func get_surface_height(x: int, z: int) -> float:
	if _height_field != null:
		return _height_field.get_surface_height(x, z)
	return config.base_height if config != null else 0.0


## Tears down the current terrain and generates a fresh one from [member config].
func rebuild() -> void:
	_teardown()

	if config == null:
		config = WorldConfig.new()
	if palette == null:
		palette = BlockPalette.new()

	# Snapshot the configuration: the live resource can be edited in the
	# inspector while worker threads are generating, and generation must not
	# observe a changing parameter halfway through.
	var cfg := config.duplicate_config()

	# Generation stack: noise -> height field -> block adapter. Each link is
	# replaceable without touching the others.
	var noise := FastNoiseLiteSource.new(cfg.world_seed, cfg.terrain_frequency, cfg.fractal_octaves)
	_height_field = TerrainHeightField.new(noise, cfg.base_height, cfg.terrain_height)

	_generator = TerrainBlockGenerator.new()
	_generator.configure(_height_field, palette)

	# Voxel Tools stack: block library -> mesher -> terrain node.
	_library = BlockyLibraryBuilder.build_library(palette)
	var mesher := BlockyLibraryBuilder.build_mesher(_library)
	var material := BlockyLibraryBuilder.build_material()

	_terrain = VoxelTerrainBuilder.create_terrain(_generator, mesher, material, cfg.view_distance_voxels)
	add_child(_terrain)

	_configure_viewers(cfg.view_distance_voxels)

	_build_count += 1
	terrain_rebuilt.emit(cfg.world_seed)


## Pushes the streaming radius onto every registered viewer. Viewers are plain
## nodes in the scene (the camera owns one), so the world only configures them
## instead of owning them.
func _configure_viewers(view_distance_voxels: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group(VIEWER_GROUP):
		var viewer := node as VoxelViewer
		if viewer == null:
			continue
		viewer.view_distance = view_distance_voxels
		viewer.view_distance_vertical_ratio = viewer_vertical_ratio
		# No collision meshes are generated in M0.1, so do not ask for them.
		viewer.requires_collisions = false
		viewer.requires_visuals = true


func _teardown() -> void:
	if is_instance_valid(_terrain):
		if _terrain.get_parent() == self:
			remove_child(_terrain)
		_terrain.queue_free()
	_terrain = null


## Snapshot of generation state, consumed by the debug overlay.
## Reading [method VoxelTerrain.get_statistics] is cheap and non-blocking.
func get_status() -> Dictionary:
	var status := {
		"seed": config.world_seed if config != null else 0,
		"base_height": config.base_height if config != null else 0.0,
		"terrain_height": config.terrain_height if config != null else 0.0,
		"terrain_frequency": config.terrain_frequency if config != null else 0.0,
		"view_distance": config.view_distance_voxels if config != null else 0,
		"build_count": _build_count,
		"terrain_present": is_instance_valid(_terrain),
	}

	if is_instance_valid(_terrain):
		var stats: Dictionary = _terrain.get_statistics()
		var viewer_position := get_viewer_position()

		# Note: Voxel Tools 1.7 reports an "updated_blocks" counter, but nothing
		# in that build ever increments it, so it is always 0 and useless as a
		# progress indicator. The honest signal is whether the streaming region
		# around the viewer has finished meshing.
		var probe := AABB(
				viewer_position - Vector3(24.0, 24.0, 24.0),
				Vector3(48.0, 48.0, 48.0)
		)
		status["streaming_ready"] = _terrain.is_area_meshed(probe)
		status["viewer_position"] = viewer_position
		status["dropped_loads"] = int(stats.get("dropped_block_loads", 0))
		status["dropped_meshes"] = int(stats.get("dropped_block_meshs", 0))
	else:
		status["streaming_ready"] = false
		status["viewer_position"] = Vector3.ZERO
		status["dropped_loads"] = 0
		status["dropped_meshes"] = 0

	return status


## World position of the first registered streaming viewer, or the origin if
## there are none. Used for reporting only.
func get_viewer_position() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return Vector3.ZERO
	for node in tree.get_nodes_in_group(VIEWER_GROUP):
		var viewer := node as VoxelViewer
		if viewer != null and viewer.is_inside_tree():
			return viewer.global_position
	return Vector3.ZERO
