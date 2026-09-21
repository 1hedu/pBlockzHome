# A kill streak is announced to the whole town, Watcher included though he is not in the fight:
# five kills, a death, then three more. Announced at 3, 5, 10, 15 and 20 only, and the death
# starts the count again rather than carrying on to eight.
#
#   godot --headless --path . -s res://tests/streak_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8826

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var heard: Array[String] = []
var t := 0.0
var at := 0.0
var phase := 0
var kills := 0
var reports := {}

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(heard.size() - 1, -1, -1):
		if heard[i].begins_with(prefix): return heard[i].substr(prefix.length())
	return ""

func _chat(who: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(reports[who]): return out
	for line in FileAccess.get_file_as_string(reports[who]).split("\n"):
		if line.begins_with("CHAT "): out.append(line.substr(5))
	return out

func _spawn(who: String) -> void:
	var before := OS.get_environment("PBLOCKZ_NO_DEV_KEY")
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	reports[who] = OS.get_user_data_dir().path_join("streak_%s.txt" % who)
	DirAccess.remove_absolute(reports[who])
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT,
		"--chunk=%s" % OS.get_user_data_dir().path_join("streak_peer.luau"), "--out=%s" % reports[who], "--name=%s" % who])
	if pid > 0: kids.append(pid)
	if before == "": OS.unset_environment("PBLOCKZ_NO_DEV_KEY")
	else: OS.set_environment("PBLOCKZ_NO_DEV_KEY", before)

func _initialize() -> void:
	print("kill streaks are announced")
	var f := FileAccess.open(OS.get_user_data_dir().path_join("streak_peer.luau"), FileAccess.WRITE)
	f.store_string("""
game:GetService("TextChatService").MessageReceived:Connect(function(msg)
	print("SEEN CHAT " .. tostring(msg.Text))
end)
""")
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.data_store_path = ""
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	for who in ["Killer", "Victim", "Watcher"]:
		_spawn(who)

const HEAD := """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local Killer, Victim = Players:FindFirstChild("Killer"), Players:FindFirstChild("Victim")
local function bare(p)
	local ff = p and p.Character and p.Character:FindFirstChildOfClass("ForceField")
	if ff then ff:Destroy() end
end
"""

## One killing blow: `by` finishes `on`.
func _kill(on: String, by: String) -> void:
	world.run_chunk("kill", HEAD + """
bare(%s)
print("KILL " .. tostring(Health.hit(%s, %s, 1000, 0)))
""" % [on, on, by])

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 3.0 and int(t * 2) != int((t - delta) * 2):
				world.run_chunk("here", HEAD + """
local n = 0
for _, name in ipairs({ "Killer", "Victim", "Watcher" }) do
	local p = Players:FindFirstChild(name)
	if p and p.Character and p.Character:FindFirstChild("Humanoid") then n += 1 end
end
print("HERE " .. n)
local lines = {}
for i = 1, 20 do
	local line = Health.streakLine("X", i)
	if line then table.insert(lines, i .. "=" .. line) end
end
print("LINES " .. table.concat(lines, ";"))
""")
			if _said("HERE ") == "3" or t > 90.0:
				phase = 1; at = t - 10.0
		1:
			# 4 s apart: the body has respawned by the next blow.
			if t - at > 4.0:
				at = t
				kills += 1
				_kill("Victim", "Killer")
				if kills == 5: phase = 2
		2:
			if t - at > 4.0:
				at = t
				phase = 3
				_kill("Killer", "Victim")
		3:
			if t - at > 4.0:
				at = t
				kills += 1
				_kill("Victim", "Killer")
				if kills == 8: phase = 4
		4:
			if t - at > 4.0:
				phase = 5
				_verdict()
	return false

func _verdict() -> void:
	var watcher := _chat("Watcher")
	var victim := _chat("Victim")
	print("    Watcher's chat: ", " | ".join(watcher))
	check(_said("LINES ") == "3=X is on fire!;5=X is on a 5 kill streak!;10=X is on a 10 kill streak!;15=X is on a 15 kill streak!;20=X is on a 20 kill streak!",
		"announced at 3, 5, 10, 15 and 20, and nothing in between: %s" % _said("LINES "))
	check(watcher.has("Killer is on fire!"), "at three kills, Watcher -- not in the fight -- is told Killer is on fire")
	check(victim.has("Killer is on fire!"), "and so is Victim")
	check(watcher.has("Killer is on a 5 kill streak!"), "at five, everybody is told it is a 5 kill streak")
	var fires := 0
	for line in watcher:
		if line == "Killer is on fire!": fires += 1
	check(fires == 2, "dying ends it: three more kills afterwards are on fire again (%d times on fire)" % fires)
	check(not " ".join(watcher).contains("8 kill"), "not a streak carried on past the death")
	for pid in kids: OS.kill(pid)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
