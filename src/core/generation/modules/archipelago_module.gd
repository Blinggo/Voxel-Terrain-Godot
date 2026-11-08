class_name ArchipelagoModule
extends GenerationModule

## Where island groups are, and how strongly they push the seafloor up into land.
##
## Output: [code]0.0 .. 1.0[/code]. 0 is open water with no island influence, 1 is
## the centre of an island.
##
## [b]Two terms, because islands come in two arrangements.[/b]
## - [i]Clustered[/i]: a very low-frequency field says where an archipelago
##   belongs, and a higher-frequency field fills that region with islands. The
##   product is a group of islands with shared orientation and spacing, which is
##   what makes a group read as a group instead of as scattered blobs.
## - [i]Isolated[/i]: a separate, rarer field places lone islands anywhere in open
##   water. Without it every island would be inside a cluster, which is the
##   opposite of how real oceans look.
##
## [b]Ocean-only.[/b] The whole field is multiplied by an offshore mask, so it can
## only add land to deep water. It cannot rework a coastline that the continental
## field already drew, and it never raises anything on a continent.
##
## [b]Strength is not applied here.[/b] The module emits a dimensionless [i]boost[/i];
## [method LandmassModule] decides how far that boost moves the land threshold.
## Keeping the conversion in one place is what lets the island strength be tuned
## or switched off without touching this module.

const MODULE_ID := &"archipelago"
const OUTPUT_FIELD := &"archipelago"

## Cluster field: below LOW no group, above HIGH a full group region.
const CLUSTER_LOW := 0.44
const CLUSTER_HIGH := 0.74

## Islands inside a cluster.
const GROUP_LOW := 0.50
const GROUP_HIGH := 0.76

## Lone islands are rarer and smaller than grouped ones.
const ISOLATED_LOW := 0.72
const ISOLATED_HIGH := 0.88
const ISOLATED_WEIGHT := 0.70

## Offshore gate: 1 well out to sea, 0 on land and on the shelf shoulder.
const OCEAN_INNER := 0.06
const OCEAN_OUTER := -0.10

var _clusters: FastNoiseLite
var _group: FastNoiseLite
var _isolated: FastNoiseLite

var _continents_index := -1


func _init() -> void:
	super(MODULE_ID, OUTPUT_FIELD, PackedStringArray([&"continentalness"]), 1)


func configure(context: GenerationContext) -> void:
	var config := context.config
	var base := config.archipelago_frequency
	_continents_index = dependency_index(&"continentalness")
	_clusters = context.make_noise_stream(MODULE_ID, version, 1, base, 2)
	# Three octaves give groups islands of mixed size instead of one uniform size.
	_group = context.make_noise_stream(MODULE_ID, version, 2, base * 5.0, 3)
	_isolated = context.make_noise_stream(MODULE_ID, version, 3, base * 14.0, 2)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var continents := values[_continents_index]

	var ocean := smoothstep(OCEAN_INNER, OCEAN_OUTER, continents)
	if ocean <= 0.0:
		values[get_output_index()] = 0.0
		return

	var clusters := smoothstep(
			CLUSTER_LOW, CLUSTER_HIGH, _unit(_clusters.get_noise_2d(x, z))
	)
	var grouped := smoothstep(GROUP_LOW, GROUP_HIGH, _unit(_group.get_noise_2d(x, z)))
	var lone := smoothstep(
			ISOLATED_LOW, ISOLATED_HIGH, _unit(_isolated.get_noise_2d(x, z))
	) * ISOLATED_WEIGHT

	values[get_output_index()] = maxf(grouped * clusters, lone) * ocean


static func _unit(noise_value: float) -> float:
	return clampf(noise_value * 0.5 + 0.5, 0.0, 1.0)
