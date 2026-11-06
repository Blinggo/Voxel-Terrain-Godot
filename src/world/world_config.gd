class_name WorldConfig
extends Resource

## All user-facing terrain generation parameters for M0.1.
##
## Kept as a [Resource] so a world can be configured in the inspector, saved as
## a `.tres`, or overridden at runtime by the debug panel, without editing code.
## The resource is treated as read-only while terrain is being generated: it is
## copied into the height field / generator when a world is (re)built, so
## changing it never mutates state that worker threads are reading.

## Seed driving every deterministic decision in the world. Same seed, same
## terrain; different seed, different terrain.
@export var world_seed: int = 1337

## Average surface height, in voxels.
@export var base_height: float = 24.0

## Maximum deviation of the surface above or below [member base_height], in
## voxels. 0 produces a flat plane; larger values produce stronger relief.
@export_range(0.0, 128.0, 1.0) var terrain_height: float = 26.0

## Base frequency of the height noise, in cycles per voxel. Smaller values
## produce broader, smoother landforms; larger values produce tighter, noisier
## ones.
@export_range(0.0001, 0.1, 0.0001) var terrain_frequency: float = 0.008

## Octaves of fractal noise layered into the height field. 1 disables fractal
## accumulation.
@export_range(1, 6, 1) var fractal_octaves: int = 4

## Streaming radius around the viewer, in voxels.
@export_range(32, 512, 16) var view_distance_voxels: int = 128


## Copy of this configuration, so callers can take a stable snapshot.
func duplicate_config() -> WorldConfig:
	var other := WorldConfig.new()
	other.world_seed = world_seed
	other.base_height = base_height
	other.terrain_height = terrain_height
	other.terrain_frequency = terrain_frequency
	other.fractal_octaves = fractal_octaves
	other.view_distance_voxels = view_distance_voxels
	return other


func to_dictionary() -> Dictionary:
	return {
		"world_seed": world_seed,
		"base_height": base_height,
		"terrain_height": terrain_height,
		"terrain_frequency": terrain_frequency,
		"fractal_octaves": fractal_octaves,
		"view_distance_voxels": view_distance_voxels,
	}
