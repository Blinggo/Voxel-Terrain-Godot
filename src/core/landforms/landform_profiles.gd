class_name LandformProfiles
extends RefCounted

## Partition-of-unity profile blend over existing geography. Never hard selects
## a nearest type. Frequency bands stay global; profiles change their influence
## instead of spatially changing noise frequency and causing phase distortion.
const IDS := ["plains","rolling_hills","highlands","foothills","mountain_ranges","alpine_mountains","plateaus","mountain_basins","coastal_lowlands","steep_rocky"]
var profiles: Array[LandformProfile] = []

func _init(overrides: Array[LandformProfile] = []) -> void:
	profiles = [
		LandformProfile.make(&"plains",-1,0.30,0,0,0.1,0,0.15),
		LandformProfile.make(&"rolling_hills",1,0.75,0,0,0.2,0.1,0.3),
		LandformProfile.make(&"highlands",8,1.05,0,0,0.4,0.3,0.4),
		LandformProfile.make(&"foothills",3,1.10,1,0,0.3,0.4,0.4),
		LandformProfile.make(&"mountain_ranges",8,1.65,6,1,0.6,1,0.7),
		LandformProfile.make(&"alpine_mountains",15,2.20,12,2,1,1.4,1),
		LandformProfile.make(&"plateaus",3,1,0,0,0.1,0.05,0.2),
		LandformProfile.make(&"mountain_basins",-5,0.45,0,4,0.1,0.03,0.15),
		LandformProfile.make(&"coastal_lowlands",0,0.5,0,0,0,0,0),
		LandformProfile.make(&"steep_rocky",5,1.5,5,1,0.5,1.5,0.9),
	]
	for override in overrides:
		if override == null:
			continue
		var index := IDS.find(String(override.id))
		if index >= 0:
			profiles[index] = override.duplicate(true)

## Input: landmass, mountains, hills, plateau, valley, elevation (-1..1).
func weights(landmass: float, mountains: float, hills: float, plateau: float, valley: float, elevation: float) -> PackedFloat32Array:
	var inland := smoothstep(-0.02,0.34,landmass)
	var m := clampf(mountains,0,1)
	var h := clampf(hills,0,1)
	var p := clampf(plateau,0,1)
	var v := clampf(valley,0,1)
	var e := clampf(elevation*0.5+0.5,0,1)
	var open := inland*(1-p)
	var result := PackedFloat32Array([
		open*pow(1-m,4)*pow(1-h,2)*(1-v),
		open*h*(1-m)*(1-v*0.5),
		open*smoothstep(0.45,0.85,e)*(1-m)*(1-v),
		open*4*m*(1-m)*(1-m),
		open*m*m*3*(1-v*0.3),
		open*smoothstep(0.40,0.85,m)*2,
		inland*p*3,
		open*v*(0.4+m),
		1-inland,
		open*m*v*0.7])
	var total := 0.0
	for i in range(result.size()):
		# Wider transition -> softer dominance; strictly positive exponent.
		result[i] = pow(result[i],1.0/maxf(0.25,profiles[i].transition_width))
		total += result[i]
	if total < 0.00001:
		result[0] = 1.0
		total = 1.0
	for i in range(result.size()):
		result[i] /= total
	return result

func shape(height: float, base: float, landmass: float, m: float, h: float, p: float, v: float, e: float) -> float:
	var w := weights(landmass,m,h,p,v,e)
	var result := 0.0
	for i in range(w.size()):
		var profile := profiles[i]
		var shaped_relief := signf(height-base)*24.0*pow(absf(height-base)/24.0,maxf(0.25,profile.slope_sharpness))
		result += w[i]*(base + shaped_relief*profile.relief + profile.broad_elevation + profile.ridge_influence*m - profile.valley_influence*v)
	# Preserve ocean/coast layout; modifications fade in on established land.
	return lerpf(height,result,smoothstep(0.0,0.34,landmass))

func density_controls(landmass: float, m: float, h: float, p: float, v: float, e: float) -> Vector3:
	var w := weights(landmass,m,h,p,v,e)
	var result := Vector3.ZERO
	for i in range(w.size()):
		var profile := profiles[i]
		result += w[i]*Vector3(profile.geological_influence,profile.structure_influence,profile.roughness)
	return result
