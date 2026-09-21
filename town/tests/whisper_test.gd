# /w, /whisper and /squelch: one line to one person, and to nobody else. Privacy is by
# delivery -- the server sends only to the channel's TextSources -- so it is checked from the
# receiving end: Alice, Bob and Carol join as separate processes, each logging what it hears.
#
#   godot --headless --path . -s res://tests/whisper_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Script errors raised by the server; asserted empty at the end.
var errors: Array[String] = []
var main: Node
var said: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var files := {}

const PORT := 8816
const LINE := "are you there Bob"
const ALIAS := "the long one works too"
const GHOST := "Nigel"          # no player in the town by this name
const SHOUT := "everybody hears this"
const HUSHED := "and this is straight at you Carol"

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

## Every row one peer heard: "channel|speaker|text".
func _heard(who: String) -> PackedStringArray:
	var at: String = files[who]
	if not FileAccess.file_exists(at):
		return PackedStringArray()
	var blob := FileAccess.get_file_as_string(at).strip_edges()
	return PackedStringArray() if blob == "" else blob.split("\n")

## What one peer's chat window drew; /squelch changes this and not _heard.
func _drew(who: String) -> String:
	var at: String = String(files[who]) + ".drew"
	return FileAccess.get_file_as_string(at) if FileAccess.file_exists(at) else ""

func _matching(who: String, what: String) -> PackedStringArray:
	var out := PackedStringArray()
	for row in _heard(who):
		if String(row).find(what) >= 0:
			out.append(String(row))
	return out

func _peer(who: String, say: String, after: float) -> void:
	files[who] = OS.get_user_data_dir().path_join("whisper-%s.txt" % who)
	DirAccess.remove_absolute(files[who])
	DirAccess.remove_absolute(files[who] + ".drew")
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/whisper_peer.gd", "--",
		"--name=%s" % who, "--port=%d" % PORT, "--out=%s" % files[who]]
	if say != "":
		args.append("--say=%s" % say)
		args.append("--after=%.1f" % after)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		printerr("could not start peer %s" % who)
	else:
		kids.append(pid)

