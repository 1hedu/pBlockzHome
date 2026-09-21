# Another player's hearts and name show only while they can be seen: through glass, not
# through a wall, and by the character's line of sight rather than the camera's.
#
#   godot --headless --path . -s res://tests/hearts_sight_test.gd
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8821

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var report := ""
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last(prefix: String) -> String:
	if not FileAccess.file_exists(report): return ""
	var lines := FileAccess.get_file_as_string(report).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

const VIEWER := """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
RunService.RenderStepped:Connect(function()
	local runner = Players:FindFirstChild("Runner")
	local myRoot = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
	local theirs = runner and runner.Character and runner.Character:FindFirstChild("HumanoidRootPart")
	if myRoot and theirs then
		-- CamHigh: the camera swung up high over the wall, where it can see them and the character cannot.
		local lift = game:GetService("ReplicatedStorage"):GetAttribute("CamHigh") and 40 or 1.5
		cam.CFrame = CFrame.lookAt(myRoot.Position + Vector3.new(0, lift, 0), theirs.Position)
	end
end)
while true do
	task.wait(0.5)
	local screen = me.PlayerGui:FindFirstChild("Overhead")
	local board = screen and screen:FindFirstChild("OverheadRunner")
	if board then
		print(("SEEN VIS hearts=%s name=%s"):format(tostring(board.Hearts.Visible), tostring(board.Name ~= "" and board:FindFirstChild("Name").Visible)))
	end
end
"""

func _initialize() -> void:
	print("hearts only in sight")
	StandIns.stage("sight")
	report = OS.get_user_data_dir().path_join("sight_viewer.txt")
	DirAccess.remove_absolute(report)
	var chunk := OS.get_user_data_dir().path_join("sight_viewer.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string(VIEWER)
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	for spec in [["tests/chunk_peer.gd", ["--chunk=%s" % chunk, "--out=%s" % report, "--name=Viewer"]],
				 ["tests/bot.gd", ["--name=Runner", "--every=999"]]]:
		var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://" + spec[0], "--", "--port=%d" % PORT]
		args.append_array(spec[1])
		var pid := OS.create_process(OS.get_executable_path(), args)
		if pid > 0: kids.append(pid)

func _wall(transparency: float) -> void:
	world.run_chunk("wall", """
local old = workspace:FindFirstChild("SightWall")
if old then old:Destroy() end
if %f < 0 then return end
local wall = Instance.new("Part")
wall.Name = "SightWall"
wall.Anchored = true
wall.Size = Vector3.new(30, 20, 1)
wall.Position = Vector3.new(25, 8, 50)
wall.Transparency = %f
wall.Parent = workspace
""" % [transparency, transparency])

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("stage", StandIns.chunk("sight"))
		world.run_chunk("places", """
local Players = game:GetService("Players")
local SPOTS = { Viewer = Vector3.new(25, 0, 40), Runner = Vector3.new(25, 0, 60) }
game:GetService("RunService").Heartbeat:Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		local spot = SPOTS[p.Name]
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if spot and root then
			root.CFrame = CFrame.new(Vector3.new(spot.X, root.Position.Y, spot.Z))
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end)
""")
	elif phase == 1 and t > 30.0:
		phase = 2
		check(_last("VIS ") == "hearts=true name=true", "across open ground, the hearts show: %s" % _last("VIS "))
		_wall(0.0)
	elif phase == 2 and t > 34.0:
		phase = 3
		check(_last("VIS ") == "hearts=false name=false", "behind a wall they go, and the name with them: %s" % _last("VIS "))
		world.run_chunk("high", "game:GetService('ReplicatedStorage'):SetAttribute('CamHigh', true)")
	elif phase == 3 and t > 38.0:
		phase = 31
		check(_last("VIS ") == "hearts=false name=false", "the camera swung up over the wall does not see them either: %s" % _last("VIS "))
		world.run_chunk("low", "game:GetService('ReplicatedStorage'):SetAttribute('CamHigh', nil)")
		_wall(-1.0)
	elif phase == 31 and t > 42.0:
		phase = 4
		check(_last("VIS ") == "hearts=true name=true", "take the wall away and they are back: %s" % _last("VIS "))
		_wall(0.6)
	elif phase == 4 and t > 46.0:
		phase = 5
		check(_last("VIS ") == "hearts=true name=true", "and through glass they still show: %s" % _last("VIS "))
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
