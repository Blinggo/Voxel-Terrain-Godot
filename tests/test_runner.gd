extends Node

## Headless test entry point.
##
## Usage:
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=core
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=voxel
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=all
##
## Exits with status 0 when every check passed, 1 otherwise, so it can be used
## directly in CI.

const TestSupport = preload("res://tests/test_support.gd")
const CoreSuite = preload("res://tests/suites/core_suite.gd")
const VoxelSuite = preload("res://tests/suites/voxel_suite.gd")

## Hard stop so a broken streaming wait cannot hang a CI job.
const MAX_RUNTIME_SECONDS := 150.0

var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > MAX_RUNTIME_SECONDS:
		push_error("Test run exceeded its watchdog timeout of %.0f s." % MAX_RUNTIME_SECONDS)
		get_tree().quit(2)


func _ready() -> void:
	var suite := "all"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="):
			suite = arg.get_slice("=", 1)

	print("")
	print("==========================================================")
	print(" Procedural World Generator - M0.1 test run")
	print(" Godot %s" % Engine.get_version_info()["string"])
	print(" Voxel Tools extension loaded: %s" % ClassDB.class_exists("VoxelTerrain"))
	print(" suite: %s" % suite)
	print("==========================================================")

	var report := TestSupport.new()

	if suite == "all" or suite == "core":
		print("")
		print("-- core generation ---------------------------------------")
		CoreSuite.run(report)

	if suite == "all" or suite == "voxel":
		print("")
		print("-- voxel integration -------------------------------------")
		await VoxelSuite.run(report, get_tree())

	var exit_code: int = report.summary()
	get_tree().quit(exit_code)
