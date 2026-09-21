# Photographs the overhead boards, as a windowed client joined to a town that has bots in it.
#
#   godot --path . -s res://tests/heads_shot.gd -- <shots dir> [--port=8800]
#
# Windowed: a headless run has a dummy renderer that rasterises nothing, resolves no material
# and sorts nothing, so a board can be built, placed and the right size and still not draw.
# overhead_test.gd checks those three headless; this one checks the pixels.
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var said: Array[String] = []

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 and not String(args[0]).begins_with("--") else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false          # the title card would otherwise be the photograph
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8800"))
	world.player_name = _flag("name", "Photographer")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

func _watch() -> void:
	for n in 3:
		said.clear()
		# Full, half and empty are forced on the client's own GUI rather than waited for.
		world.run_chunk("force", ("""
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local screen = me:WaitForChild("PlayerGui"):FindFirstChild("Overhead")
if not screen then return end
for _, b in ipairs(screen:GetChildren()) do
	if b:IsA("BillboardGui") then
		local n = 0
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("Frame") and d.Name == "Window" then
				n += 1
				-- full, half, empty: one of each, so one picture answers it
				d.Size = UDim2.new(n == 1 and 1 or n == 2 and 0.5 or 0, 0, 1, 0)
				d.Visible = n < 3
			end
		end
	end
end
"""))
		await create_timer(1.0).timeout
		world.run_chunk("fills", """
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local screen = me:WaitForChild("PlayerGui"):FindFirstChild("Overhead")
if not screen then print("FILLS no screen") return end
for _, b in ipairs(screen:GetChildren()) do
	if b:IsA("BillboardGui") then
		local who = b.Name:sub(#"Overhead" + 1)
		local them = Players:FindFirstChild(who)
		local hum = them and them.Character and them.Character:FindFirstChildOfClass("Humanoid")
		local bits = {}
		for _, d in ipairs(b:GetDescendants()) do
			if d:IsA("Frame") and d.Name == "Window" then
				table.insert(bits, ("%.1f%s"):format(d.Size.X.Scale * 2, d.Visible and "" or "(hidden)"))
			end
		end
		print(("FILLS %s health=%s fills=[%s] absSize=%s"):format(
			who, hum and tostring(hum.Health) or "?", table.concat(bits, " "),
			tostring(b.Size)))
	end
end
""")
		await create_timer(1.5).timeout
		for row in _lines("FILLS "):
			print("    shot %d: %s" % [n, row])
		var img := get_root().get_texture().get_image()
		img.save_png(shots.path_join("fill%d.png" % n))
		print("  -> fill%d.png" % n)
		await create_timer(2.5).timeout
	quit(0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 26.0:
		phase = 1
		t = 0.0
		# The default camera follows this character, so placing the body frames the subject.
		world.run_chunk("stand", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local them
for _, p in ipairs(Players:GetPlayers()) do
	if p ~= me and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
		them = p
		break
	end
end
if not them then print("SHOT nobody else is here") return end
local theirs = them.Character.HumanoidRootPart
local mine = me.Character:WaitForChild("HumanoidRootPart")
-- In front of them and facing them, and held there: a body its own client simulates drifts.
task.spawn(function()
	for _ = 1, 600 do
		RunService.Heartbeat:Wait()
		mine.CFrame = CFrame.new(theirs.Position + theirs.CFrame.LookVector * 9
			+ Vector3.new(0, 0.5, 0), theirs.Position)
	end
end)
print(("SHOT standing in front of %s"):format(them.Name))
""")
	elif phase == 1 and t > 4.0:
		phase = 2
		t = 0.0
		for row in _lines("SHOT "):
			print("    ", row)
		# Each picture is paired with the row's numbers read in the same instant.
		_watch()
	elif phase == 2 and t > 3.0:
		for row in _lines("TALLY "):
			print("    ", row)
		quit(0)
	return false
