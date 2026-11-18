class_name MountainMorphology
extends RefCounted

## One immutable evaluator for every mountain style. No extra noise calls.
const DEFAULTS := [preload("res://resources/mountains/alpine.tres"),preload("res://resources/mountains/massif.tres"),preload("res://resources/mountains/rounded.tres"),preload("res://resources/mountains/rugged.tres"),preload("res://resources/mountains/eroded.tres"),preload("res://resources/mountains/highland.tres")]
var profiles: Array[LandformProfile] = []
var _curves: Array[PackedFloat32Array] = []

func _init(configured: Array[LandformProfile] = []) -> void:
	var source: Array = configured.filter(func(item): return item != null)
	if source.is_empty(): source = DEFAULTS
	for item in source:
		if item == null: continue
		var profile: LandformProfile = item.duplicate(true)
		profiles.append(profile)
		_curves.append(compile_vertical(profile))
	assert(not profiles.is_empty(),"Mountain catalogue must contain a profile")

func weights(selector: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	var total := 0.0
	for p in profiles:
		var width := maxf(0.02,p.transition_width*0.28)
		# Positive tails avoid holes for custom catalogues; normalized blend.
		var w := 1.0/(1.0+pow(absf(selector-p.morphology_position)/width,4))
		result.append(w)
		total += w
	for i in range(result.size()): result[i] /= total
	return result

## Input distance is absolute single-octave primary noise after existing warp.
## Existing ribs provide secondary peaks/cols and gully modulation. No max of
## competing ridge components; smooth sums preserve continuous derivatives.
func evaluate(distance: float, ribs: float, detail: float, selector: float) -> float:
	var w := weights(selector)
	var result := 0.0
	for i in range(profiles.size()):
		result += w[i]*evaluate_profile(profiles[i],_curves[i],distance,ribs,detail,selector*2-1)
	return result

static func evaluate_profile(p: LandformProfile, curve: PackedFloat32Array, distance: float, ribs: float, detail: float, geological: float = 0.0) -> float:
	var d := absf(distance)/maxf(0.05,p.mountain_width)
	var summit := exp(-pow(d/maxf(0.03,p.summit_width),clampf(2.0/maxf(0.1,p.summit_sharpness),1.05,4.0)))
	var shoulder := exp(-pow(d/maxf(0.05,p.shoulder_width),2))
	var foot := exp(-pow(d/maxf(0.05,p.foothill_width),2))
	var ridge := exp(-pow((1-clampf(ribs,0,1))/maxf(0.03,p.ridge_width),2))
	var influence := clampf(p.mountain_ridge_influence,0,1)
	# Nonzero col floor keeps connected crest systems; ribs add flank summits.
	var crest := summit*(1-influence*0.3*(1-ridge))
	var shape := 0.58*crest+0.30*shoulder+0.12*foot
	shape += 0.18*influence*ridge*shoulder*(1-summit)
	# Analytical gully/valley shaping, NOT simulated erosion.
	shape *= 1-0.3*clampf(p.mountain_valley_influence,0,1)*(1-ridge)*(1-summit)
	shape += p.surface_roughness*detail*shoulder*(1-summit)
	shape *= 1+p.geological_detail*geological*(1-summit)*0.25
	return maxf(0,p.overall_elevation)*vertical(curve,clampf(shape,0,1))

## Invert increasing threshold(height) keys into height(signal), using a
## monotone cubic Hermite interpolant. Unlike per-segment smoothstep, slopes do
## not become zero at every key, so no accidental horizontal terraces.
static func compile_vertical(p: LandformProfile) -> PackedFloat32Array:
	var xs := p.terrain_y_thresholds
	var ys := p.terrain_y_positions
	var valid := xs.size() == ys.size() and xs.size() >= 2 and xs.size() <= 16
	if valid:
		valid = xs[0] == 0 and ys[0] == 0 and xs[-1] == 1 and ys[-1] == 1
		for i in range(1,xs.size()): valid = valid and xs[i] > xs[i-1] and ys[i] > ys[i-1]
	if not valid:
		push_warning("Invalid mountain vertical keys: using identity, not a discontinuous curve")
		xs = PackedFloat32Array([0,1])
		ys = PackedFloat32Array([0,1])
	var result := PackedFloat32Array()
	for i in range(xs.size()):
		var before := (ys[i]-ys[i-1])/(xs[i]-xs[i-1]) if i > 0 else (ys[1]-ys[0])/(xs[1]-xs[0])
		var after := (ys[i+1]-ys[i])/(xs[i+1]-xs[i]) if i < xs.size()-1 else before
		var tangent := 2*before*after/(before+after)
		result.append_array(PackedFloat32Array([xs[i],ys[i],tangent]))
	return result

static func vertical(curve: PackedFloat32Array, value: float) -> float:
	var x := clampf(value,0,1)
	for i in range(0,curve.size()-3,3):
		if x > curve[i+3]: continue
		var h := curve[i+3]-curve[i]
		var t := (x-curve[i])/h
		var t2 := t*t
		var t3 := t2*t
		return (2*t3-3*t2+1)*curve[i+1]+(t3-2*t2+t)*h*curve[i+2]+(-2*t3+3*t2)*curve[i+4]+(t3-t2)*h*curve[i+5]
	return 1.0
