class_name LandformProfile
extends Resource

## One parameter set, not a generator. All ten types use one shared evaluator.
@export var id: StringName = &"plains"
@export var broad_elevation: float = 0.0
@export_range(0.5,2.0,0.05) var slope_sharpness: float = 1.0
@export var relief: float = 1.0
@export var ridge_influence: float = 0.0
@export var valley_influence: float = 0.0
@export var transition_width: float = 1.0
## Profile amplitudes for three independently configured fixed-frequency bands.
@export var geological_influence: float = 0.0
@export var structure_influence: float = 0.0
@export var roughness: float = 0.0

## M5.1 morphology parameters. Dimensionless widths are relative to the
## continuous primary-noise crest coordinate, NOT world height multipliers.
@export_group("Mountain morphology")
@export var overall_elevation: float = 1.15
@export var mountain_width: float = 0.8
@export var summit_width: float = 0.26
@export var summit_sharpness: float = 0.8
@export var ridge_width: float = 0.45
@export var mountain_ridge_influence: float = 0.35
@export var shoulder_width: float = 0.65
@export var foothill_width: float = 1.15
@export var mountain_valley_influence: float = 0.25
@export var surface_roughness: float = 0.04
@export var geological_detail: float = 0.12
@export var morphology_position: float = 0.5
@export_group("Vertical shaping")
## Threshold required to reach each relative elevation. Strictly increasing.
@export var terrain_y_positions := PackedFloat32Array([0,0.2,0.55,0.82,1])
@export var terrain_y_thresholds := PackedFloat32Array([0,0.12,0.45,0.78,1])

static func make(name: StringName, uplift: float, amplitude: float, ridge: float, valley: float, geo: float, structure: float, fine: float) -> LandformProfile:
	var profile := LandformProfile.new()
	profile.id = name
	profile.broad_elevation = uplift
	profile.relief = amplitude
	profile.ridge_influence = ridge
	profile.valley_influence = valley
	profile.geological_influence = geo
	profile.structure_influence = structure
	profile.roughness = fine
	return profile

func to_dictionary() -> Dictionary:
	return {"id":String(id),"broad_elevation":broad_elevation,"relief":relief,
		"slope_sharpness":slope_sharpness,"ridge_influence":ridge_influence,
		"valley_influence":valley_influence,"transition_width":transition_width,
		"geological_influence":geological_influence,"structure_influence":structure_influence,"roughness":roughness,
		"overall_elevation":overall_elevation,"mountain_width":mountain_width,
		"summit_width":summit_width,"summit_sharpness":summit_sharpness,
		"ridge_width":ridge_width,"mountain_ridge_influence":mountain_ridge_influence,
		"shoulder_width":shoulder_width,"foothill_width":foothill_width,
		"mountain_valley_influence":mountain_valley_influence,
		"surface_roughness":surface_roughness,"geological_detail":geological_detail,
		"morphology_position":morphology_position,
		"terrain_y_positions":terrain_y_positions,"terrain_y_thresholds":terrain_y_thresholds}
