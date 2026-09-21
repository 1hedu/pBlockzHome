# Photographs of the fish: the Everliving Fish and the rod worn, and every fish colour in a row.
#
#   godot --path . -s res://tests/fish_shot.gd -- <shots dir>
#
# The models are the town's own (shared/Fish.luau, built into ReplicatedStorage.Made).
# Windowed: headless has a dummy renderer and draws nothing.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var shots := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _look(from: Vector3, at: Vector3, fov := 40.0) -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local root = game:GetService("Players").LocalPlayer.Character.HumanoidRootPart
cam.CFrame = CFrame.lookAt(root.Position + Vector3.new(%f, %f, %f), root.Position + Vector3.new(%f, %f, %f))
cam.FieldOfView = %f
for _, s in ipairs(game:GetService("Players").LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
""" % [from.x, from.y, from.z, at.x, at.y, at.z, fov])

func _run() -> void:
	await create_timer(9.0).timeout
	world.run_chunk("dress", """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local root = ch.HumanoidRootPart
root.CFrame = CFrame.new(20, root.Position.Y, 60)
root.Anchored = true
for _, name in ipairs({ "Everliving Fish", "Dysnomia Rod" }) do
	local m = rs.Made:FindFirstChild(name)
	if m then hum:AddAccessory(m:Clone()) else print("SHOT missing " .. name) end
end
-- The rest laid out in a row to his left, each one on its own, handle anchored.
local names = { "Red Fish", "Magenta Fish", "Purple Fish", "Blue Fish", "Cyan Fish", "Yellow Fish",
	"Orange Fish", "Indigo Fish", "Green Fish", "Everliving Fish" }
for i, name in ipairs(names) do
	local m = rs.Made:FindFirstChild(name)
	if m then
		-- An Accessory is not a PVInstance, on Roblox or here, so it goes in a Model to be placed.
		local holder = Instance.new("Model")
		holder.Name = name .. " Display"
		local copy = m:Clone()
		for _, d in ipairs(copy:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
		copy.Parent = holder
		holder.PrimaryPart = copy:FindFirstChild("Handle")
		holder.Parent = workspace
		local row = (i - 1) % 5
		local col = math.floor((i - 1) / 5)
		holder:PivotTo(CFrame.new(root.Position.X - 4 - row * 1.8, root.Position.Y + 1.2 - col * 1.4, root.Position.Z) * CFrame.Angles(0, math.rad(90), 0))
	end
end
""")
	await create_timer(2.0).timeout
	# He faces -Z: from his right side, then from in front.
	_look(Vector3(9.0, 1.0, -1.5), Vector3(0.0, 0.0, -1.5))
	await create_timer(1.5).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fish_held_side.png"))
	_look(Vector3(2.5, 1.5, -9.0), Vector3(0.0, 0.3, 0.0))
	await create_timer(1.5).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fish_held_front.png"))
	_look(Vector3(-7.5, 0.8, -8.5), Vector3(-7.5, 0.6, 0), 45.0)
	await create_timer(1.5).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fish_row.png"))
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(0)