func _initialize() -> void:
	print("a whisper reaches one person and nobody else")
	main = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

	# Alice speaks one line every 11s, once all three are in; ";;" separates them.
	_peer("Alice", "/w Bob %s;;/whisper Bob %s;;/w %s hello?;;%s;;/w Carol %s"
		% [LINE, ALIAS, GHOST, SHOUT, HUSHED], 11.0)
	_peer("Bob", "", 0.0)
	# Carol's squelch lands before Alice's shout and the whisper aimed at her.
	_peer("Carol", "hello everyone;;/squelch Alice", 11.0)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	# 72s: peer startup, then Alice's fifth and last line at join+55s, then its trip up to the
	# server, onto a channel and back down into the two logs that get it
	if phase == 0 and t > 72.0:
		phase = 1
		t = 0.0
		# The town may say nothing of its own, so an empty log is legitimate and only the file's
		# existence proves the peer came up -- tightening >= 0 to > 0 would ride on town chatter
		check(_heard("Bob").size() >= 0 and FileAccess.file_exists(files["Bob"]),
			"all three clients are up and writing down what they hear")

		var toBob := _matching("Bob", LINE)
		var toAlice := _matching("Alice", LINE)
		var toCarol := _matching("Carol", LINE)

		check(toBob.size() > 0, "Bob got the whisper: %s" % str(toBob))
		check(toAlice.size() > 0, "and Alice sees her own copy of it: %s" % str(toAlice))
		check(toCarol.size() == 0,
			"and Carol, standing right there, heard nothing: %s" % str(toCarol))

		if toBob.size() > 0:
			var bits: PackedStringArray = String(toBob[0]).split("|")
			check(bits.size() >= 3 and String(bits[0]).begins_with("RBXWhisper"),
				"on a whisper channel of its own, not in the general chat: %s" % bits[0])
			check(bits.size() >= 3 and String(bits[1]) == "Alice",
				"and it says who it came from: %s" % bits[1])

		var shouted := 0
		for row in _heard("Carol"):
			if String(row).begins_with("RBXGeneral") and String(row).find("/w ") >= 0:
				shouted += 1
		check(shouted == 0, "and the command itself was never said out loud: %d such lines" % shouted)

		var alias := _matching("Bob", ALIAS)
		check(alias.size() > 0, "/whisper reaches him as well as /w: %s" % str(alias))
		if alias.size() > 0 and toBob.size() > 0:
			check(String(alias[0]).split("|")[0] == String(toBob[0]).split("|")[0],
				"and on the same channel, not a second one for the same pair")

		var told := PackedStringArray()
		for row in _heard("Alice"):
			if String(row).find(GHOST) >= 0:
				told.append(String(row))
		check(told.size() > 0, "whispering to somebody who is not here says so: %s" % str(told))
		check(_matching("Carol", GHOST).size() == 0
				and _matching("Bob", GHOST).size() == 0,
			"and says it to nobody else")

		# ---- /squelch ------------------------------------------------------------------
		# Squelch is the window's decision: the server is never told and the line is still
		# delivered, so these read _drew and not _heard.
		check(_drew("Bob").find(SHOUT) >= 0,
			"Bob, who squelched nobody, sees the shout")
		check(_drew("Carol").find(SHOUT) < 0,
			"and Carol, who squelched Alice, does not: %s" % _drew("Carol"))
		# A squelch is per speaker, not per channel.
		check(_drew("Carol").find(HUSHED) < 0,
			"nor a whisper aimed straight at her")
		check(_matching("Carol", HUSHED).size() > 0,
			"though it was delivered to her -- squelch is her window's decision, not the server's")
		check(_drew("Carol").find("squelched") >= 0,
			"and she was told it took: %s" % _drew("Carol"))
		check(_drew("Bob").find("squelched") < 0, "and nobody else was told anything")
		# Control: her own earlier line still reaches Bob, so a squelched window is not a dead one.
		check(_drew("Bob").find("hello everyone") >= 0,
			"while Carol's own line before it reached everybody: %s" % _drew("Bob"))

		world.run_chunk("state", """
local TextChatService = game:GetService("TextChatService")
local channels = TextChatService:WaitForChild("TextChannels")
local names, whispers = {}, 0
for _, c in ipairs(channels:GetChildren()) do
	if c:IsA("TextChannel") then
		local n = 0
		for _, s in ipairs(c:GetChildren()) do
			if s:IsA("TextSource") then n += 1 end
		end
		table.insert(names, ("%s(%d)"):format(c.Name, n))
		if c.Name:match("^RBXWhisper") then whispers += 1 end
	end
end
print(("CHANNELS %d whisper channel(s): %s"):format(whispers, table.concat(names, " ")))

local who = {}
for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
	table.insert(who, ("%s=%d"):format(p.Name, p.UserId))
end
print("WHO " .. table.concat(who, " "))
""")
	elif phase == 1 and t > 3.0:
		phase = 2
		var rows := _lines("CHANNELS ")
		check(rows.size() > 0, "the server's channel list was read: %s" % str(rows))
		if rows.size() > 0:
			var r := String(rows[0])
			# 2: one channel per pair who spoke, not per line -- Alice sent Bob two and Carol one.
			check(r.begins_with("2 whisper channel"),
				"one whisper channel per pair who spoke, and no more: %s" % r)
			# A third TextSource in a whisper channel is the leak this test is about.
			check(r.find("_2)") >= 0 or r.match("*RBXWhisper*(2)*"),
				"with two people in it: %s" % r)
			check(r.find("RBXGeneral(3)") >= 0,
				"and all three still in the general chat: %s" % r)

		# A TextSource is keyed by UserId: players sharing an id share one source, and a line
		# reaches whichever of them arrived first. A client that sets no id claims the default.
		var who := _lines("WHO ")
		check(who.size() > 0, "the town's user ids were read: %s" % str(who))
		if who.size() > 0:
			var seen := {}
			var dupe := false
			for cell in String(who[0]).split(" ", false):
				var id := String(cell).split("=")[-1]
				if seen.has(id): dupe = true
				seen[id] = true
			check(not dupe and seen.size() == 3,
				"and no two players share one: %s" % who[0])
		_finish()
	return false
