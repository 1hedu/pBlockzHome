# A photograph of one catalogue item, from several angles, off the staged catalogue.
#
#   godot --path . -s res://tests/model_shot.gd -- <instance name> <shots dir> [zoom]
#
# Stage first, as bots.ps1 does: node scripts/stage-preview.js all .preview
# zoom under 1 comes closer: 0.4 fills the frame with a spoon's bowl.
#
# Windowed: the headless renderer is a dummy and draws nothing.
extends SceneTree

const Preview = preload("res://tests/Preview.gd")

var world: PulseBlockzWorld
var item := ""
var shots := ""
var zoom := 1.0
var t := 0.0
var phase := 0
var said: Array[String] = []

# The views a player catches a held thing at: either side, three-quarters, front and above.
const ANGLES := [
	["side",  Vector3(3.2, 0, 0)],
	["other", Vector3(-3.2, 0, 0)],   # the left side, where a left-wrist item faces
	["three", Vector3(2.2, 1.2, -2.0)],
	["front", Vector3(0, 0.3, -3.2)],
	["top",   Vector3(0.4, 3.2, 0)],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	item = args[0] if args.size() > 0 else "Spoonie"
	shots = args[1] if args.size() > 1 else "user://shots"
	zoom = float(args[2]) if args.size() > 2 else 1.0
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	Preview.stage("shot", ProjectSettings.globalize_path("res://../../../.preview"))
	get_root().add_child(main)

func _look(offset: Vector3, zoom: float) -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local at = workspace:FindFirstChild("ShotTarget")
local c = at and at.Value or Vector3.new(0, 200, 0)
cam.CFrame = CFrame.lookAt(c + Vector3.new(%f, %f, %f) * %f, c)
cam.FieldOfView = 40
""" % [offset.x, offset.y, offset.z, zoom])

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 10.0:
		phase = 1
		Preview.install(world, "shot", ProjectSettings.globalize_path("res://../../../.preview"))
	elif phase == 1 and t > 13.0:
		phase = 2
		# An item's parts ship unanchored, welded to a Handle a character holds, so the copy
		# has to be anchored or it falls through the town before the shutter opens.
		world.run_chunk("place", ("""
local src = game:GetService("ReplicatedStorage").OnChain:FindFirstChild("ITEM")
if not src then print("SHOT no item ITEM") return end
local copy = src:Clone()
local focus = copy:FindFirstChild("Bowl", true) or copy:FindFirstChild("Handle", true)
local lift = Vector3.new(0, 200, 0) - (focus and focus.Position or Vector3.zero)
for _, d in ipairs(copy:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored = true
		d.CFrame = d.CFrame + lift
	end
end
copy.Parent = workspace
local target = Instance.new("Vector3Value")
target.Name = "ShotTarget"
target.Value = Vector3.new(0, 200, 0)
target.Parent = workspace
print("SHOT placed ITEM")
""").replace("ITEM", item))
	elif phase >= 2 and phase < 2 + ANGLES.size() * 2:
		var i: int = (phase - 2) / 2
		var step_t := 14.5 + i * 2.5
		if (phase - 2) % 2 == 0 and t > step_t:
			_look(ANGLES[i][1], zoom)
			phase += 1
		elif (phase - 2) % 2 == 1 and t > step_t + 1.5:
			var img := get_root().get_texture().get_image()
			var file: String = shots.path_join("%s-%s.png" % [item.replace(" ", "_"), ANGLES[i][0]])
			img.save_png(file)
			print("  -> ", file)
			phase += 1
	elif phase == 2 + ANGLES.size() * 2:
		for line in said:
			if String(line).begins_with("SHOT "): print("  ", line)
		quit(0)
	return false
