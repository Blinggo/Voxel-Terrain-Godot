class_name WorldConfig
extends Resource

## All user-facing terrain generation parameters.
##
## Kept as a [Resource] so a world can be configured in the inspector, saved as
## a `.tres`, or overridden at runtime by the debug panel, without editing code.
## The resource is treated as read-only while terrain is being generated: it is
## copied into a [GenerationContext] when a world is (re)built, so changing it
## never mutates state that worker threads are reading.
##
## Since M1 the parameters are grouped by what they control:
## [br]- [b]World[/b]: seed, generation version.
## [br]- [b]Landform amplitudes[/b]: how tall land, hills and ranges are.
## [br]- [b]Field frequencies[/b]: the horizontal scale of each geographic field.
## [br]- [b]Streaming[/b]: how far the voxel viewer streams.
##
## Frequencies are the horizontal scale of a field, and they are what decide
## whether a feature is visible from the camera at all: a continent field with a
## 2000-voxel period looks like a flat plain through a 128-voxel view distance.
## Defaults are tuned so a fresh world shows ocean, coast, plains, hills and a
## range within that radius.

# --- World -------------------------------------------------------------------

## Seed driving every deterministic decision in the world. Same seed, same
## terrain; different seed, different terrain.
@export var world_seed: int = 1337

## Version of the generation pipeline. Folded into every module's random stream,
## so incrementing it deliberately reshuffles the whole world. Bump it whenever a
## change would make previously generated terrain unreproducible anyway.
##
## 2 is M2: the land signal downstream modules read is now the composed landmass
## field, and every field's stream changed, so M1 terrain is deliberately not
## reproduced.
@export var generation_version: int = 2

# --- Landform amplitudes -----------------------------------------------------

## Average height of inland terrain, in voxels.
@export var base_height: float = 24.0

## Overall relief amplitude, in voxels. Scales hills, mountains and fine detail
## together.
@export_range(0.0, 128.0, 1.0, "or_greater") var terrain_height: float = 26.0

## Height of the sea surface, in voxels. Terrain below this level is under water.
@export var sea_level: float = 20.0

## Extra rise from the coast to a continental interior, in voxels.
@export var inland_rise: float = 4.0

## How far the multi-scale elevation field may raise the land, in voxels.
@export var elevation_gain: float = 8.0

## Depth of the deepest ocean, in voxels below [member sea_level].
@export var ocean_depth: float = 16.0

## Mountain relief at full mountainness, as a multiple of
## [member terrain_height].
@export_range(0.0, 4.0, 0.05) var mountain_scale: float = 1.8

## Hill relief at full hilliness, as a multiple of [member terrain_height].
@export_range(0.0, 2.0, 0.05) var hill_scale: float = 0.60

## Fine per-column roughness, as a multiple of [member terrain_height].
@export_range(0.0, 1.0, 0.01) var detail_scale: float = 0.09

## How far a plateau interior sits above the base land surface, in voxels. The
## surface is blended towards that level, so this is the height of the step up
## from the surrounding plain rather than an amount added to relief.
@export_range(0.0, 64.0, 1.0) var plateau_uplift: float = 26.0

## Number of shelves the plateau margin is terraced into. 1 disables terracing.
@export_range(1, 8, 1) var plateau_steps: int = 3

## Depth of a full-strength valley, as a multiple of [member terrain_height].
@export_range(0.0, 1.0, 0.01) var valley_depth: float = 0.26

## How strongly the archipelago field pushes the seafloor up into islands. Must be
## large enough to carry the land signal across zero (roughly 0.5).
@export_range(0.0, 1.0, 0.01) var island_strength: float = 0.55

## How far coastline detail may perturb the land signal. Small: it should shape
## the shoreline, not move the continent.
@export_range(0.0, 0.5, 0.01) var coast_strength: float = 0.14

# --- Field frequencies -------------------------------------------------------

## Frequency of the continentalness field, in cycles per voxel. Smaller values
## make bigger continents.
@export_range(0.0001, 0.02, 0.0001) var continent_frequency: float = 0.0014

## Octaves of the continentalness field.
@export_range(1, 6, 1) var continent_octaves: int = 3

## How far the continentalness field's sample coordinate is displaced, in voxels.
## Breaks up the noise lattice so continents do not repeat.
@export_range(0.0, 1000.0, 10.0) var continent_warp: float = 260.0

## Frequency of the broadest band of the multi-scale elevation field.
@export_range(0.0001, 0.02, 0.0001) var elevation_frequency: float = 0.0025

## Frequency of the ridged field that shapes mountain ranges.
@export_range(0.0001, 0.05, 0.0001) var mountain_frequency: float = 0.006

## Frequency of the hills field.
@export_range(0.0001, 0.1, 0.0001) var hill_frequency: float = 0.02

## Cell size of the tectonic plate lattice, in voxels. One plate is roughly this
## wide, so it sets the spacing of mountain systems and geological regions.
@export_range(128.0, 2048.0, 16.0) var plate_cell_size: float = 520.0

## Width of the band around a plate boundary in which tectonic influence acts,
## in voxels. Larger makes broader, softer ranges.
@export_range(16.0, 512.0, 4.0) var plate_boundary_width: float = 110.0

## Frequency of the broad archipelago cluster field. Smaller values make island
## groups larger and further apart.
@export_range(0.0001, 0.01, 0.0001) var archipelago_frequency: float = 0.0011

