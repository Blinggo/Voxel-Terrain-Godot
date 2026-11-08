class_name ValleyModule
extends GenerationModule

## Valleys, mountain passes and enclosed basins, as a carve amount.
##
## Output: [code]0.0 .. 1.0[/code] on land, 0 over water. The surface composer
## subtracts [code]output * depth[/code] from the composed height, so this module
## never decides an absolute elevation - it only says how much material a shaped
## region removes.
##
## [b]Why valleys are ridged noise, not circles.[/b] A valley floor follows the
## line of least resistance across a landscape, so valley fields should be
## [i]linear[/i] features that branch. Ridged noise is the cheapest source of
## continuous crest lines, and its crests are exactly what is wanted here: a valley
## is a ridge line in the carve field. The network field is ridged noise at a
## wavelength of roughly 450 voxels, warped, and sharpened so the valley floor is
## narrow and its sides climb away. A second ridged field at about three times the
## frequency supplies tributaries, which is what makes a network rather than a set
## of parallel lines. There is no flow routing, no accumulation and no water: the
## hierarchy is a frequency ratio, not a drainage calculation.
##
## [b]Passes.[b] The carve amount is scaled up where
## [member MountainModule] is high, so a valley crossing a range cuts deeper than
## the same valley in the lowlands. That intersection is a mountain pass, and it
## also keeps the valleys from looking pasted on top of the mountains.
##
## [b]Basins.[/b] Enclosed depressions come from a separate low-frequency field,
## masked to points where no valley already is, and deepened towards their centre
## by squaring the mask. They are the one place the shape is roughly round, so they
## are kept small and rare; the valley network is what supplies the large structure.
##
## [b]No hydrology.[/b] Nothing here accumulates, transports or conserves anything,
## and the field is a pure function of position, so a valley appears in the same
## place in every chunk and in every direction of approach. Full hydrological
## simulation is explicitly deferred.

const MODULE_ID := &"valleys"
const OUTPUT_FIELD := &"valleys"

## Broad valley network.
const NETWORK_LOW := 0.52
const NETWORK_HIGH := 0.88

## Tributaries: narrower, shallower, and allowed only where some valley structure
## already exists, so they join the network instead of crossing it.
const TRIBUTARY_LOW := 0.58
const TRIBUTARY_HIGH := 0.90
const TRIBUTARY_WEIGHT := 0.55

## Basins.
const BASIN_LOW := 0.62
const BASIN_HIGH := 0.86
const BASIN_WEIGHT := 0.92

## Extra carve inside mountains, which is what turns a valley into a pass.
const MOUNTAIN_BOOST := 0.45

## Land gate. Valleys are a land feature: this must reach zero before the
## shoreline, or carving would cut channels into the seafloor.
const LAND_INNER := -0.02
const LAND_OUTER := 0.12

const WARP_AMPLITUDE := 90.0

var _network: FastNoiseLite
var _tributaries: FastNoiseLite
var _basins: FastNoiseLite
var _warp: FastNoiseLite

var _landmass_index := -1
var _mountains_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([&"landmass", &"mountainness"]),
			1
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	var base := config.valley_frequency
	_landmass_index = dependency_index(&"landmass")
	_mountains_index = dependency_index(&"mountainness")

	_network = context.make_noise_stream(
			MODULE_ID,
			version,
			1,
			base,
			3,
			FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			FastNoiseLite.FRACTAL_RIDGED
	)
	_tributaries = context.make_noise_stream(
			MODULE_ID,
			version,
			2,
			base * 3.1,
			2,
			FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			FastNoiseLite.FRACTAL_RIDGED
	)
	_basins = context.make_noise_stream(MODULE_ID, version, 3, base * 0.55, 2)
	_warp = context.make_noise_stream(MODULE_ID, version, 4, base * 1.4, 1)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var land := values[_landmass_index]
	var land_gate := smoothstep(LAND_INNER, LAND_OUTER, land)
	if land_gate <= 0.0:
		values[get_output_index()] = 0.0
		return

	var mountains := values[_mountains_index]

	var warp := _warp.get_noise_2d(x, z) * WARP_AMPLITUDE
	var wx := x + warp
	var wz := z - warp

	var network := smoothstep(
			NETWORK_LOW,
			NETWORK_HIGH,
			clampf(_network.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	)
	var tributary := smoothstep(
			TRIBUTARY_LOW,
			TRIBUTARY_HIGH,
			clampf(_tributaries.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	) * TRIBUTARY_WEIGHT * (0.35 + 0.65 * network)

	var basin := clampf(_basins.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	var basin_mask := smoothstep(BASIN_LOW, BASIN_HIGH, basin)
	# Squared so the middle of a basin is markedly deeper than its rim: a basin is
	# a depression with a floor, not a hole with straight sides.
	basin_mask = basin_mask * basin_mask * BASIN_WEIGHT * (1.0 - network)

	var carve := maxf(network, tributary) * (1.0 + MOUNTAIN_BOOST * mountains)
	carve = maxf(carve, basin_mask)

	values[get_output_index()] = clampf(carve * land_gate, 0.0, 1.6)
