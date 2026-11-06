class_name BlockPalette
extends Resource

## Voxel type ids used by the terrain, plus the rule that maps a voxel position
## to a type.
##
## The surface logic (what counts as "one block below the surface") lives here
## rather than in the generator or in the voxel integration, so that material
## rules can grow without touching either of them.
##
## [b]Id 0 is air by contract.[/b] Voxel Tools' blocky mesher always treats type
## id 0 as empty and skips it, so the palette and the blocky library must agree
## that 0 means air. The constants below are the single source of truth for that
## agreement.

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3

## Number of voxels of dirt directly below the grass layer.
@export_range(0, 16, 1) var soil_depth: int = 4

@export var grass_color: Color = Color(0.36, 0.62, 0.29)
@export var dirt_color: Color = Color(0.45, 0.33, 0.22)
@export var stone_color: Color = Color(0.52, 0.52, 0.56)


## Type of the voxel at world y, given the (fractional) surface height of its
## column.
func classify(y: int, surface_height: float) -> int:
	if float(y) > surface_height:
		return AIR

	# Depth in voxels below the topmost solid voxel of the column.
	var depth := int(floor(surface_height)) - y

	if depth == 0:
		return GRASS
	if depth <= soil_depth:
		return DIRT
	return STONE


## Highest type id the palette can produce. Used to validate the blocky
## library, which must contain a model for every id in 0..max_type_id().
func max_type_id() -> int:
	return STONE


func get_color(type_id: int) -> Color:
	match type_id:
		GRASS:
			return grass_color
		DIRT:
			return dirt_color
		STONE:
			return stone_color
		_:
			return Color.MAGENTA