## Frequency of the coastline detail field.
@export_range(0.0005, 0.05, 0.0005) var coast_frequency: float = 0.008

## Frequency of the valley network field. Smaller values make longer, more widely
## spaced valleys.
@export_range(0.0001, 0.02, 0.0001) var valley_frequency: float = 0.0022

## Frequency of the plateau field. Smaller values make larger plateaus.
@export_range(0.0001, 0.02, 0.0001) var plateau_frequency: float = 0.0016

## Base frequency of the fine detail noise, in cycles per voxel.
@export_range(0.0001, 0.1, 0.0001) var terrain_frequency: float = 0.022

## Octaves of fractal detail noise. 1 disables fractal accumulation.
@export_range(1, 6, 1) var fractal_octaves: int = 4

# --- Hydrology ---------------------------------------------------------------

## Independently switchable; fields retain their M2/M3 random streams.
@export var hydrology_enabled: bool = true
@export_range(4.0, 80.0, 1.0) var hydrology_source_rise: float = 14.0
@export_range(0.5, 1.25, 0.05) var hydrology_width_scale: float = 1.0

# --- Streaming ---------------------------------------------------------------

## Streaming radius around the viewer, in voxels.
@export_range(32, 512, 16) var view_distance_voxels: int = 128

## Independent vertical radius. Finite nearby streaming follows the viewer.
@export_range(32, 512, 16, "or_greater") var vertical_view_distance_voxels: int = 128

## Spacing of the node grid the geographic fields are evaluated on, in voxels.
## Larger is cheaper and coarser. Must stay well below the wavelength of the
## finest field or detail is lost; 8 is one block face at the default block size.
@export_range(1, 32, 1) var sampling_stride: int = 8

## Show a translucent plane at [member sea_level] so submerged terrain reads as
## water. Purely visual: nothing is simulated.
@export var show_sea_plane: bool = true


## Copy of this configuration, so callers can take a stable snapshot.
func duplicate_config() -> WorldConfig:
	var other := WorldConfig.new()
	other.world_seed = world_seed
	other.hydrology_enabled = hydrology_enabled
	other.hydrology_source_rise = hydrology_source_rise
	other.hydrology_width_scale = hydrology_width_scale
	other.generation_version = generation_version
	other.base_height = base_height
	other.terrain_height = terrain_height
	other.sea_level = sea_level
	other.inland_rise = inland_rise
	other.elevation_gain = elevation_gain
	other.ocean_depth = ocean_depth
	other.mountain_scale = mountain_scale
	other.hill_scale = hill_scale
	other.detail_scale = detail_scale
	other.plateau_uplift = plateau_uplift
	other.plateau_steps = plateau_steps
	other.valley_depth = valley_depth
	other.island_strength = island_strength
	other.coast_strength = coast_strength
	other.plate_cell_size = plate_cell_size
	other.plate_boundary_width = plate_boundary_width
	other.archipelago_frequency = archipelago_frequency
	other.coast_frequency = coast_frequency
	other.valley_frequency = valley_frequency
	other.plateau_frequency = plateau_frequency
	other.continent_frequency = continent_frequency
	other.continent_octaves = continent_octaves
	other.continent_warp = continent_warp
	other.elevation_frequency = elevation_frequency
	other.mountain_frequency = mountain_frequency
	other.hill_frequency = hill_frequency
	other.terrain_frequency = terrain_frequency
	other.fractal_octaves = fractal_octaves
	other.view_distance_voxels = view_distance_voxels
	other.vertical_view_distance_voxels = vertical_view_distance_voxels
	other.sampling_stride = sampling_stride
	other.show_sea_plane = show_sea_plane
	return other


func to_dictionary() -> Dictionary:
	return {
		"world_seed": world_seed,
		"hydrology_enabled": hydrology_enabled,
		"hydrology_source_rise": hydrology_source_rise,
		"hydrology_width_scale": hydrology_width_scale,
		"generation_version": generation_version,
		"base_height": base_height,
		"terrain_height": terrain_height,
		"sea_level": sea_level,
		"inland_rise": inland_rise,
		"elevation_gain": elevation_gain,
		"ocean_depth": ocean_depth,
		"mountain_scale": mountain_scale,
		"hill_scale": hill_scale,
		"detail_scale": detail_scale,
		"plateau_uplift": plateau_uplift,
		"plateau_steps": plateau_steps,
		"valley_depth": valley_depth,
		"island_strength": island_strength,
		"coast_strength": coast_strength,
		"plate_cell_size": plate_cell_size,
		"plate_boundary_width": plate_boundary_width,
		"archipelago_frequency": archipelago_frequency,
		"coast_frequency": coast_frequency,
		"valley_frequency": valley_frequency,
		"plateau_frequency": plateau_frequency,
		"continent_frequency": continent_frequency,
		"continent_octaves": continent_octaves,
		"continent_warp": continent_warp,
		"elevation_frequency": elevation_frequency,
		"mountain_frequency": mountain_frequency,
		"hill_frequency": hill_frequency,
		"terrain_frequency": terrain_frequency,
		"fractal_octaves": fractal_octaves,
		"view_distance_voxels": view_distance_voxels,
		"vertical_view_distance_voxels": vertical_view_distance_voxels,
		"sampling_stride": sampling_stride,
		"show_sea_plane": show_sea_plane,
	}
