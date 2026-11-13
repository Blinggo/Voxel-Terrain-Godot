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
		"geological_influence":geological_influence,"structure_influence":structure_influence,"roughness":roughness}
