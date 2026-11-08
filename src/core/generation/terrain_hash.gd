class_name TerrainHash
extends RefCounted

## Deterministic coordinate hashing for the generation modules.
##
## [b]Why not [RandomNumberGenerator].[/b] A generator object carries mutable
## state, so its values depend on how many numbers were drawn before - which
## depends on which chunk was generated first, on thread scheduling, and on
## nothing the world seed controls. Hashing gives the opposite property: the
## value for a coordinate is a pure function of the inputs, so it cannot depend
## on generation order, on neighbouring chunks, or on threads.
##
## [b]What goes in.[/b] Every hash mixes:
## - the world seed (split into two 32-bit halves, so 64-bit seeds do not alias);
## - a [i]module key[/i] - a 32-bit hash of the module's identifier string, which
##   gives each module an independent stream from the same seed;
## - the module's version and the world's generation version, so bumping either
##   deliberately reshuffles;
## - the absolute coordinates, split the same way as the seed.
##
## [b]Why 32-bit mixing.[/b] GDScript integers are 64-bit and wrap on overflow,
## but literals at or above 2^63 cannot be written and right-shifting a negative
## value is a parse error. Staying inside 32-bit unsigned lanes avoids both
## problems entirely, and keeps every intermediate value positive so shifts are
## well defined.
##
## [b]Determinism scope.[/b] Integer arithmetic and this mixing are exactly
## reproducible. The guarantees and their limits are documented in
## `Documentation/Milestones/M01_DETERMINISTIC_TERRAIN_FOUNDATION.md`.

const U32 := 0xFFFFFFFF
const TWO32 := 0x100000000

const FNV_OFFSET_BASIS := 0x811C9DC5
const FNV_PRIME := 0x01000193

## MurmurHash3 finaliser constants.
const MIX_1 := 0x85EBCA6B
const MIX_2 := 0xC2B2AE35


## 32-bit FNV-1a over the UTF-8 bytes of [param text].
##
## Used for module identifiers, so that a module's random stream is tied to its
## name: renaming a module changes its terrain, which is intended and is why
## names are part of the generation version contract.
static func hash_string(text: String) -> int:
	var h := FNV_OFFSET_BASIS
	for byte in text.to_utf8_buffer():
		h = ((h ^ byte) * FNV_PRIME) & U32
	return h


## MurmurHash3 fmix32. Avalanches the low bits so that adjacent coordinates do
## not produce correlated values.
static func mix(value: int) -> int:
	var h := value & U32
	h = h ^ (h >> 16)
	h = (h * MIX_1) & U32
	h = h ^ (h >> 13)
	h = (h * MIX_2) & U32
	h = h ^ (h >> 16)
	return h & U32


## Folds a 64-bit integer into the hash, low word first.
##
## The high word is recovered by integer division rather than shifting, because
## shifting a negative value is not allowed. `value & U32` is the exact low 32
## bits even for negative values, and `(value - low) / 2^32` is exact integer
## division, so the pair reconstructs [param value] exactly for the whole range.
static func fold_int(h: int, value: int) -> int:
	var low := value & U32
	var high := (value - low) / TWO32
	h = mix(h ^ low)
	h = mix(h ^ (high & U32))
	return h


## 32-bit hash of a coordinate for one module stream.
##
## [param module_key] comes from [method hash_string]; [param generation_version]
## and the module's own version are folded in so that changing an algorithm
## produces a genuinely different world instead of a subtly different one.
static func hash_coords(
		seed: int,
		module_key: int,
		generation_version: int,
		x: int,
		z: int
) -> int:
	var h := FNV_OFFSET_BASIS
	h = fold_int(h, seed)
	h = mix(h ^ (module_key & U32))
	h = fold_int(h, generation_version)
	h = fold_int(h, x)
	h = fold_int(h, z)
	return h


## A value in [0, 1) from an already-computed hash.
##
## For callers that hold a 32-bit hash and want several independent-looking
## numbers from it. A single [method hash_coords] call mixes the whole seed,
## module and coordinate set, so splitting one hash is the cheapest way to get
## the two jitter components of a feature point: there is no need to pay for a
## second mixing pass just to place a point.
static func unit_from_hash(h: int) -> float:
	return float(h & U32) / 4294967296.0


## A coarse value in [0, 1) taken from one byte-aligned slice of a hash,
## [param slice] 0..3.
##
## Used for the small integer choices a regional feature needs (which of three
## boundary kinds, which of several height bands). Whole bytes, so the slices are
## independent for the same cost as one slice.
static func unit_slice(h: int, slice_index: int) -> float:
	var shift := (slice_index & 3) * 8
	return float((h >> shift) & 0xFF) / 256.0


## Order-independent mix of two hashes.
##
## A boundary between two regions must be described identically from either
## side, so this must not depend on argument order: callers pass the hashes in
## whatever order they discovered them, and both sides get the same character
## for the shared edge.
static func combine_pair(a: int, b: int) -> int:
	var low := mini(a & U32, b & U32)
	var high := maxi(a & U32, b & U32)
	return mix(low ^ mix(high))


## Convenience: a value in [0, 1) at a coordinate, for one module stream.
static func unit_at(
		seed: int,
		module_key: int,
		generation_version: int,
		x: int,
		z: int
) -> float:
	var h := hash_coords(seed, module_key, generation_version, x, z)
	return float(h) / 4294967296.0


## A 32-bit seed suitable for a noise generator, derived from the world seed, a
## module identifier, the module's own version and the pipeline's generation
## version. Two modules never share a noise stream, and bumping either version
## deliberately reshuffles.
static func module_seed(
		seed: int,
		module_key: int,
		module_version: int,
		generation_version: int = 0
) -> int:
	var h := FNV_OFFSET_BASIS
	h = fold_int(h, seed)
	h = mix(h ^ (module_key & U32))
	h = fold_int(h, module_version)
	h = fold_int(h, generation_version)
	return h & U32
