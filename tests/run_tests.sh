#!/usr/bin/env bash
#
# Runs the test suites.
#
#   ./tests/run_tests.sh              # core + generation + voxel + reliability + perf,
#                                     # plus UI input when a display exists
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
	if grep -qE "SCRIPT ERROR|Parse Error" "${log}"; then
		status=1
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
run_suite generation
run_suite m2
run_suite m3
run_suite m4
run_suite voxel
run_suite reliability
run_suite perf
run_suite ui

if [[ "${1:-}" == "--screenshot" ]]; then
	if ! mkdir -p "${SHOT_DIR}"; then
		echo "cannot create screenshot directory: ${SHOT_DIR}" >&2
		FAILURES=$((FAILURES + 1))
	fi

	for seed in 1337 90210; do
		local_shot="${SHOT_DIR}/terrain_seed_${seed}.png"
		echo ""
		echo "### screenshot, seed ${seed} -> ${local_shot}"
		shot_log="$(mktemp)"
		# A display is mandatory for this step; without one the capture script
		# exits non-zero and the failure is propagated below.
		"${GODOT}" "${SUITE_FLAGS[@]}" --path "${PROJECT_DIR}" \
			res://tests/capture_screenshot.tscn -- \
			"--out=${local_shot}" --warmup=12 --seed="${seed}" \
			--distance=100 --pitch=-28 --yaw=35 2>&1 | tee "${shot_log}"
		shot_status=${PIPESTATUS[0]}

		if [[ ${shot_status} -ne 0 ]]; then
			echo "screenshot for seed ${seed} FAILED (exit ${shot_status})" >&2
			FAILURES=$((FAILURES + 1))
		elif ! grep -q "SCREENSHOT_OK" "${shot_log}"; then
			echo "screenshot for seed ${seed} produced no SCREENSHOT_OK line" >&2
			FAILURES=$((FAILURES + 1))
		elif [[ ! -s "${local_shot}" ]]; then
			echo "screenshot ${local_shot} is missing or empty" >&2
			FAILURES=$((FAILURES + 1))
		else
			echo "verified: ${local_shot} ($(wc -c < "${local_shot}") bytes)"
		fi
		rm -f "${shot_log}"
	done
fi

echo ""
echo "##########################################################"
if [[ ${FAILURES} -eq 0 && ${SKIPPED} -eq 0 ]]; then
	echo "# ALL SUITES PASSED"
elif [[ ${FAILURES} -eq 0 ]]; then
	echo "# ALL RUNNABLE SUITES PASSED (${SKIPPED} skipped - needs a display)"
else
	echo "# ${FAILURES} FAILURE(S): suites or screenshots"
fi
echo "##########################################################"
exit "${FAILURES}"
