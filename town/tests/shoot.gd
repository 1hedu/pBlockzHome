# Wears each catalogue item on the character and saves the frame. Needs a real window:
# headless Godot draws with a dummy renderer, which shows nothing about how an item looks.
#
#   node scripts/stage-preview.js goldcoat,mariajacket <dir>
#   godot --path . -s res://tests/shoot.gd -- <dir> <shots dir>
#
# Staging resolves the model JSON's texture paths, so nothing has to be published first.
extends SceneTree

var world: PulseBlockzWorld
var main: Node
var items: Array = []
var at := 0
var stage := ""
var shots := ""
var phase := 0
var t := 0.0
var close_on := ""
var spin := 0.0        # degrees the lens orbits the subject; 0 is head-on
var dist := 2.4        # studs from the part in a close-up
var lift := 0.0        # studs above the aim point; a garment's top is invisible from eye level
var lit := false       # the place has reported itself up

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0] if args.size() > 0 else ""
	shots = args[1] if args.size() > 1 else stage
	close_on = args[2] if args.size() > 2 else ""
	spin = float(args[3]) if args.size() > 3 else 0.0
	dist = float(args[4]) if args.size() > 4 else 2.4
	lift = float(args[5]) if args.size() > 5 else 0.0
	if stage == "":
		printerr("usage: godot --path . -s res://tests/shoot.gd -- <staged dir> [shots dir]")
		quit(1)
		return
	var raw := FileAccess.get_file_as_string(stage.path_join("manifest.json"))
	items = JSON.parse_string(raw)
	DirAccess.make_dir_recursive_absolute(shots)
	_stage_files()
	main = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false      # no chain: everything comes off disk
	# The title card covers the world for the first several seconds, which is when the
	# shutter goes.
	main.show_title = false
	# The shot clock in _process starts from the place being up, not from launch.
	world.script_print.connect(func(_n, line):
		if line.begins_with("intro:"): lit = true)
	root.add_child(main)
	print("== photographing %d item(s)" % items.size())

## Copies the staged files into user://preview.
##
## Texture and mesh paths resolve against res://, user:// or the asset root; any other
## path gets the asset root pasted on the front and fails silently, leaving the garment
## its flat base colour.
func _stage_files() -> void:
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	if dir == null:
		printerr("cannot read ", stage)
		return
	for f in dir.get_files():
		var bytes := FileAccess.get_file_as_bytes(stage.path_join(f))
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(bytes)
			w.close()
	print("staged %d file(s) into user://preview" % dir.get_files().size())

## Wears one item by the wardrobe's own path: Humanoid:AddAccessory.
func _wear(entry: Dictionary) -> void:
	var json := FileAccess.get_file_as_string(stage.path_join("%s.json" % entry.key))
	json = json.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage/OnChain", String(entry.key), json)
	world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local folder = rs:WaitForChild("OnChain", 2)
local src = folder and folder:FindFirstChild("%s")
local player = Players:GetPlayers()[1]
local ch = player and player.Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
if not src or not hum then print("WEAR failed") return end
-- Take off whatever is on, so one photograph is one garment. Collected first and
-- destroyed after: removing entries from the list being walked skips every other one.
local old = {}
for _, d in ipairs(ch:GetChildren()) do
    if d:IsA("Accoutrement") then table.insert(old, d) end
end
for _, d in ipairs(old) do d:Destroy() end
local copy = src:Clone()
if copy:IsA("Accoutrement") then
    copy.Parent = ch
    hum:AddAccessory(copy)
else
    for _, c in ipairs(copy:GetChildren()) do
        if c:IsA("Accoutrement") then c.Parent = ch; hum:AddAccessory(c) end
    end
    copy:Destroy()
end
print("WEAR %s")
""" % [String(entry.get("instance", entry.key)), entry.key])

## Frames one worn part at `dist`, orbited by `spin`: a fixed angle leaves whatever is on
## the far side of a limb invisible. Angle 0 stands behind him -- he is placed facing -Z.
func _close(part_name: String) -> void:
	world.run_client_chunk("close", """
