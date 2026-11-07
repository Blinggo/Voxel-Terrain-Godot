class_name GenerationContext
extends RefCounted

## Everything a generation module is allowed to depend on.
##
## A module must not read globals, singletons, the clock, or a shared RNG. It
## receives this context once, at build time, and stores what it needs. That is
## what makes generation reproducible: the only inputs are the world seed, the
## module's identity, and the frozen configuration snapshot.
##
## [b]Configuration snapshot.[/b] [member config] is a [method
## WorldConfig.duplicate_config] copy taken when the world was built. Editing the
## inspector resource afterwards cannot change generation that is already in
## flight, and a module holding a reference to this context cannot observe a
## half-applied edit.
##
## [b]Independent streams.[/b] [method module_seed] mixes the world seed with the
## module identifier, so two modules never share a noise stream even though they
## start from the same world seed. This is what lets a module be added, removed
## or re-tuned without shifting the terrain of unrelated modules.

## World seed. The only user-facing source of variation.
var seed: int

## Version of the whole generation pipeline. Bumping it deliberately reshuffles
## every module at once, which is how a breaking algorithm change is signalled.
var generation_version: int

## Frozen copy of the world configuration. Treat as read-only.
var config: WorldConfig

var _keys: Dictionary = {}


func _init(
		world_seed: int,
		p_generation_version: int,
		config_snapshot: WorldConfig
) -> void:
	assert(config_snapshot != null, "GenerationContext requires a configuration snapshot.")
	seed = world_seed
	generation_version = p_generation_version
	config = config_snapshot


## 32-bit key for a module identifier, cached because it is requested per build
## rather than per sample.
func module_key(module_id: StringName) -> int:
	var existing: Variant = _keys.get(module_id)
	if existing != null:
		return int(existing)
	var key := TerrainHash.hash_string(String(module_id))
	_keys[module_id] = key
	return key


## Noise seed for one module instance.
##
## Mixes the world seed with both versions, so two modules never share a stream,
## a module's own version bump reshuffles only that module, and a bump of the
## pipeline's version reshuffles everything at once.
func module_seed(module_id: StringName, module_version: int) -> int:
	return TerrainHash.module_seed(
			seed, module_key(module_id), module_version, generation_version
	)


## Builds a configured [FastNoiseLite] for a module.
##
## Centralised so every module gets identical fractal settings and so noise
## creation cannot accidentally pick up unseeded engine defaults.
func make_noise(
		module_id: StringName,
		module_version: int,
		frequency: float,
		octaves: int,
		noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		fractal_type: FastNoiseLite.FractalType = FastNoiseLite.FRACTAL_FBM
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = noise_type
	noise.seed = module_seed(module_id, module_version)
	noise.frequency = frequency
	noise.fractal_type = fractal_type if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = maxi(octaves, 1)
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise


## Convenience: same as [method make_noise] but with an explicit sub-stream
## index, for modules that need several independent noises of their own (for
## example a domain warp field next to the field it warps).
func make_noise_stream(
		module_id: StringName,
		module_version: int,
		stream: int,
		frequency: float,
		octaves: int,
		noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH,
		fractal_type: FastNoiseLite.FractalType = FastNoiseLite.FRACTAL_FBM
) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = noise_type
	noise.seed = TerrainHash.module_seed(
			seed, module_key(module_id), module_version * 131 + stream, generation_version
	)
	noise.frequency = frequency
	noise.fractal_type = fractal_type if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = maxi(octaves, 1)
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	return noise
