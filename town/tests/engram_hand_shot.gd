# Two shots of an Engram held in the hand: from in front of the character, and from behind.
#
#   godot --path . -s res://tests/engram_hand_shot.gd -- <shots dir>
#
# Windowed: the headless renderer draws nothing.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	StandIns.stage("gradient")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)

func _look(side: float) -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart
local hand = root.CFrame * CFrame.new(-1.5, -1, 0)
cam.CFrame = CFrame.lookAt(hand.Position + root.CFrame.LookVector * (%f * 6) + Vector3.new(0, 0.5, 0), hand.Position)
cam.FieldOfView = 40
for _, s in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
""" % side)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		world.run_chunk("standins", StandIns.chunk("gradient"))
	elif phase == 1 and t > 9.0:
		phase = 2
		world.run_chunk("hold", """
local rs = game:GetService("ReplicatedStorage")
local Engram = require(rs:WaitForChild("Engram"))
local ch = game:GetService("Players"):GetPlayers()[1].Character
local badge = Engram.build("Look", Engram.look())
ch.Humanoid:AddAccessory(badge)
""")
	elif phase == 2 and t > 10.5:
		phase = 3
		_look(1.0)
	elif phase == 3 and t > 12.5:
		phase = 4
		get_root().get_texture().get_image().save_png(shots.path_join("engram_front.png"))
		_look(-1.0)
	elif phase == 4 and t > 14.5:
		phase = 5
		get_root().get_texture().get_image().save_png(shots.path_join("engram_back.png"))
		print("  -> ", shots)
		quit(0)
	return false
