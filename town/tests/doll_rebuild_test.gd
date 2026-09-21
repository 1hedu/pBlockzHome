# The paper doll is rebuilt when the outfit changes, and not otherwise.
#
#   godot --headless --path . -s res://tests/doll_rebuild_test.gd
#
# A rebuild is a fresh clone off the real character, so it does not carry an attribute marked
# on the body already in the frame. Mark, push, and see whether the mark survived.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var lit := false

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("rebuilding the doll only when there is a reason to")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := line.find(prefix)
		if at >= 0:
			out.append(line.substr(at + prefix.length()).strip_edges())
	return out

## Pushes an inventory down WardrobeRemote, with the Familiar worn or not.
func _push(worn: bool) -> void:
	world.run_chunk("fill", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
rs.WardrobeRemote:FireClient(player, "items", {
	{ id = "0x1", name = "Familiar", model = "Familiar", thumb = "", slot = "pet",
	  tier = 4, tier_name = "", worn = %s },
	{ id = "0x2", name = "Top Hat", model = "Top Hat", thumb = "", slot = "hat",
	  tier = 2, tier_name = "", worn = false },
}, { name = "", tier = 0 }, { "Familiar", "", "", "", "", "", "", "", "", "" }, false)
""" % ("true" if worn else "false"))
	await create_timer(0.8).timeout

func _mark() -> void:
	world.run_client_chunk("mark", """
local Players = game:GetService("Players")
local wardrobe = Players.LocalPlayer.PlayerGui:FindFirstChild("Wardrobe")
for _, c in ipairs(wardrobe:GetDescendants()) do
	if c:IsA("ViewportFrame") and c.Name == "Doll" then
		for _, kid in ipairs(c:GetChildren()) do
			if kid:IsA("Model") then kid:SetAttribute("Seen", true) end
		end
	end
end
""")
	await create_timer(0.6).timeout

## The last DOLL line: how many bodies are in the frame, and how many carry the mark.
func _look() -> String:
	said.clear()
	world.run_client_chunk("look", """
local Players = game:GetService("Players")
local wardrobe = Players.LocalPlayer.PlayerGui:FindFirstChild("Wardrobe")
local bodies, marked = 0, 0
for _, c in ipairs(wardrobe:GetDescendants()) do
	if c:IsA("ViewportFrame") and c.Name == "Doll" then
		for _, kid in ipairs(c:GetChildren()) do
			if kid:IsA("Model") then
				bodies += 1
				if kid:GetAttribute("Seen") then marked += 1 end
			end
		end
	end
end
print(("DOLL bodies=%d marked=%d"):format(bodies, marked))
""")
	await create_timer(0.8).timeout
	var rows := _lines("DOLL ")
	return String(rows[rows.size() - 1]) if rows.size() > 0 else ""

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	await create_timer(4.0).timeout

	world.run_client_chunk("open", """
local Players = game:GetService("Players")
Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Wardrobe").Enabled = true
""")
	await create_timer(1.0).timeout

	await _push(false)
	var first := await _look()
	check(first.find("bodies=1") >= 0, "one body in the frame to begin with: %s" % first)
	if first.find("bodies=1") < 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	await _mark()
	# The same list again: the action bar re-asks for it until the chain answers.
	for _i in 3:
		await _push(false)
	var same := await _look()
	check(same.find("marked=1") >= 0,
		"the same list again leaves the body alone: %s" % same)
	check(same.find("bodies=1") >= 0,
		"and there is still only one of it: %s" % same)

	await _push(true)
	var changed := await _look()
	check(changed.find("marked=0") >= 0,
		"putting something on copies the body again: %s" % changed)
	check(changed.find("bodies=1") >= 0,
		"throwing the old one away as it goes: %s" % changed)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
