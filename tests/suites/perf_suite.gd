extends RefCounted

## Performance instrumentation suite.
##
## Two things are being checked here. First, that the sampler's arithmetic is
## right - a wrong average or a max that only ever reports the last frame would
## quietly mislead anyone reading the overlay. Second, that the overlay reports
## only measurements that actually exist, rather than a schema someone hoped
## Voxel Tools had.
##
## Runs headless: no display or input injection is involved.

const TestSupport = preload("res://tests/test_support.gd")

const MAIN_SCENE_PATH := "res://scenes/main.tscn"

## Keys Voxel Tools 1.7x really returns from VoxelTerrain.get_statistics().
## Verified against the installed extension before being written down here.
const REAL_VOXEL_KEYS: Array[String] = [
	"dropped_block_loads",
	"dropped_block_meshs",
	"time_detect_required_blocks",
	"time_process_load_responses",
	"time_request_blocks_to_load",
	"time_request_blocks_to_update",
	"updated_blocks",
]

var _report
var _tree: SceneTree


static func run(report, tree: SceneTree) -> void:
	var suite := new()
	suite._report = report
	suite._tree = tree

	print("")
	print("-- performance instrumentation ---------------------------")
	await tree.process_frame

	suite._test_frame_statistics()
	suite._test_frame_maximum()
	suite._test_disabled_sampler_does_nothing()
	suite._test_sections()
	suite._test_memory_report()
	suite._test_voxel_statistics_passthrough()
	suite._test_extension_statistics_schema()
	await suite._test_panel_readout()


# ---------------------------------------------------------------------- checks

func _test_frame_statistics() -> void:
	var sampler := PerformanceSampler.new()

	# 110 frames of 10 ms: the window closes at 1 s, so the report describes the
	# first 100 frames and leaves 10 in the open window.
	for _i in range(110):
		sampler.sample(0.01)

	var frames: Dictionary = sampler.get_frame_report()
	var fps := float(frames["fps"])
	_report.check("fps is derived from the window", fps > 95.0 and fps < 105.0, "fps=%.2f" % fps)
	_report.check("average frame time is 10 ms",
			absf(float(frames["frame_ms_avg"]) - 10.0) < 0.01,
			"avg=%.3f" % float(frames["frame_ms_avg"]))
	_report.check_equal("the window counted 100 frames", int(frames["frames"]), 100)

	# A second window must reset rather than accumulate.
	for _i in range(110):
		sampler.sample(0.02)
	var second: Dictionary = sampler.get_frame_report()
	_report.check("a new window replaces the previous report",
			absf(float(second["frame_ms_avg"]) - 20.0) < 0.01,
			"avg=%.3f" % float(second["frame_ms_avg"]))


func _test_frame_maximum() -> void:
	var sampler := PerformanceSampler.new()
	for _i in range(99):
		sampler.sample(0.01)
	sampler.sample(0.05)   # one slow frame inside the same window
	sampler.sample(0.01)

	var frames: Dictionary = sampler.get_frame_report()
	_report.check("the slowest frame is reported as the maximum",
			absf(float(frames["frame_ms_max"]) - 50.0) < 0.5,
			"max=%.2f" % float(frames["frame_ms_max"]))
	_report.check("the maximum is larger than the average",
			float(frames["frame_ms_max"]) > float(frames["frame_ms_avg"]))


func _test_disabled_sampler_does_nothing() -> void:
	var sampler := PerformanceSampler.new()
	sampler.enabled = false
	for _i in range(110):
		sampler.sample(0.01)
	sampler.record_section("rebuild", 12.0)

	var frames: Dictionary = sampler.get_frame_report()
	_report.check_equal("a disabled sampler reports no frames", int(frames["frames"]), 0)
	_report.check_equal("a disabled sampler records no sections",
			sampler.get_sections().size(), 0)

	sampler.enabled = true
	for _i in range(110):
		sampler.sample(0.01)
	_report.check("re-enabling resumes sampling", int(sampler.get_frame_report()["frames"]) == 100)


func _test_sections() -> void:
	var sampler := PerformanceSampler.new()
	sampler.record_section("rebuild", 10.0)
	sampler.record_section("rebuild", 30.0)
	sampler.record_section("rebuild", 20.0)

	_report.check_equal("the last section duration is reported", sampler.get_section_ms("rebuild"), 20.0)
	_report.check("the section average is the mean of every call",
			absf(sampler.get_section_average_ms("rebuild") - 20.0) < 0.001,
			"avg=%.3f" % sampler.get_section_average_ms("rebuild"))
	_report.check_equal("an unmeasured section reads zero",
			sampler.get_section_ms("never-recorded"), 0.0)


