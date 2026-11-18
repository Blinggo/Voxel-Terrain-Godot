class_name MountainShowcase
extends RefCounted

## Shared reproducible poses for captures and the Android Editor tour.
const SITES := [
	{"id":"alpine","profile":"alpine","seed":1337,"target":Vector3(-16,125,-1360),"distance":110.0,"pitch":-25.0,"yaw":25.0},
	{"id":"massif","profile":"massif","seed":1337,"target":Vector3(-16,125,-1360),"distance":110.0,"pitch":-25.0,"yaw":25.0},
	{"id":"rounded","profile":"rounded","seed":90210,"target":Vector3(-384,110,-128),"distance":110.0,"pitch":-22.0,"yaw":35.0},
	{"id":"rugged","profile":"rugged","seed":1337,"target":Vector3(-64,110,-1472),"distance":100.0,"pitch":-18.0,"yaw":-180.0},
	{"id":"eroded","profile":"eroded","seed":1337,"target":Vector3(-16,125,-1360),"distance":110.0,"pitch":-35.0,"yaw":-30.0},
	{"id":"highland","profile":"highland","seed":1337,"target":Vector3(-16,125,-1360),"distance":110.0,"pitch":-25.0,"yaw":25.0},
	{"id":"foothills","profile":"","seed":1337,"target":Vector3(-64,48,-256),"distance":100.0,"pitch":-22.0,"yaw":35.0},
	{"id":"basin","profile":"","seed":1337,"target":Vector3(320,30,-640),"distance":120.0,"pitch":-48.0,"yaw":25.0},
	{"id":"lake_range","profile":"","seed":1337,"target":Vector3(32,70,-1472),"distance":110.0,"pitch":-30.0,"yaw":35.0},
	{"id":"distant","profile":"","seed":1337,"target":Vector3(-16,125,-1360),"distance":180.0,"pitch":-8.0,"yaw":35.0}
]

static func apply_profile(config: WorldConfig, site: Dictionary) -> void:
	config.world_seed = site.seed
	config.density_mode = 1
	config.mountain_profiles.clear()
	if not String(site.profile).is_empty():
		config.mountain_profiles.append(load("res://resources/mountains/"+site.profile+".tres").duplicate(true))
