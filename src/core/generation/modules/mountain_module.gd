class_name MountainModule
extends GenerationModule

## Where mountains are, and how high - as connected range systems rather than as a
## layer of ridged noise.
##
## Output: [code]0.0 .. 1.0[/code]. 0 is flatland, 1 is the crest of a high range.
##
## [b]What M1 did and what was wrong with it.[/b] M1 multiplied one ridged fractal
## by a belt mask and an inland gate. That produced mountain-shaped [i]texture[/i]
## but not mountain [i]systems[/i]: because the only structure was the noise lattice,
## crests ran in every direction at once, ranges had no length or spine, and the
## height of a range was whatever the fractal happened to produce locally. It was
## one layer of ridged noise with two multipliers, which is exactly what M2 rules
## out.
##
## [b]How the range structure is built now.[/b] Four components with different jobs,
## combined in a fixed order:
## [codeblock]
## spine      long-wavelength ridged field, domain-warped   -> where ranges run
## secondary  higher-frequency ridged field                 -> ribs off the spine
## apron      the low tail of the spine, widened            -> foothills
## belts      very low frequency field                      -> province spread
## [/codeblock]
## The [i]spine[/i] is ridged noise at a wavelength of roughly 170 voxels, warped by
## a second noise so its crests bend instead of following the noise lattice. Ridged
## noise produces crests along continuous lines, and at this wavelength those lines
## are long enough to read as a primary ridge. The [i]secondary[/i] field is the same
## construction at about three times the frequency, weighted by how far up the
## primary ridge the point already is, so ribs grow on the flanks of a primary range
## and do not invent ranges of their own. The [i]apron[/i] takes the low tail of the
## spine - before it is sharpened into a crest - and spreads it sideways, which is
## what gives a range a foothill transition instead of a wall; this is the term that
## makes the silhouette irregular. The [i]belts[/i] field is the M1 multi-scale
## variation idea, kept because it spaces whole mountain provinces apart.
##
## [b]Connections between ranges.[/b] Two ranges are connected when their spines
## meet, and spines meet where the low-frequency belt field is high: the belt mask
## damps a range rather than cutting it, so a damped stretch becomes a saddle
## between two ranges instead of two ranges with a gap. Combined with the apron,
## which never drops fully to zero across a belt, the result is a continuous system
## with high massifs and lower connecting ridges.
##
## [b]Tectonics.[/b] [member TectonicsModule] supplies where uplift is strong. It
## gates the field (a convergent boundary raises the ceiling on how mountainous a
## region may become) rather than generating the shape, and the gate has a floor:
## with [constant TECTONIC_FLOOR] at 0.22, a belt outside any strong boundary still
## produces low mountains. Belt noise alone would leave the tectonic field
## decorative; tectonics alone would give straight-edged ranges along a Voronoi
## bisector, which looks worse than noise. The product of the two is what produces
## ranges that follow a plausible structural line but are not obviously geometric.
##
## [b]Height variation between ranges.[/b] A separate very low frequency field
## scales the whole result, so one range is a line of low hills and the next is a
## high massif within the same world.
##
## [b]Cost.[/b] Six noise lookups per node and no allocations. This module inherits
## the engine's node grid, so it is evaluated once per eight voxels, not per voxel.

const MODULE_ID := &"mountainness"
const OUTPUT_FIELD := &"mountainness"

## Primary ridge: below LOW a node is not on a range, above HIGH it is on the
## crest. Sharpened rather than spread, so the crest line is narrow and the flanks
## fall away from it.
const SPINE_LOW := 0.36
const SPINE_HIGH := 0.84

## Secondary ridges. They are weighted by spine height, so they appear on flanks.
const SECONDARY_LOW := 0.44
const SECONDARY_HIGH := 0.90
const SECONDARY_WEIGHT := 0.38
## Secondary amplitude at the foot of a primary range, so ribs also exist in the
## trough between two spines - that is what connects adjacent ranges.
const SECONDARY_BASE := 0.40

## Foothills: the unsharpened spine tail, widened.
const APRON_LOW := 0.06
const APRON_HIGH := 0.60
const APRON_WEIGHT := 0.26

## Mountain provinces: the noise-driven massifs, away from any plate boundary.
const BELT_LOW := 0.30
const BELT_HIGH := 0.78

## Structural uplift band along a convergent boundary. Below LOW there is no
## structural range, above HIGH the band is at full strength.
const TECTONIC_LOW := 0.02
const TECTONIC_HIGH := 0.55

## Height of a structural band relative to a crest of the spine field. A band is
## raised along its whole length, which is what makes a range continuous; the
## ridge field then varies the height within it.
const BAND_BASE := 0.42

