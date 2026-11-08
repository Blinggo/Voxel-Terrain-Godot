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

## Adapter selection only; both modes construct the same GeographicSurface.
@export var smooth_terrain: bool = false

## Size of the visual water plane, in voxels. Larger than the streaming radius so
## the sea reaches the horizon in every direction; the camera's far plane clips
## it long before its edge.
const SEA_PLANE_SIZE := 2048.0

var _water_view: HydrologyWaterView
var _terrain: VoxelTerrain
## First registered streaming viewer, cached so the sea can follow the camera
## without walking a scene group every frame.
var _viewer: VoxelViewer
var _surface: GeographicSurface
var _sea_plane: MeshInstance3D
var _generator: VoxelGeneratorScript
var _library: VoxelBlockyLibrary
var _build_count := 0
## Duration of the last [method rebuild] call, in milliseconds (main thread).
var _last_rebuild_ms := 0.0


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


## The geographic surface driving the terrain: module pipeline, cached fields and
## classification. Read-only once built.
func get_surface() -> GeographicSurface:
	return _surface


func get_generator() -> VoxelGeneratorScript:
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
	if _surface != null:
		return _surface.get_surface_height(x, z)
	return config.base_height if config != null else 0.0


## Tears down the current terrain and generates a fresh one from [member config].
func rebuild() -> void:
	# Main-thread cost of reconfiguring the world: teardown, snapshotting the
	# configuration, rebuilding the generation stack and the blocky library, and
	# adding the new terrain node. Streaming afterwards happens on worker
	# threads and is not part of this number. Measured unconditionally because a
	# single clock read costs nothing; whether it is displayed is the overlay's
	# business.
	var started_usec := Time.get_ticks_usec()
	_teardown()

	if config == null:
		config = WorldConfig.new()
	if palette == null:
		palette = BlockPalette.new()

	# Snapshot the configuration: the live resource can be edited in the
	# inspector while worker threads are generating, and generation must not
	# observe a changing parameter halfway through.
	var cfg := config.duplicate_config()

	# Same reasoning for the palette. The generator and the blocky library are
	# both built from this one snapshot, so the voxels a block is made of and
	# the model used to draw them cannot disagree even if the editor-facing
	# package is edited mid-generation. The next rebuild picks up the edit.
	var palette_snapshot := palette.create_snapshot()

	# Generation stack: module pipeline -> geographic surface -> block adapter.
	# The surface snapshots the configuration again internally, so the fields a
	# module reads can never differ from the ones the block palette was built
	# from.
	_surface = GeographicSurface.new(cfg)
	if not _surface.is_valid():
		push_error("VoxelWorld.rebuild(): generation pipeline failed to build.")
		return

	var mesher: VoxelMesher
	var material: StandardMaterial3D
	if smooth_terrain:
		var adapter := TerrainSmoothGenerator.new()
		adapter.configure(_surface)
		_generator = adapter
		var smooth := VoxelMesherTransvoxel.new()
		smooth.transitions_enabled = false
		smooth.edge_clamp_margin = 0.0
		mesher = smooth
		material = StandardMaterial3D.new()
		material.albedo_color = palette_snapshot.grass_color
		material.roughness = 0.95
	else:
		var adapter := TerrainBlockGenerator.new()
		adapter.configure(_surface, palette_snapshot)
		_generator = adapter
		_library = BlockyLibraryBuilder.build_library(palette_snapshot)
		mesher = BlockyLibraryBuilder.build_mesher(_library)
		material = BlockyLibraryBuilder.build_material()
	_terrain = VoxelTerrainBuilder.create_terrain(_generator, mesher, material,
		maxi(cfg.view_distance_voxels, cfg.vertical_view_distance_voxels))
	add_child(_terrain)

	configure_viewers(cfg.view_distance_voxels)

	if cfg.show_sea_plane:
		_sea_plane = _build_sea_plane(cfg.sea_level)
		add_child(_sea_plane)

	if cfg.hydrology_enabled:
		_water_view = HydrologyWaterView.new()
		_water_view.surface = _surface
		_water_view.radius = cfg.view_distance_voxels
		_water_view.vertical_radius = cfg.vertical_view_distance_voxels
		add_child(_water_view)

	_build_count += 1
	_last_rebuild_ms = float(Time.get_ticks_usec() - started_usec) / 1000.0
	terrain_rebuilt.emit(cfg.world_seed)


