# A verdict out of what a probe printed, as the "N passed, M failed" line run.ps1 reads.
#
# "LABEL what happened: value (wanted x)" passes when the value is x; a line ending in true or
# false passes on true. A probe that printed nothing to judge fails.
extends RefCounted

static func finish(lines: Array, prefix: String, extra_passed: int = 0, extra_failed: int = 0) -> int:
	var passed := extra_passed
	var failed := extra_failed
	var seen := 0
	for raw in lines:
		var line := String(raw)
		if not line.begins_with(prefix + " "): continue
		var want := ""
		var got := ""
		var body := line.substr(prefix.length() + 1)
		var w := body.rfind(" (wanted ")
		if w >= 0:
			want = body.substr(w + 9).trim_suffix(")")
			body = body.substr(0, w)
			var c := body.rfind(": ")
			if c < 0: continue
			got = body.substr(c + 2).strip_edges()
		else:
			var c := body.rfind(": ")
			if c < 0: continue
			got = body.substr(c + 2).strip_edges()
			if got != "true" and got != "false": continue
			want = "true"
		seen += 1
		if got == want:
			passed += 1
			print("  PASS ", body)
		else:
			failed += 1
			printerr("  FAIL ", body, " (wanted ", want, ")")
	if seen == 0 and extra_passed + extra_failed == 0:
		failed += 1
		printerr("  FAIL the probe printed nothing to judge")
	print("%d passed, %d failed" % [passed, failed])
	return 1 if failed > 0 else 0
