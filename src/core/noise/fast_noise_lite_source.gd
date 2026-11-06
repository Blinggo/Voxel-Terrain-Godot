class_name FastNoiseLiteSource
extends NoiseSource

## [NoiseSource] backed by Godot's built-in [FastNoiseLite].
##
## The instance is fully configured in [method _init] and only read afterwards,
## which satisfies the thread-safety contract of [NoiseSource]: reading is
## lock-free and cannot corrupt the object. Each instance owns its own
## [FastNoiseLite], so there is no global or shared generator state.

var _noise: FastNoiseLite


func _init(
		world_seed: int,
		frequency: float,
		octaves: int = 4,
		noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
) -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = noise_type
	_noise.seed = world_seed
	_noise.frequency = frequency

	if octaves > 1:
		_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		_noise.fractal_octaves = octaves
		_noise.fractal_lacunarity = 2.0
		_noise.fractal_gain = 0.5
	else:
		_noise.fractal_type = FastNoiseLite.FRACTAL_NONE


func sample_2d(x: float, y: float) -> float:
	return _noise.get_noise_2d(x, y)
