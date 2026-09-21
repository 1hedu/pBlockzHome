# A close look at one of the town's own people.
#
#   godot --path . -s res://tests/npc_look.gd -- <shots dir> <model name> [part] [distance]
#
# shoot.gd dresses the player and pet_look.gd summons a pet; neither photographs a standing
# NPC, which is a part from scripts/src/map/*.model.json that never moves. The camera has to be
# Scriptable -- the host drives it off the character every frame, so a write to the Camera3D is
# gone by the next one -- and the shot waits for the intro's line lifting the dark, because a
# shot on a timer photographs the loading bar.
extends SceneTree

var world: PulseBlockzWorld
var shots := ""
var who := "Funmaster"
var part := "Head"
var back := 5.0
var lit := false
var phase := 0
var t := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	who = args[1] if args.size() > 1 else who
	part = args[2] if args.size() > 2 else part
	back = float(args[3]) if args.size() > 3 else back
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	main.show_title = false
	world.script_error.connect(func(n, e): printerr("  LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		if line.begins_with("intro:"): lit = true
		elif line.begins_with("NPC at"): _aim(line)
		elif line.begins_with("NPC "): print(line))
	get_root().add_child(main)

## Aims the camera, once the place has printed where the subject is.
func _aim(line: String) -> void:
	var bits := line.split(" ")
	var at := Vector3(float(bits[2]), float(bits[3]), float(bits[4]))
	# Off to the side and slightly above: head-on against the sky, a hat sitting on the head
	# and a hat floating over it look the same.
	world.run_client_chunk("aim", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 35
cam.CFrame = CFrame.new(Vector3.new(%f, %f, %f), Vector3.new(%f, %f, %f))
""" % [at.x + back * 0.8, at.y + back * 0.35, at.z + back * 0.6, at.x, at.y - 0.35, at.z])
	# The chat box, the bar and the name tags otherwise sit across the subject.
	world.run_client_chunk("hideui", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if gui then
	for _, s in ipairs(gui:GetChildren()) do
		if s:IsA("ScreenGui") then s.Enabled = false end
	end
end
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BillboardGui") then d.Enabled = false end
end
""")
	phase = 2
	t = 0.0

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 1.5:
		phase = 1
		world.run_chunk("find", """
local function find(node, want)
	for _, d in ipairs(node:GetDescendants()) do
		if d.Name == want then return d end
	end
	return nil
end
local model = find(workspace, "%s")
if not model then print("NPC missing " .. "%s") return end
local p = model:IsA("BasePart") and model or find(model, "%s")
if not p then print("NPC no part") return end
print(("NPC at %%.3f %%.3f %%.3f"):format(p.Position.X, p.Position.Y, p.Position.Z))
""" % [who, who, part])
	elif phase == 2 and t > 2.5:
		var name := "%s-%s" % [who.to_lower(), part.to_lower()]
		get_root().get_texture().get_image().save_png(shots.path_join(name + ".png"))
		print("  -> %s" % shots.path_join(name + ".png"))
		quit(0)
	return false
