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
@export var generation_version: int = 1

# --- Landform amplitudes -----------------------------------------------------

## Average height of inland terrain, in voxels.
@export var base_height: float = 24.0

## Overall relief amplitude, in voxels. Scales hills, mountains and fine detail
## together.
@export_range(0.0, 128.0, 1.0) var terrain_height: float = 26.0

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
@export_range(0.0, 4.0, 0.05) var mountain_scale: float = 1.5

## Hill relief at full hilliness, as a multiple of [member terrain_height].
@export_range(0.0, 2.0, 0.05) var hill_scale: float = 0.60

## Fine per-column roughness, as a multiple of [member terrain_height].
@export_range(0.0, 1.0, 0.01) var detail_scale: float = 0.09

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

## Base frequency of the fine detail noise, in cycles per voxel.
@export_range(0.0001, 0.1, 0.0001) var terrain_frequency: float = 0.022

## Octaves of fractal detail noise. 1 disables fractal accumulation.
@export_range(1, 6, 1) var fractal_octaves: int = 4

# --- Streaming ---------------------------------------------------------------

## Streaming radius around the viewer, in voxels.
@export_range(32, 512, 16) var view_distance_voxels: int = 128

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
	other.continent_frequency = continent_frequency
	other.continent_octaves = continent_octaves
	other.continent_warp = continent_warp
	other.elevation_frequency = elevation_frequency
	other.mountain_frequency = mountain_frequency
	other.hill_frequency = hill_frequency
	other.terrain_frequency = terrain_frequency
	other.fractal_octaves = fractal_octaves
	other.view_distance_voxels = view_distance_voxels
	other.sampling_stride = sampling_stride
	other.show_sea_plane = show_sea_plane
	return other


func to_dictionary() -> Dictionary:
	return {
		"world_seed": world_seed,
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
		"continent_frequency": continent_frequency,
		"continent_octaves": continent_octaves,
		"continent_warp": continent_warp,
		"elevation_frequency": elevation_frequency,
		"mountain_frequency": mountain_frequency,
		"hill_frequency": hill_frequency,
		"terrain_frequency": terrain_frequency,
		"fractal_octaves": fractal_octaves,
		"view_distance_voxels": view_distance_voxels,
		"sampling_stride": sampling_stride,
		"show_sea_plane": show_sea_plane,
	}
