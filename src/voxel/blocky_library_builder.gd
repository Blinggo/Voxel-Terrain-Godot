class_name BlockyLibraryBuilder
extends RefCounted

## Builds the Voxel Tools blocky mesher assets: the block library, the mesher
## and the material the mesher's vertex colours are drawn with.
##
## Built in code rather than saved as `.tres` so the palette stays the single
## source of truth for both type ids and colours. If the library were an asset,
## the ids in [BlockPalette] and the indices in the asset could drift apart
## silently; here they cannot, because the assert below fails loudly.
##
## [b]Slot 0 must be empty.[/b] Voxel Tools' blocky mesher treats type id 0 as
## air unconditionally. The library therefore reserves slot 0 for
## [VoxelBlockyModelEmpty] and starts real blocks at id 1.
##
## [b]bake() is required.[/b] The mesher only reads baked library data (it is
## the only form safe to share across worker threads), so the library must be
## baked before it is handed to a mesher, otherwise the terrain is silently
## empty.


static func build_library(palette: BlockPalette) -> VoxelBlockyLibrary:
	assert(palette != null, "BlockyLibraryBuilder requires a BlockPalette.")
	assert(BlockPalette.AIR == 0, "Voxel Tools requires type id 0 to mean air.")

	var library := VoxelBlockyLibrary.new()

	var air := VoxelBlockyModelEmpty.new()
	air.resource_name = "air"
	library.add_model(air)

	# Ids must stay in lockstep with BlockPalette: the generator writes ids, the
	# library resolves them to models.
	for type_id in range(BlockPalette.GRASS, palette.max_type_id() + 1):
		var model := VoxelBlockyModelCube.new()
		model.resource_name = "block_%d" % type_id
		model.color = palette.get_color(type_id)
		# Let the mesher skip faces shared with any neighbour (internal faces).
		model.culls_neighbors = true
		library.add_model(model)

	assert(
		library.get_models().size() == palette.max_type_id() + 1,
		"Blocky library and BlockPalette disagree on the number of types."
	)

	library.bake()
	return library


static func build_mesher(library: VoxelBlockyLibrary) -> VoxelMesherBlocky:
	var mesher := VoxelMesherBlocky.new()
	mesher.library = library
	# Vertex-baked ambient occlusion: cheap, and it is what makes blocky terrain
	# readable without any texture work.
	mesher.occlusion_enabled = true
	mesher.occlusion_darkness = 0.5
	return mesher


## Material used for the whole terrain. The blocky mesher writes per-vertex
## colours and no textures, so the material only has to opt into vertex colour.
static func build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 0.95
	material.metallic = 0.0
	return material
