# ADR-0006 — Ship only the extension binaries for the target platforms

**Status:** Accepted
**Date:** 2026-11-06

## Context

The upstream `GodotVoxelExtension.zip` ships native libraries for macOS, iOS,
Linux (x86_64 and arm64), Windows (x86_64) and Android (arm64 and x86_64), about
129 MB in total. The repository snapshot budget and the project's actual targets
are both much smaller.

## Decision

Keep only the platforms this project targets, and record exactly what was
removed:

| Kept | Purpose |
|---|---|
| `libvoxel.linux.editor.x86_64.so` / `.template_release.x86_64.so` | development + CI on this machine |
| `libvoxel.windows.editor.x86_64.dll` / `.template_release.x86_64.dll` | secondary target |
| `libvoxel.android.editor.arm64.so` / `.template_release.arm64.so` | primary target |

Removed: macOS universal (editor + template), iOS arm64 (editor + template),
Linux arm64, Android x86_64, and two 4 KB Windows import stub `.a` files.
Total on disk drops from 129 MB to 58 MB.

`voxel.gdextension` itself is **unmodified**. It still declares the removed
platforms; Godot only loads the entry matching the running platform, so the
missing files are inert.

## Consequences

- Building for macOS, iOS, Linux-arm64 or an Android x86_64 emulator will fail
  until those libraries are restored. Restoring them is unzipping the original
  release archive over `addons/zylann.voxel/bin/`; no code change is needed.
- Upgrading the extension means re-applying this trim; the platform list is
  stated above and in the foundation document.
