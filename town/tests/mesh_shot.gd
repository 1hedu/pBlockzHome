# A photograph of two EditableMeshes: a cube with a colour per side, and the same cube with a
# corner pulled out after it was already on screen.
#
#   godot --path . -s res://tests/mesh_shot.gd -- <shots dir>
#
# Windowed: the headless renderer is a dummy and draws nothing.
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 8.0:
		phase = 1
		world.run_chunk("place", """
local AssetService = game:GetService("AssetService")
local floor = Instance.new("Part")
floor.Size = Vector3.new(30, 1, 16); floor.Anchored = true; floor.CFrame = CFrame.new(0, 199, 0); floor.Color = Color3.fromRGB(60, 60, 70); floor.Parent = workspace
local colours = { Color3.new(1, 0.2, 0.2), Color3.new(0.2, 1, 0.2), Color3.new(0.2, 0.4, 1), Color3.new(1, 1, 0.2), Color3.new(1, 0.3, 1), Color3.new(0.2, 1, 1) }
local function cube()
	local m = AssetService:CreateEditableMesh()
	local p = { Vector3.new(0,0,0), Vector3.new(1,0,0), Vector3.new(0,1,0), Vector3.new(1,1,0), Vector3.new(0,0,1), Vector3.new(1,0,1), Vector3.new(0,1,1), Vector3.new(1,1,1) }
	local v = {}
	for i, pos in ipairs(p) do v[i] = m:AddVertex(pos) end
	local quads = { {5,6,8,7}, {1,3,4,2}, {1,5,7,3}, {2,4,8,6}, {1,2,6,5}, {3,7,8,4} }
	for side, q in ipairs(quads) do
		local n = m:AddNormal()
		local c = m:AddColor(colours[side], 1)
		for _, tri in ipairs({ {q[1], q[2], q[3]}, {q[1], q[3], q[4]} }) do
			local f = m:AddTriangle(v[tri[1]], v[tri[2]], v[tri[3]])
			m:SetFaceNormals(f, {n, n, n})
			m:SetFaceColors(f, {c, c, c})
		end
	end
	m:RemoveUnused()
	return m
end
local a = AssetService:CreateMeshPartAsync(Content.fromObject(cube()))
a.Size = Vector3.new(4, 4, 4); a.Anchored = true; a.CFrame = CFrame.new(-5, 202, 0) * CFrame.Angles(0, math.rad(35), 0); a.Color = Color3.new(1, 1, 1); a.Parent = workspace
local bm = cube()
local b = AssetService:CreateMeshPartAsync(Content.fromObject(bm))
b.Size = Vector3.new(4, 4, 4); b.Anchored = true; b.CFrame = CFrame.new(5, 202, 0) * CFrame.Angles(0, math.rad(35), 0); b.Color = Color3.new(1, 1, 1); b.Parent = workspace
task.wait(0.5)
bm:SetPosition(bm:FindClosestVertex(Vector3.new(1, 1, 1)), Vector3.new(1.8, 1.8, 1.8))
""")
		world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(0, 207, 18), Vector3.new(0, 202, 0))
cam.FieldOfView = 50
""")
	elif phase == 1 and t > 12.0:
		phase = 2
		var file := shots.path_join("meshes.png")
		get_root().get_texture().get_image().save_png(file)
		print("  -> ", file)
		quit(0)
	return false
