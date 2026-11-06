#!/usr/bin/env bash
#
# Runs the M0.1 test suites.
#
#   ./tests/run_tests.sh              # headless suites (core + voxel integration)
#   ./tests/run_tests.sh --screenshot # also render a PNG proof of the terrain
#
# Override the engine binary with GODOT=/path/to/godot.
#
# The headless suites are fully self-checking and exit non-zero on failure.
# The screenshot step needs a real rendering device: on a headless machine run
# it under Xvfb (`xvfb-run -s "-screen 0 1280x720x24" ./tests/run_tests.sh --screenshot`).

set -uo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOT_DIR="${SHOT_DIR:-/tmp/voxel_screenshots}"
FAILURES=0

run_suite() {
	local suite="$1"
	echo ""
	echo "##########################################################"
	echo "# suite: ${suite}"
	echo "##########################################################"
	"${GODOT}" --headless --path "${PROJECT_DIR}" res://tests/test_runner.tscn -- "--suite=${suite}"
	local status=$?
	if [[ ${status} -ne 0 ]]; then
		echo "suite '${suite}' FAILED (exit ${status})"
		FAILURES=$((FAILURES + 1))
	fi
	return 0
}

run_suite core
run_suite voxel

if [[ "${1:-}" == "--screenshot" ]]; then
	mkdir -p "${SHOT_DIR}"
	for seed in 1337 90210; do
		echo ""
		echo "### screenshot, seed ${seed}"
		"${GODOT}" --path "${PROJECT_DIR}" res://tests/capture_screenshot.tscn -- \
			"--out=${SHOT_DIR}/terrain_seed_${seed}.png" --warmup=12 --seed="${seed}" \
			--distance=100 --pitch=-28 --yaw=35
	done
	echo "screenshots written to ${SHOT_DIR}"
fi

echo ""
echo "##########################################################"
if [[ ${FAILURES} -eq 0 ]]; then
	echo "# ALL SUITES PASSED"
else
	echo "# ${FAILURES} SUITE(S) FAILED"
fi
echo "##########################################################"
exit "${FAILURES}"