## How much a rift (negative tectonic influence) suppresses a massif. A belt that
## runs across a rift loses its mountains there, which is what stops a range from
## crossing its own rift valley.
const RIFT_SUPPRESSION := 0.55

## Range-to-range height variation.
const VARIATION_LOW := 0.42
const VARIATION_HIGH := 1.0

## Domain warp of the spine, in world units. Large enough to bend a crest line
## visibly, small enough that a range stays where the belt put it.
const WARP_AMPLITUDE := 120.0

var _spine: FastNoiseLite
var _warp: FastNoiseLite
var _secondary: FastNoiseLite
var _belts: FastNoiseLite
var _variation: FastNoiseLite

var _landmass_index := -1
var _tectonics_index := -1


func _init() -> void:
	super(
			MODULE_ID,
			OUTPUT_FIELD,
			PackedStringArray([&"landmass", &"tectonics"]),
			2
	)


func configure(context: GenerationContext) -> void:
	var config := context.config
	var base := config.mountain_frequency
	_landmass_index = dependency_index(&"landmass")
	_tectonics_index = dependency_index(&"tectonics")

	_spine = context.make_noise_stream(
			MODULE_ID,
			version,
			1,
			base,
			3,
			FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			FastNoiseLite.FRACTAL_RIDGED
	)
	_warp = context.make_noise_stream(MODULE_ID, version, 2, base * 1.3, 2)
	_secondary = context.make_noise_stream(
			MODULE_ID,
			version,
			3,
			base * 3.2,
			2,
			FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
			FastNoiseLite.FRACTAL_RIDGED
	)
	_belts = context.make_noise_stream(MODULE_ID, version, 4, base * 0.32, 2)
	_variation = context.make_noise_stream(MODULE_ID, version, 5, base * 0.16, 2)


func evaluate_node(x: int, z: int, values: PackedFloat32Array) -> void:
	var land := values[_landmass_index]
	var tectonic := values[_tectonics_index]

	# Warped lookup coordinates. Two offsets of one noise give the two components,
	# which is cheaper than a second generator and just as independent.
	var warp_x := _warp.get_noise_2d(x + 3711, z) * WARP_AMPLITUDE
	var warp_z := _warp.get_noise_2d(x, z + 7331) * WARP_AMPLITUDE
	var wx := x + warp_x
	var wz := z + warp_z

	var raw_spine := clampf(_spine.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	var spine := smoothstep(SPINE_LOW, SPINE_HIGH, raw_spine)

	var ribs := smoothstep(
			SECONDARY_LOW,
			SECONDARY_HIGH,
			clampf(_secondary.get_noise_2d(wx, wz) * 0.5 + 0.5, 0.0, 1.0)
	)
	var secondary := ribs * SECONDARY_WEIGHT * (SECONDARY_BASE + (1.0 - SECONDARY_BASE) * spine)

	var ridge := maxf(spine, secondary)
	var apron := smoothstep(APRON_LOW, APRON_HIGH, raw_spine) * APRON_WEIGHT

	# Two ways a range happens.
	#
	# A [i]structural[/i] range follows a convergent plate boundary. The band is
	# the band of tectonic uplift, so it is long and narrow by construction: the
	# uplift field decays with distance from a boundary, and a boundary is a line.
	# That is what gives a range a spine and a length instead of a blob shape, and
	# BAND_BASE raises the whole band rather than only its crests, so the range is
	# continuous along its length with the ridge field varying its height.
	#
	# A [i]massif[/i] is a noise-driven province away from any boundary, taken from
	# the squared belt field so massifs are rarer and their edges are soft.
	var band := smoothstep(TECTONIC_LOW, TECTONIC_HIGH, tectonic)
	var structural := band * (BAND_BASE + (1.0 - BAND_BASE) * ridge)
	var belt := smoothstep(
			BELT_LOW, BELT_HIGH, clampf(_belts.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	)
	var massif := belt * belt * ridge

	var relief := maxf(maxf(structural, massif), apron * (0.35 + 0.65 * belt))

	# Gates: on land, inland, and not cut by a rift.
	#
	# A low inland floor on purpose: an island whose land signal only reaches 0.15
	# still has hills on it. Gating hard here made every island a flat pancake.
	var inland := smoothstep(-0.04, 0.18, land)
	# A rift cuts through a belt rather than crossing it.
	var province := 1.0 - RIFT_SUPPRESSION * clampf(-tectonic, 0.0, 1.0)

	var variation := lerpf(
			VARIATION_LOW,
			VARIATION_HIGH,
			clampf(_variation.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0)
	)

	values[get_output_index()] = relief * inland * province * variation
