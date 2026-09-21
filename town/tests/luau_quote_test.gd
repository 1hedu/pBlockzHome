# host/Luau.gd quote(): host text -- chain data, a manifest's splash, explorer pages -- pasted
# into a chunk stays text. Each hostile string is set as an attribute by a real chunk and read
# back byte for byte; a control chunk wrapping it in [==[ ]==] runs the code in it instead.
#
#   godot --headless --path . -s res://tests/luau_quote_test.gd
extends SceneTree

const Luau = preload("res://host/Luau.gd")

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var lines: Array[String] = []
var t := 0.0
var phase := 0

const NASTY := [
	"]==]) print(\"PWNED long bracket\") local _ = ([==[",
	"\"; print(\"PWNED quote\") --",
	"back\\slash \\\" and \\n written out",
	"line one\nline two\r\n\ttabbed",
	"bell" + char(7) + " then 9 digits " + char(1) + "9",
	"héllo, 🙂, ]] and ]=] and ]==]",
	"",
]

func check(ok: bool, what: String) -> void:
	print(("  PASS " if ok else "  FAIL ") + what)
	if ok: passed += 1
	else: failed += 1

func _initialize() -> void:
	print("luau quote: host text stays text")
	var main := Node.new()
	root.add_child(main)
	world = PulseBlockzWorld.new()
	world.mode = PulseBlockzWorld.MODE_SERVER
	world.auto_join = false
	world.default_controls = false
	world.default_camera = false
	main.add_child(world)
	world.script_print.connect(func(_n, s): lines.append(String(s)))
	world.script_error.connect(func(n, e): lines.append("ERROR " + String(n) + ": " + String(e)))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 0.5:
		phase = 1
		for i in NASTY.size():
			world.run_chunk("quote%d" % i, "workspace:SetAttribute(\"Q%d\", %s)\nprint(\"SET %d|\" .. workspace:GetAttribute(\"Q%d\"))" % [i, Luau.quote(NASTY[i]), i, i])
		world.run_chunk("oldway", "workspace:SetAttribute(\"OLD\", [==[%s]==])" % NASTY[0])
	elif phase == 1 and t > 1.5:
		phase = 2
		for i in NASTY.size():
			var got = null
			for l in lines:
				if l.begins_with("SET %d|" % i): got = l.substr(("SET %d|" % i).length())
			check(typeof(got) == TYPE_STRING and got == NASTY[i], "string %d comes back byte for byte: %s" % [i, JSON.stringify(got)])
		check(not lines.any(func(l): return l == "PWNED quote"), "a quote inside it runs nothing")
		var old_ran := lines.any(func(l): return l == "PWNED long bracket")
		check(old_ran, "while the old [==[ ]==] wrapping of the same text did run the code in it (the hole this closes)")
		check(lines.filter(func(l): return l.begins_with("SET ")).size() == NASTY.size(), "every quoted chunk ran to the end: %s" % [lines.filter(func(l): return l.begins_with("ERROR"))])
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
