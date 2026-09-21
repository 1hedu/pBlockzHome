# Photographs what /hitbox draws, frame by frame through one real swing: the ball a body
# counts for and the capsule a stroke cuts.
#
#   node scripts/stage-preview.js all .preview
#   godot --path . -s res://tests/hitbox_shot.gd -- <shots dir> [weapon[,more...]] [side|top|back|left]
#
# A weapon is named by its instance name ("Spoonie"), not its catalogue key. ShowHitboxes is
# the attribute the chat command sets, and the swing goes through WeaponRemote, so the ghosts
# drawn are the ones sweep() reads. Windowed: the headless renderer draws nothing.
# Angles: side for reach against the body, top for the arc and the width, back for the view the
# player has of it.
extends SceneTree

const Preview = preload("res://tests/Preview.gd")

var world: PulseBlockzWorld
var shots := ""
var weapon := "Spoonie"
var angle := "side"
var t := 0.0
var phase := 0
var swungAt := 0.0
var frame := 0
const FRAMES := [0.1, 0.2, 0.3, 0.4, 0.55, 0.7, 0.85, 1.0]   # a slash cuts inside 0.46 s; a hachimonji runs 1.05

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	weapon = args[1] if args.size() > 1 else "Spoonie"
	angle = args[2] if args.size() > 2 else "side"
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): if String(line).begins_with("SHOT ") or String(line).begins_with("weapons:"): print("  ", line))
	Preview.stage("hitbox", ProjectSettings.globalize_path("res://../../../.preview"))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 10.0:
		phase = 1
		Preview.install(world, "hitbox", ProjectSettings.globalize_path("res://../../../.preview"))
	elif phase == 1 and t > 13.0:
		phase = 2
		world.run_chunk("wear", ("""
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local ch = player and player.Character
if not ch then print("SHOT no character") return end
local hum = ch:FindFirstChildOfClass("Humanoid")
local onChain = rs:WaitForChild("OnChain", 2)
for name in string.gmatch("WEAPON", "[^,]+") do
	local src = onChain and onChain:FindFirstChild(name)
	if not src then print("SHOT no item " .. name) else
		-- An outfit is a Model of Accessories (a coat and its two cuffs); a single thing is one.
		local c = src:Clone()
		if c:IsA("Accessory") then c.Parent = ch; hum:AddAccessory(c)
		else for _, a in ipairs(c:GetChildren()) do if a:IsA("Accessory") then a.Parent = ch; hum:AddAccessory(a) end end end
	end
end
local root = ch:FindFirstChild("HumanoidRootPart")
root.CFrame = CFrame.new(Vector3.new(0, root.Position.Y, 58), Vector3.new(0, root.Position.Y, 0))
workspace:SetAttribute("ShowHitboxes", true)
print("SHOT wearing WEAPON, hitboxes on")
""").replace("WEAPON", weapon))
	elif phase == 2 and t > 16.0:
		phase = 3
		world.run_client_chunk("look", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do if s:IsA("ScreenGui") then s.Enabled = false end end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local root = Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
local c = root.Position
local from, at = Vector3.new(11, 3, -2), Vector3.new(0, -0.5, -2)
if "ANGLE" == "top" then from, at = Vector3.new(0.01, 16, -2), Vector3.new(0, 0, -2)
elseif "ANGLE" == "back" then from, at = Vector3.new(0, 6, 9), Vector3.new(0, 0, -3)
elseif "ANGLE" == "left" then from, at = Vector3.new(-6, -1, -5), Vector3.new(-1.5, 0.5, 0) end
cam.CFrame = CFrame.lookAt(c + from, c + at)
cam.FieldOfView = 50
""".replace("ANGLE", angle))
	elif phase == 3 and t > 17.0:
		phase = 4
		swungAt = t
		world.run_client_chunk("swing", """
local r = game:GetService("ReplicatedStorage"):FindFirstChild("WeaponRemote")
if r then r:FireServer() end
""")
	elif phase == 4:
		if frame < FRAMES.size() and t - swungAt >= FRAMES[frame]:
			var img := get_root().get_texture().get_image()
			var file: String = shots.path_join("%s-%s-%03d.png" % [weapon.replace(" ", "_").replace(",", "+"), angle, int(FRAMES[frame] * 1000)])
			img.save_png(file)
			print("  -> ", file)
			frame += 1
		elif frame >= FRAMES.size():
			quit(0)
	return false
