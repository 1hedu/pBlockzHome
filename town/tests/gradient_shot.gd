# The PulseBlockz gradient where it is worn: the character, an Engram badge and the cane's orb
# side by side and facing the lens, so the grain can be compared.
#
#   godot --path . -s res://tests/gradient_shot.gd -- <shots dir>
#
# Windowed: headless has a dummy renderer and draws nothing.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var look_pending := false

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

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		world.run_chunk("standins", StandIns.chunk("gradient"))
	elif phase == 1 and t > 9.0:
		phase = 2
		world.run_chunk("place", """
local rs = game:GetService("ReplicatedStorage")
local Engram = require(rs:WaitForChild("Engram"))
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root = ch.HumanoidRootPart
-- Where he stands, and his own front: the badge and the orb go either side of him, facing the lens.
local at = root.Position
local front = root.CFrame.LookVector
local side = root.CFrame.RightVector
workspace:SetAttribute("ShotAt", at)
workspace:SetAttribute("ShotFront", front)
-- The badge, big enough to read, to his left as the lens sees it.
local badge = Engram.build("Look", Engram.look())
for _, d in ipairs(badge:GetDescendants()) do
	if d:IsA("BasePart") then d.Anchored = true end
end
badge.Parent = workspace
local handle = badge:FindFirstChild("Handle")
local mesh = handle:FindFirstChildOfClass("SpecialMesh")
if mesh then mesh.Scale = Vector3.one * 2.5 end
handle.Size = handle.Size * 2.5
for _, d in ipairs(badge:GetChildren()) do
	if d:IsA("BasePart") and d ~= handle then d.Transparency = 1 end
end
handle.CFrame = CFrame.lookAt(at + side * -4 + front * 1 + Vector3.new(0, 0.5, 0), at + side * -4 + front * 10 + Vector3.new(0, 0.5, 0))
-- An orb, still, to his right.
local folder = rs.PlaceAssets
local ball = Instance.new("Part")
ball.Anchored = true
ball.CanCollide = false
ball.Size = Vector3.one * 2.5
ball.Transparency = 0.3
ball.CFrame = CFrame.lookAt(at + side * 4 + front * 1 + Vector3.new(0, 0.5, 0), at + side * 4 + front * 10 + Vector3.new(0, 0.5, 0))
local m = Instance.new("SpecialMesh")
m.MeshType = Enum.MeshType.FileMesh
m.MeshId = folder.OrbMesh.Value
m.TextureId = folder.PulseGradient.Value
m.Scale = Vector3.one * 2.5
m.Parent = ball
ball.Parent = workspace
""")
		look_pending = true
	elif phase == 2 and look_pending and t > 10.0:
		look_pending = false
		world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local at = workspace:GetAttribute("ShotAt")
local front = workspace:GetAttribute("ShotFront")
cam.CFrame = CFrame.lookAt(at + front * 15 + Vector3.new(0, 1, 0), at + Vector3.new(0, 0.5, 0))
cam.FieldOfView = 50
for _, s in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
""")
	elif phase == 2 and t > 13.0:
		phase = 3
		var file := shots.path_join("gradient.png")
		get_root().get_texture().get_image().save_png(file)
		print("  -> ", file)
		quit(0)
	return false
