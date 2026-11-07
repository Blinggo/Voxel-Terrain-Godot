# ADR-0012 — Deterministic hashing in 32-bit lanes, hand-written

**Status:** Accepted
**Date:** 2026-11-07

## Context

Every module needs randomness that is (a) reproducible from the world seed, (b)
independent per module, (c) independent of generation order and thread
scheduling, and (d) stable across engine versions. M1 also had to answer a
practical question first: what integer arithmetic can GDScript actually do?

Measured limits (probed, not assumed):

- hex literals at or above 2^63 are a **parse error**
  (`Cannot represent 0x9E3779B97F4A7C15 as a 64-bit signed integer`), which rules
  out SplitMix64 and FNV-64 constants written as literals;
- `>>` on a **negative** left operand is a parse error;
- 64-bit multiplication wraps silently and deterministically.

## Decision

`TerrainHash` is hand-written, on FNV-1a + MurmurHash3 `fmix32`, staying inside
**32-bit unsigned lanes**:

```
key    = fnv1a_32(module_id_utf8)
h      = fnv1a_32
h      = mix(h ^ low32(seed));   h = mix(h ^ high32(seed))
h      = mix(h ^ key)
h      = mix(h ^ module_version); h = mix(h ^ generation_version)
h      = mix(h ^ low32(x));  h = mix(h ^ high32(x))
h      = mix(h ^ low32(z));  h = mix(h ^ high32(z))
```

Every masked intermediate is a positive 32-bit value, so `>>` is always legal;
each product is bounded by 2^64 and masked immediately, so wrap-around is
well-defined. The 64-bit split is exact for negative values:

```
low  = v & 0xFFFFFFFF              # exact low word, negative values included
high = (v - low) / 0x100000000     # exact integer division, truncation is safe here
```

Godot's built-in `hash()` was rejected: it is not documented as stable across
engine versions, and a world that silently changes when the engine is upgraded is
worse than one that fails to build.

The generation version and the module version are folded in for the same reason:
a change that alters output must alter the stream, otherwise terrain would change
subtly without a witness.

## Consequences

- 32 bits of output space per stream. With ≤ 6 modules × 4 versions in use that
  is far below collision pressure; a birthday collision would need ~2^16 streams
  to become likely. Distinctness of the *six* module seeds is asserted in tests.
- Module ids are part of the determinism contract: renaming a module changes its
  terrain. This is intentional and documented in the class.
- A bug during development proved the value of the test: `generation_version` was
  stored but not folded in, so bumping it changed nothing. The test caught it
  (0 % of columns differed) and the mix was fixed.
- Cross-platform bit-identity of the *floats* downstream is still not claimed;
  hashing is integer-exact, noise is float32.
