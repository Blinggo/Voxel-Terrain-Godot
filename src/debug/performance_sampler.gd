class_name PerformanceSampler
extends RefCounted

## Lightweight runtime measurements for the debug overlay.
##
## [b]Why a plain object and not a node or a singleton.[/b] ADR-0007 forbids
## autoloads, and profiling must not appear in the scene tree where it could
## affect what it measures. The debug panel owns one of these and feeds it, so
## the whole thing can be removed by deleting the panel.
##
## [b]Separation from generation.[/b] Nothing in `src/core/`, `src/voxel/` or
## `src/world/` knows this class exists. Generation modules can report their own
## timings later through [method record_section] without the panel growing a
## special case per module — that is what the section table is for.
##
## [b]Cost.[/b] [method sample] is a handful of float operations per frame; all
## string formatting happens when [method get_report] is called, which the panel
## does a few times per second, not every frame. When [member enabled] is false
## [method sample] returns immediately and the section table stops growing.

## Length of the rolling window over which frame times are averaged.
const WINDOW_SECONDS := 1.0

## When false, sampling stops and no report is produced.
var enabled := true

var _window_elapsed := 0.0
var _frames := 0
var _frame_ms_total := 0.0
var _frame_ms_max := 0.0

## Last completed window, as produced by [method sample].
var _frame_report := {
	"fps": 0.0,
	"frame_ms_avg": 0.0,
	"frame_ms_max": 0.0,
	"frames": 0,
}

## name -> { "last_ms": float, "max_ms": float, "total_ms": float, "count": int }
var _sections := {}

## Last [method VoxelTerrain.get_statistics] dictionary handed in, unmodified.
var _voxel_statistics := {}


## Call once per frame with the frame delta. Closes a window every
## [constant WINDOW_SECONDS].
func sample(delta: float) -> void:
	if not enabled:
		return

	_window_elapsed += delta
	_frames += 1
	var frame_ms := delta * 1000.0
	_frame_ms_total += frame_ms
	_frame_ms_max = maxf(_frame_ms_max, frame_ms)

	if _window_elapsed >= WINDOW_SECONDS:
		_close_window()


func _close_window() -> void:
	var frames := maxi(_frames, 1)
	_frame_report = {
		"fps": float(_frames) / maxf(_window_elapsed, 0.000001),
		"frame_ms_avg": _frame_ms_total / float(frames),
		"frame_ms_max": _frame_ms_max,
		"frames": _frames,
	}
	_window_elapsed = 0.0
	_frames = 0
	_frame_ms_total = 0.0
	_frame_ms_max = 0.0


## Frames-per-second and frame time for the last completed window.
func get_frame_report() -> Dictionary:
	return _frame_report.duplicate()


## Records one measurement of a named phase, in milliseconds. Repeat calls for
## the same name roll up into average/max, so a caller can time every invocation
## of something and still get a readable summary.
func record_section(section_name: String, elapsed_ms: float) -> void:
	if not enabled:
		return
	var entry: Dictionary = _sections.get(section_name, {
		"last_ms": 0.0, "max_ms": 0.0, "total_ms": 0.0, "count": 0,
	})
	entry["last_ms"] = elapsed_ms
	entry["max_ms"] = maxf(float(entry["max_ms"]), elapsed_ms)
	entry["total_ms"] = float(entry["total_ms"]) + elapsed_ms
	entry["count"] = int(entry["count"]) + 1
	_sections[section_name] = entry


## Last recorded duration of a section, in ms, or 0 when it was never measured.
func get_section_ms(section_name: String) -> float:
	var entry: Dictionary = _sections.get(section_name, {})
	return float(entry.get("last_ms", 0.0))


## Mean duration of a section over every recorded call, in ms.
func get_section_average_ms(section_name: String) -> float:
	var entry: Dictionary = _sections.get(section_name, {})
	var count := int(entry.get("count", 0))
	if count == 0:
		return 0.0
	return float(entry.get("total_ms", 0.0)) / float(count)


func get_sections() -> Dictionary:
	return _sections.duplicate(true)


## Stores the dictionary returned by [method VoxelTerrain.get_statistics].
## The keys are reported as-is; this sampler does not invent any.
func set_voxel_statistics(statistics: Dictionary) -> void:
	_voxel_statistics = statistics.duplicate()


func get_voxel_statistics() -> Dictionary:
	return _voxel_statistics.duplicate()


## Godot-managed memory and object counts.
##
## [b]These are not Android process memory.[/b] They describe what the engine
## accounts for internally (its static allocator and object graph). A device's
## resident set size also contains the Android runtime, the GL/Vulkan driver and
## graphics allocations, and must be read with `adb shell dumpsys meminfo`.
func get_memory_report() -> Dictionary:
	return {
		"static_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"static_max_bytes": Performance.get_monitor(Performance.MEMORY_STATIC_MAX),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"object_node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"object_resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
	}


## Everything at once, for callers that want a single snapshot (tests, logs).
func get_report() -> Dictionary:
	return {
		"frames": get_frame_report(),
		"memory": get_memory_report(),
		"voxel": get_voxel_statistics(),
		"sections": get_sections(),
	}


## Clears accumulated section data. Frame and memory statistics are recomputed
## from scratch on the next window anyway.
func reset() -> void:
	_sections.clear()
	_window_elapsed = 0.0
	_frames = 0
	_frame_ms_total = 0.0
	_frame_ms_max = 0.0
	_frame_report = {"fps": 0.0, "frame_ms_avg": 0.0, "frame_ms_max": 0.0, "frames": 0}
