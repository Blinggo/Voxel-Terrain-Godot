#!/usr/bin/env bash
#
# Runs the test suites.
#
#   ./tests/run_tests.sh              # core + voxel, plus UI input if a display exists
#   ./tests/run_tests.sh --screenshot # also render a PNG proof of the terrain
#
# Override the engine binary with GODOT=/path/to/godot.
#
# The suites are fully self-checking and exit non-zero on failure.
#
# Godot does not deliver GUI input in --headless mode, so the UI input suite
# (M0.2) only proves anything when a display is reachable. When DISPLAY is set
# the suites run windowed so those checks execute; otherwise they run headless
# and the UI suite is reported as SKIPPED. On a machine with no display:
#   xvfb-run -s "-screen 0 1280x720x24" ./tests/run_tests.sh
# The --screenshot step always needs a rendering device for the same reason.

set -uo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOT_DIR="${SHOT_DIR:-/tmp/voxel_screenshots}"
FAILURES=0
SKIPPED=0

# GUI input needs a real viewport; pick the mode from the environment.
if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
	SUITE_FLAGS=()
	MODE="windowed (display: ${DISPLAY:-${WAYLAND_DISPLAY:-}})"
else
	SUITE_FLAGS=(--headless)
	MODE="headless (UI input suite will be skipped)"
fi

run_suite() {
	local suite="$1"
	echo ""
	echo "##########################################################"
	echo "# suite: ${suite}"
	echo "##########################################################"
	local log
	log="$(mktemp)"
	"${GODOT}" "${SUITE_FLAGS[@]}" --path "${PROJECT_DIR}" res://tests/test_runner.tscn -- "--suite=${suite}" 2>&1 | tee "${log}"
	local status=${PIPESTATUS[0]}
	if grep -q "RESULT: SKIP" "${log}"; then
		SKIPPED=$((SKIPPED + 1))
	fi
	rm -f "${log}"
	if [[ ${status} -ne 0 ]]; then
		echo "suite '${suite}' FAILED (exit ${status})"
		FAILURES=$((FAILURES + 1))
	fi
	return 0
}

echo "test mode: ${MODE}"

run_suite core
run_suite voxel
run_suite ui

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
if [[ ${FAILURES} -eq 0 && ${SKIPPED} -eq 0 ]]; then
	echo "# ALL SUITES PASSED"
elif [[ ${FAILURES} -eq 0 ]]; then
	echo "# ALL RUNNABLE SUITES PASSED (${SKIPPED} skipped - needs a display)"
else
	echo "# ${FAILURES} SUITE(S) FAILED"
fi
echo "##########################################################"
exit "${FAILURES}"