## Pushes the streaming radius onto every registered viewer. Viewers are plain
## nodes in the scene (the camera owns one), so the world only configures them
## instead of owning them.
func configure_viewers(view_distance_voxels: int) -> void:
	var tree := get_tree()
	if tree == null:
		return
	_resolve_viewer()
	for node in tree.get_nodes_in_group(VIEWER_GROUP):
		var viewer := node as VoxelViewer
		if viewer == null:
			continue
		viewer.view_distance = view_distance_voxels
		viewer.view_distance_vertical_ratio = float(config.vertical_view_distance_voxels) / float(maxi(1, view_distance_voxels))
		# No collision meshes are generated in M0.1, so do not ask for them.
		viewer.requires_collisions = false
		viewer.requires_visuals = true


## Keeps the sea under the camera.
##
## The plane used to be centred on the world origin, which meant that a viewer more
## than half a plane away from the origin - including every capture taken on a
## landmark out at z = -1400 - saw the terrain floating over the background with only
## a sliver of blue at the horizon. Following the viewer costs one Vector3 write per
## frame and keeps the water in front of the camera wherever it goes.
func _process(_delta: float) -> void:
	if _water_view != null:
		_water_view.viewer_position = get_viewer_position()
	if _sea_plane == null:
		return
	if _viewer == null or not is_instance_valid(_viewer):
		if not _resolve_viewer():
			return
	var here := _viewer.global_position
	var sea_y := _sea_plane.position.y
	if config != null:
		sea_y = config.sea_level + 0.02
	_sea_plane.position = Vector3(here.x, sea_y, here.z)


## Caches the first registered streaming viewer. Returns false while the scene has
## no viewer yet, which is normal on the frame the world is built.
func _resolve_viewer() -> bool:
	if _viewer != null and is_instance_valid(_viewer):
		return true
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group(VIEWER_GROUP):
		var viewer := node as VoxelViewer
		if viewer != null and viewer.is_inside_tree():
			_viewer = viewer
			return true
	return false


## A flat translucent plane at sea level, purely so submerged terrain reads as
## water. No simulation, no depth, no interaction: it exists because without it a
## world with real oceans looks like a world with holes in it.
func _build_sea_plane(sea_level: float) -> MeshInstance3D:
	var plane := PlaneMesh.new()
	plane.size = Vector2(SEA_PLANE_SIZE, SEA_PLANE_SIZE)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.35, 0.55, 0.62)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Rough enough that the directional light does not produce a blown-out
	# specular patch on a perfectly flat plane.
	material.roughness = 0.62
	material.metallic = 0.0

	var sea := MeshInstance3D.new()
	sea.name = "SeaPlane"
	sea.mesh = plane
	sea.material_override = material
	# Ground surface height s fills voxels up to floor(s); the water surface sits
	# at the first empty voxel row above sea level, nudged to avoid z-fighting
	# with a ground face that lands exactly on it.
	sea.position = Vector3(0.0, sea_level + 0.02, 0.0)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return sea


func _teardown() -> void:
	if is_instance_valid(_water_view):
		remove_child(_water_view)
		_water_view.queue_free()
	_water_view = null
	if is_instance_valid(_terrain):
		# Free while attached: the native terrain teardown may inspect transforms.
		# Detaching then queue_free left it alive but outside the scene tree.
		_terrain.free()
	_terrain = null

	if is_instance_valid(_sea_plane):
		if _sea_plane.get_parent() == self:
			remove_child(_sea_plane)
		_sea_plane.queue_free()
	_sea_plane = null
	_viewer = null


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
		"last_rebuild_ms": _last_rebuild_ms,
		"sea_level": config.sea_level if config != null else 0.0,
	}

	# Geography under the viewer: what the module pipeline thinks this place is.
	# Sampled at the viewer's own column so the panel reports the terrain the
	# camera is actually looking at.
	if _surface != null:
		var here := get_viewer_position()
		var geography := _surface.describe_at(int(floor(here.x)), int(floor(here.z)))
		status["terrain_type"] = geography["terrain_type"]
		status["surface_height_here"] = geography["surface_height"]
		status["continentalness"] = geography["continentalness"]
		status["landmass"] = geography["landmass"]
		status["tectonics"] = geography["tectonics"]
		status["mountainness"] = geography["mountainness"]
		status["plateaus"] = geography["plateaus"]
		status["valleys"] = geography["valleys"]
	else:
		status["terrain_type"] = &"unknown"

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
		# Passed through untouched: the overlay displays whichever keys exist
		# rather than assuming a schema.
		status["voxel_statistics"] = stats
	else:
		status["streaming_ready"] = false
		status["viewer_position"] = Vector3.ZERO
		status["dropped_loads"] = 0
		status["dropped_meshes"] = 0
		status["voxel_statistics"] = {}

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
