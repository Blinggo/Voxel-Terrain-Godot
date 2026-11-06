extends Node

## Headless test entry point.
##
## Usage:
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=core
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=voxel
##   godot --headless --path . res://tests/test_runner.tscn -- --suite=all
##   godot --path . res://tests/test_runner.tscn -- --suite=ui   (needs a display)
##
## Exits with status 0 when every check passed, 1 otherwise, so it can be used
## directly in CI.

const TestSupport = preload("res://tests/test_support.gd")
const CoreSuite = preload("res://tests/suites/core_suite.gd")
const VoxelSuite = preload("res://tests/suites/voxel_suite.gd")
const UiInputSuite = preload("res://tests/suites/ui_input_suite.gd")

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
	print(" Procedural World Generator - test run")
	print(" Godot %s" % Engine.get_version_info()["string"])
	print(" Voxel Tools extension loaded: %s" % ClassDB.class_exists("VoxelTerrain"))
	print(" display server: %s" % DisplayServer.get_name())
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

	var ui_was_skipped := false
	if suite == "all" or suite == "ui":
		if DisplayServer.get_name() == "headless":
			# Godot does not deliver GUI input in headless mode, so these checks
			# would pass vacuously. Skip loudly rather than pretending.
			print("")
			print("-- android input fix -------------------------------------")
			print("  SKIP  UI input suite needs a display server (run without --headless)")
			ui_was_skipped = true
		else:
			await UiInputSuite.run(report, get_tree())

	if ui_was_skipped and report.get_check_count() == 0:
		# Nothing ran at all: never print a 0-check "PASS".
		print("")
		print("----------------------------------------------------------")
		print("RESULT: SKIP  (no suite could run without a display server)")
		print("----------------------------------------------------------")
		get_tree().quit(0)
		return

	var exit_code: int = report.summary()
	get_tree().quit(exit_code)