func _test_memory_report() -> void:
	var sampler := PerformanceSampler.new()
	var memory: Dictionary = sampler.get_memory_report()

	for key in ["static_bytes", "static_max_bytes", "object_count", "object_node_count",
			"object_resource_count"]:
		_report.check("memory report exposes %s" % key, memory.has(key))
	_report.check("Godot static memory is non-zero in a live process",
			float(memory["static_bytes"]) > 0.0,
			"%.1f MB" % (float(memory["static_bytes"]) / 1048576.0))
	_report.check("object count is non-zero", int(memory["object_count"]) > 0)
	_report.check("static memory peak is at least the current value",
			float(memory["static_max_bytes"]) >= float(memory["static_bytes"]))


func _test_voxel_statistics_passthrough() -> void:
	var sampler := PerformanceSampler.new()
	var fake := {"time_request_blocks_to_update": 1234, "dropped_block_loads": 2}
	sampler.set_voxel_statistics(fake)

	var stored: Dictionary = sampler.get_voxel_statistics()
	_report.check_equal("voxel statistics are stored unchanged", stored, fake)

	# get_voxel_statistics() hands out a copy, so a caller editing it cannot
	# corrupt what the overlay reports next frame.
	stored["extra"] = 1
	_report.check("a caller editing its copy does not affect the sampler",
			not sampler.get_voxel_statistics().has("extra"))


func _test_extension_statistics_schema() -> void:
	# Guards against the overlay displaying keys that do not exist. If a future
	# Voxel Tools release renames them, this check is what fails loudly.
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	_tree.root.add_child.call_deferred(scene)
	await _wait_frames(3)

	var world: VoxelWorld = scene.get_node("World")
	var terrain := world.get_terrain()
	_report.check("the terrain exists for the statistics check", terrain != null)
	if terrain != null:
		var statistics: Dictionary = terrain.get_statistics()
		for key in REAL_VOXEL_KEYS:
			_report.check("VoxelTerrain.get_statistics() still provides %s" % key,
					statistics.has(key),
					"keys=%s" % str(statistics.keys()))
	scene.queue_free()
	await _wait_frames(2)


func _test_panel_readout() -> void:
	var scene: Node = load(MAIN_SCENE_PATH).instantiate()
	_tree.root.add_child.call_deferred(scene)
	await _wait_frames(3)

	var panel: DebugPanel = scene.get_node("DebugLayer/DebugPanel")
	_report.check("profiling is enabled by default", panel.is_profiling_enabled())

	# MainScene refreshes the overlay every 0.25 s of engine time, which under
	# headless (thousands of frames per second) is many frames later. Wait for
	# the refresh instead of guessing a frame count.
	var label: Label = panel.get_node("%PerformanceLabel")
	_report.check("the performance label exists", label != null)
	var refreshed: bool = await _wait_for_text(label, "fps")
	_report.check("the overlay refreshes the readout on its own", refreshed, label.text)
	_report.check("the readout shows fps", "fps" in label.text, label.text.replace("\n", " | "))
	_report.check("the readout shows Godot memory", "godot mem" in label.text)
	_report.check("the readout names the best-effort voxel timings", "voxel" in label.text)

	var report: Dictionary = panel.get_performance_report()
	_report.check("the panel report has frame, memory, voxel and section parts",
			report.has("frames") and report.has("memory") and report.has("voxel")
			and report.has("sections"))

	var voxel: Dictionary = report["voxel"]
	var all_real := true
	for key in voxel.keys():
		if not REAL_VOXEL_KEYS.has(key):
			all_real = false
	_report.check("the readout only reports statistics the extension actually provides",
			all_real, "keys=%s" % str(voxel.keys()))

	# Disabling must stop sampling, not merely hide the text.
	panel.set_profiling_enabled(false)
	_report.check("the label is hidden when profiling is off",
			not label.visible or label.text == "")
	var frames_before := int(panel.get_performance_report()["frames"].get("frames", 0))
	await _wait_frames(5)
	var frames_after := int(panel.get_performance_report()["frames"].get("frames", 0))
	_report.check_equal("no frames are counted while profiling is disabled",
			frames_after, frames_before)

	panel.set_profiling_enabled(true)
	await _wait_frames(3)
	_report.check("profiling can be turned back on", panel.is_profiling_enabled())

	scene.queue_free()
	await _wait_frames(2)


## Waits (bounded, in wall-clock terms) until the label contains [param needle].
func _wait_for_text(label: Label, needle: String) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if needle in label.text:
			return true
		await _tree.process_frame
	return false


func _wait_frames(count: int) -> void:
	for _i in range(count):
		await _tree.process_frame
