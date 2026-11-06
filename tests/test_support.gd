extends RefCounted

## Minimal assertion recorder for the headless test suites.
##
## Deliberately not a general-purpose test framework: M0.1 needs pass/fail
## records that can be read straight out of a CI log, and nothing else.

var _checks := 0
var _failures := 0


func check(description: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	var suffix := "" if detail.is_empty() else "   (%s)" % detail
	if condition:
		print("  PASS  %s%s" % [description, suffix])
	else:
		_failures += 1
		print("  FAIL  %s%s" % [description, suffix])


func check_equal(description: String, actual: Variant, expected: Variant) -> void:
	check(description, actual == expected, "actual=%s expected=%s" % [actual, expected])


func info(message: String) -> void:
	print("        %s" % message)


func get_failure_count() -> int:
	return _failures


func get_check_count() -> int:
	return _checks


func summary() -> int:
	print("")
	print("----------------------------------------------------------")
	if _failures == 0:
		print("RESULT: PASS  (%d checks)" % _checks)
	else:
		print("RESULT: FAIL  (%d of %d checks failed)" % [_failures, _checks])
	print("----------------------------------------------------------")
	return 0 if _failures == 0 else 1