local Players = game:GetService("Players")
local cam = workspace.CurrentCamera
local ch = Players.LocalPlayer and Players.LocalPlayer.Character
if not cam or not ch then return end
local target
for _, acc in ipairs(ch:GetChildren()) do
    if acc:IsA("Accoutrement") then
        local p = acc:FindFirstChild("%s")
        if p then target = p break end
    end
end
if not target then print("CLOSE no part") return end
cam.CameraType = Enum.CameraType.Scriptable
local at = target.Position
local a = math.rad(%f)
local eye = at + Vector3.new(math.sin(a) * %f, %f * 0.3, math.cos(a) * %f)
cam.CFrame = CFrame.new(eye, at)
print(("CLOSE on %%s at %%.2f,%%.2f,%%.2f"):format(target.Name, at.X, at.Y, at.Z))
""" % [part_name, spin, dist, dist, dist])

## Full-body shot `back` studs from the root, aimed `height` studs above it, orbited by
## `spin`: head-on, anything held out in front comes down the barrel and reads as a dot.
func _aim(back: float, height: float) -> void:
	world.run_client_chunk("aim", """
local Players = game:GetService("Players")
local cam = workspace.CurrentCamera
local ch = Players.LocalPlayer and Players.LocalPlayer.Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if not cam or not root then print("AIM not ready") return end
cam.CameraType = Enum.CameraType.Scriptable
local at = root.Position + Vector3.new(0, %f, 0)
local dir = (CFrame.Angles(0, math.rad(%f), 0) * root.CFrame.LookVector)
local eye = at + (dir * %f) + Vector3.new(0, %f, 0)
cam.CFrame = CFrame.new(eye, at)
print(("AIM at %%.1f,%%.1f,%%.1f eye %%.1f"):format(at.X, at.Y, at.Z, eye.Y))
""" % [height, spin, back, lift])

## Hides the chat bar and the wallet panel, both ScreenGuis over the whole frame.
func _hide_ui() -> void:
	world.run_client_chunk("hideui", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if not gui then return end
for _, s in ipairs(gui:GetChildren()) do
    if s:IsA("ScreenGui") then s.Enabled = false end
end
-- And the world's own signage: every NPC name tag and notice board is a BillboardGui
-- drawn on top of everything, so from any distance they sit across the subject.
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("BillboardGui") then d.Enabled = false end
end
""")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 1.0:
		phase = 1
		_hide_ui()
		# South out of the square, once, before any shot: the client needs the move
		# replicated before the camera reads his position. His own Y is kept -- at a
		# chosen height he is falling until the anchor lands.
		world.run_chunk("place", """
local Players = game:GetService("Players")
local ch = Players:GetPlayers()[1] and Players:GetPlayers()[1].Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if not root then return end
root.CFrame = CFrame.new(Vector3.new(0, root.Position.Y, 58), Vector3.new(0, root.Position.Y, 0))
print("PLACE ok")
""")
	elif phase == 1 and t > 6.0:
		phase = 2
		if at >= items.size():
			print("done: %d shot(s) in %s" % [items.size(), shots])
			quit(0)
			return true
		_wear(items[at])
		t = 0.0
		phase = 2
	# Chunks are queued, not run on the spot: aiming needs its own phase after the garment
	# is on and before the shutter.
	elif phase == 2 and t > 1.2:
		phase = 3
		if close_on != "":
			_close(close_on)
		else:
			_aim(6.0, -0.3)
		t = 0.0
	elif phase == 3 and t > 1.2:
		phase = 4
		var img := get_root().get_texture().get_image()
		var file: String = shots.path_join("%s.png" % items[at].key)
		img.save_png(file)
		print("  %s -> %s" % [String(items[at].name), file])
		at += 1
		t = 6.1
		phase = 1
	return false
