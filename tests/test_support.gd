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


## Equality check with an optional trailing note.
##
## [param detail] exists because six call sites in the M1 suite passed one, and a
## GDScript call with too many arguments raises at runtime *without* failing the
## run: the check was silently skipped and the rest of the test function with it.
## Accepting the argument is the fix that cannot be forgotten; the guard below is
## the safety net if a future suite grows a fifth one.
func check_equal(
		description: String, actual: Variant, expected: Variant, detail: String = ""
) -> void:
	var note := "actual=%s expected=%s" % [actual, expected]
	if not detail.is_empty():
		note += " " + detail
	check(description, actual == expected, note)


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
