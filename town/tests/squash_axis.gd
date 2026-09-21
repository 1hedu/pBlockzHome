# Squash stretches a particle along its travel, as on Roblox, not along the screen: an emitter
# firing sideways, seen from the side, draws streaks lying flat rather than standing up. A shot
# to read by eye -- it asserts nothing.
#
#   godot --path . -s res://tests/squash_axis.gd -- <shots dir>
extends SceneTree
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("sideways", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
ch:PivotTo(CFrame.new(0, 4, 20))
local p = Instance.new("Part")
p.Name = "Sideways"
p.Anchored = true p.CanCollide = false p.Transparency = 1
p.Size = Vector3.new(0.2, 0.2, 0.2)
p.Position = Vector3.new(-6, 60, 260)
p.Parent = workspace
local e = Instance.new("ParticleEmitter")
e.Rate = 8
e.Lifetime = NumberRange.new(2.5, 2.5)
e.Speed = NumberRange.new(6, 6)
e.SpreadAngle = Vector2.new(0, 0)
e.Size = NumberSequence.new(1.5)
e.Squash = NumberSequence.new(4)
e.Transparency = NumberSequence.new(0)
e.Color = ColorSequence.new(Color3.fromRGB(0, 255, 0))
e.LightEmission = 0
e.EmissionDirection = Enum.NormalId.Right      -- along +X, straight across the view
e.Parent = p
print("AXIS emitting along +X")
""")
		world.run_client_chunk("cam", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 45
cam.CFrame = CFrame.new(Vector3.new(0, 60, 285), Vector3.new(0, 60, 260))
""")
		t = 0.0
	elif phase == 1 and t > 5.0:
		get_root().get_texture().get_image().save_png(shots.path_join("axis.png"))
		print("  -> axis.png")
		quit(0)
	return false
