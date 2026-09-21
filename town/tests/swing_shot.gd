# Wears the staged item, fires the real WeaponRemote and lays the swing out frame by frame as a
# contact sheet; tests/shoot.gd is the sibling for an item held still, this one for an item that
# is only itself in motion. `hitbox` adds the town's /hitbox draw -- the body ball and the
# capsule a stroke cuts. Needs a real renderer: headless captures nothing.
#
#   node scripts/stage-preview.js crudespoon <dir>
#   godot --path . -s res://tests/swing_shot.gd -- <dir> <shots dir> [angle] [hitbox]
extends SceneTree

const COLS := 4
const ROWS := 2
const KEEP := COLS * ROWS
const STRIDE := 6          # ~100ms apart at 60fps, so eight cells span the longer cut

var world: PulseBlockzWorld
var stage := ""
var hitbox := false
var shots := ""
var spin := 40.0
var phase := 0
var t := 0.0
var tick := 0
var frames: Array[Image] = []
var kind := ""
var key := ""        # which staged item to wear
var inst := ""       # the name it gives itself, which is what add_model uses

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: godot --path . -s res://tests/swing_shot.gd -- <staged> <shots> [angle]")
		quit(1)
		return
	stage = args[0]
	shots = args[1]
	spin = float(args[2]) if args.size() > 2 else 40.0
	hitbox = args.size() > 3 and args[3] == "hitbox"
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in dir.get_files():
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	# Whatever stage-preview.js staged, rather than a hard-coded item
	var manifest: Array = JSON.parse_string(
		FileAccess.get_file_as_string(stage.path_join("manifest.json")))
	key = manifest[0].key
	inst = manifest[0].get("instance", key)
	print("== swinging %s" % inst)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false   # the title card waits for a click nobody gives
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_print.connect(func(_n, x): print("[lua] ", x))
	print("== swing sheet")

func _wear() -> void:
	var json := FileAccess.get_file_as_string(stage.path_join("%s.json" % key))
	json = json.replace(stage.replace("\\", "/") + "/", "user://preview/")
	world.add_model("ReplicatedStorage/OnChain", inst, json)
	world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("%s")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = src:Clone(); c.Parent = ch; hum:AddAccessory(c)
local root = ch:FindFirstChild("HumanoidRootPart")
root.CFrame = CFrame.new(Vector3.new(0, root.Position.Y, 58), Vector3.new(0, root.Position.Y, 0))
if %s then workspace:SetAttribute("ShowHitboxes", true) end
print("worn")
""" % [inst, "true" if hitbox else "false"])

func _hide_and_aim() -> void:
	world.run_client_chunk("aim", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
    if s:IsA("ScreenGui") then s.Enabled = false end
end
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("BillboardGui") then d.Enabled = false end
end
local cam = workspace.CurrentCamera
local ch = Players.LocalPlayer.Character
local root = ch:FindFirstChild("HumanoidRootPart")
cam.CameraType = Enum.CameraType.Scriptable
local at = root.Position + Vector3.new(0, 0.6, 0)
local dir = (CFrame.Angles(0, math.rad(%f), 0) * root.CFrame.LookVector)
cam.CFrame = CFrame.new(at + (dir * 5.5), at)
print("aimed")
""" % spin)

## Prints the weapon head's world position and the shoulder joint's tilt every frame for 2.2 s,
## which tells a swing the render ignored from one that never ran.
func _watch() -> void:
	world.run_client_chunk("watch", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ch = Players.LocalPlayer.Character
local bowl
for _, a in ipairs(ch:GetChildren()) do
    if a:IsA("Accoutrement") then bowl = a:FindFirstChild("Bowl") or a:FindFirstChild("Handle") end
end
local j = ch:FindFirstChild("Torso"):FindFirstChild("Right Shoulder")
if not bowl or not j then print("watch: missing") return end
local t0 = os.clock()
local conn
conn = RunService.RenderStepped:Connect(function()
    if os.clock() - t0 > 2.2 then conn:Disconnect() return end
    local p = bowl.Position
    print(("bowl %.3f %.2f,%.2f,%.2f  c0 %.3f"):format(
        os.clock() - t0, p.X, p.Y, p.Z, j.Transform.UpVector:Dot(Vector3.new(0, 1, 0))))
end)
""")

func _fire() -> void:
	world.run_client_chunk("fire", """
local rs = game:GetService("ReplicatedStorage")
rs:WaitForChild("WeaponRemote", 3):FireServer()
""")

## Drops the frames captured before the arm moved: the remote is queued rather than fired on the
## spot, so a capture opens on the character standing still. The start is the first frame that
## differs from the resting one, rather than a guessed latency.
func _trim(all: Array[Image]) -> Array[Image]:
	if all.is_empty():
		return all
	var rest := all[0].duplicate()
	rest.resize(96, 54, Image.INTERPOLATE_BILINEAR)
	var rd: PackedByteArray = rest.get_data()
	var start := 0
	for i in range(1, all.size()):
		var c := all[i].duplicate()
		c.resize(96, 54, Image.INTERPOLATE_BILINEAR)
		var cd: PackedByteArray = c.get_data()
		var diff := 0.0
		for b in range(0, rd.size(), 7):
			diff += abs(int(cd[b]) - int(rd[b]))
		diff /= float(rd.size() / 7)
		if diff > 1.5:
			start = max(0, i - 1)
			break
	print("  swing starts at captured frame %d of %d" % [start, all.size()])
	return all.slice(start, start + KEEP)

func _sheet(all: Array[Image], out: String) -> void:
	var picked := _trim(all)
	if picked.is_empty():
		printerr("nothing captured")
		return
	var cw: int = int(picked[0].get_width() / float(COLS))
	var ch: int = int(picked[0].get_height() / float(COLS))
	var sheet := Image.create(cw * COLS, ch * ROWS, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.07, 0.08, 0.11))
	for i in picked.size():
		var f: Image = picked[i].duplicate()
		f.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
		f.convert(Image.FORMAT_RGBA8)
		sheet.blit_rect(f, Rect2i(0, 0, cw, ch), Vector2i((i % COLS) * cw, (i / COLS) * ch))
	sheet.save_png(out)
	print("  %s  (%d frames, left to right, top to bottom)" % [out, picked.size()])

func _process(delta: float) -> bool:
	t += delta
	tick += 1
	if phase == 0 and t > 3.0:
		phase = 1
		_wear()
		t = 0.0
	elif phase == 1 and t > 1.5:
		phase = 2
		_hide_and_aim()
		t = 0.0
	elif phase == 2 and t > 1.5:
		phase = 3
		kind = "slash"
		frames = []
		_watch()
		_fire()
		t = 0.0
	elif phase == 3:
		if tick % STRIDE == 0 and frames.size() < 40:
			frames.append(get_root().get_texture().get_image())
		if t > 1.4:
			phase = 4
			_sheet(frames, shots.path_join("swing-slash.png"))
			frames = []
			kind = "thrust"
			_fire()
			t = 0.0
	elif phase == 4:
		if tick % STRIDE == 0 and frames.size() < 40:
			frames.append(get_root().get_texture().get_image())
		if t > 1.4:
			_sheet(frames, shots.path_join("swing-thrust.png"))
			print("done")
			quit(0)
			return true
	return false
