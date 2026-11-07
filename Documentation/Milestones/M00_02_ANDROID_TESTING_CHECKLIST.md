# M0.2 — Android Manual Testing Checklist

For the project owner to run on the physical device. Everything here is a step
this environment cannot perform.

Two builds can be tested, and they test different things:

| Build | What it establishes |
|---|---|
| **Editor run** (one-click deploy from the Godot editor) | already done, passed — see `M00_02_ANDROID_VALIDATION.md` §7.1 |
| **Release APK** (`artifacts/android/procedural-world-arm64.apk`) | whether the *exported* build works. **Never tested.** Do this one. |

The APK is signed with a throwaway key. If a differently-signed build of
`io.arena.proceduralworld` is already installed, uninstall it first:

```bash
adb uninstall io.arena.proceduralworld
adb install -r artifacts/android/procedural-world-arm64.apk
adb shell am start -n io.arena.proceduralworld/com.godot.game.GodotApp
```

Attach `adb logcat` while testing — Godot prints its startup and any script
errors there:

```bash
adb logcat -c && adb logcat | grep -iE "godot|voxel|error|script"
```

---

## 1. Launch

- [ ] App installs without error.
- [ ] App opens in **landscape** (this changed in M0.2 — it used to be
      portrait-locked, which was a bug).
- [ ] No crash, no black screen, logcat shows Voxel Tools initialising and no
      script errors.
- [ ] After a few seconds the overlay shows `streaming  ready`.

## 2. Terrain generation

- [ ] Blocky terrain fills the view, coloured green/brown/grey with no holes.
- [ ] Surface is continuous — no seams, no floating gaps, no missing chunks.
- [ ] Overlay `seed` shows 1337 and `builds` shows 1 on a fresh start.

## 3. Camera interaction

- [ ] Drag orbits smoothly; frame rate stays usable while moving.
- [ ] Pinch zooms; two-finger or middle drag pans.
- [ ] No stutter when crossing newly streamed terrain.

## 4. Numerical input (all four fields)

For each of **world seed**, **terrain height**, **terrain frequency**,
**view distance**:

- [ ] Tap the field: cursor appears, numeric keyboard opens.
- [ ] Frequency offers a decimal point; the others do not.
- [ ] Type a value, press Done: field shows the value, keyboard closes.
- [ ] Tap Regenerate: the change takes effect (see §5).
- [ ] Empty the field, tap Regenerate: the previous value is restored, no crash.
- [ ] Type letters: rejected, previous value restored.
- [ ] Dismiss the keyboard with the back gesture, tap the same field again: the
      keyboard reopens.
- [ ] `+` / `-` buttons step the value and stop at the limits.

## 5. Regeneration and random seed

- [ ] Edit **terrain height** to 40, Regenerate: the terrain is visibly taller.
- [ ] Edit **terrain frequency** to 0.02, Regenerate: hills become tighter/more
      frequent.
- [ ] Edit **view distance** to 96, then 256: the streamed area shrinks/grows and
      the overlay's `viewer` keeps updating.
- [ ] Press **Random seed**: seed changes to a new number and the terrain differs.
- [ ] Set a seed by hand, note it, regenerate twice: identical terrain each time.
- [ ] Force-stop the app and relaunch: it returns to the configured default seed
      (1337) — not the last typed seed.

## 6. Frame time and memory observations

With the overlay visible (F3 hides/shows the panel, F4 toggles the perf block):

- [ ] Record the `fps` and `frame` lines while standing still.
- [ ] Record them while orbiting continuously, and while flying into unstreamed
      terrain.
- [ ] Note `godot mem` after startup and after several regenerations.
- [ ] Note `voxel` phase timings during streaming versus when idle.
- [ ] Note `rebuild` after pressing Regenerate (main-thread cost only).

Process memory cannot be read from inside the app. From the host:

```bash
adb shell dumpsys meminfo io.arena.proceduralworld | head -25
adb shell top -n 1 | grep -i procedural
```

Record `TOTAL PSS` at startup and at the end of the sustained test. This is the
only number that reflects real device memory — it is not comparable with the
overlay's `godot mem`.

## 7. Sustained runtime (20–30 minutes)

- [ ] Start with a fresh launch and `adb logcat` running.
- [ ] Spend ~10 minutes orbiting and moving continuously so terrain streams
      constantly.
- [ ] Spend ~5 minutes regenerating with different seeds, heights, frequencies
      and view distances (at least 10 regenerations).
- [ ] Spend ~5 minutes parked at a fixed view, checking for drift in `fps`,
      `godot mem`, `dropped` counters and `objects`.
- [ ] Spend the remaining time moving between the two extremes of view distance
      (32 and 512).
- [ ] At the end: record final `fps`, `frame max`, `godot mem`, `objects`,
      `dropped loads / meshes`, and `dumpsys meminfo TOTAL PSS`.
- [ ] Check the device is not uncomfortably hot and note whether the frame rate
      fell as it warmed.

**Fail conditions** — stop and report if any occur:

- crash or ANR;
- visible memory growth that never comes back down after regenerations;
- `dropped loads` / `dropped meshes` growing steadily while idle;
- frame time degrading without recovering;
- terrain holes or seams that persist.

---

## What to send back

1. Device model, Android version, SoC.
2. Which build was tested (APK or Editor) and the APK sha256 if used.
3. The numbers from §6 and §7 (start and end).
4. Anything that failed, with the logcat section around it.
5. Whether landscape orientation and the overlay layout look right on the
   device's screen.
