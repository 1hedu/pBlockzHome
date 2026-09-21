# A contact sheet of the cane's cast: the arm going up, the lunge, and the orb leaving.
#
#   node scripts/stage-preview.js cane <dir>
#   godot --path . -s res://tests/cast_shot.gd -- <dir> <shots dir> [front] [hold=<seconds>]
#
# No --headless: the dummy renderer draws nothing to photograph. `front` puts the lens out along
# the orb's path looking back at him; `hold` is seconds of charge, six being full.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const StandIns = preload("res://tests/StandIns.gd")

const COLS := 4
const ROWS := 3
const STRIDE := 4          # ~67ms apart at 60fps

var world: PulseBlockzWorld
var stage := ""
var shots := ""
var phase := 0
var t := 0.0
var tick := 0
var frames: Array[Image] = []
var front := false
var hold := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1]
	front = args.has("front")
	for a in args:
		if a.begins_with("hold="): hold = float(a.substr(5))
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in dir.get_files():
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	StandIns.stage("castshot")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)
	# Nobody here to click through the intro, so the player is admitted on join.
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	tick += 1
	if phase == 0 and t > 6.0:
		phase = 1; t = 0.0
		world.run_chunk("standins", StandIns.chunk("castshot"))
		var json := FileAccess.get_file_as_string(stage.path_join("cane.json"))
		world.add_model("ReplicatedStorage/OnChain", "Cane", json.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("wear", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local c = game:GetService("ReplicatedStorage").OnChain:FindFirstChild("Cane"):Clone()
c.Parent = ch
ch:FindFirstChildOfClass("Humanoid"):AddAccessory(c)
local root = ch:FindFirstChild("HumanoidRootPart")
-- Facing out of the square, where there is open ground for the orb to fly over.
root.CFrame = CFrame.new(Vector3.new(0, root.Position.Y, 58), Vector3.new(0, root.Position.Y, 120))
""")
	elif phase == 1 and t > 2.0:
		phase = 2; t = 0.0
		# Lens out to his right, aimed ahead of him: the orb stays in frame for several cells.
		world.run_client_chunk("aim", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:FindFirstChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BillboardGui") then d.Enabled = false end
end
local root = Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
local ahead = root.Position + root.CFrame.LookVector * 4 + Vector3.new(0, 0.5, 0)
if FRONT then
	cam.CFrame = CFrame.lookAt(root.Position + root.CFrame.LookVector * 16 + root.CFrame.RightVector * 2.2 + Vector3.new(0, 1.2, 0), root.Position + root.CFrame.LookVector * 5 + Vector3.new(0, 0.4, 0))
else
	cam.CFrame = CFrame.lookAt(root.Position + root.CFrame.RightVector * 11 + root.CFrame.LookVector * 1 + Vector3.new(0, 1.5, 0), ahead)
end
cam.FieldOfView = 60
""".replace("FRONT", "true" if front else "false"))
	elif phase == 2 and t > 1.5:
		phase = 3; t = 0.0
		world.run_client_chunk("click", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer()")
		if hold <= 0.0:
			_let_go()
			phase = 4
	# A fully charged cane strobes only while the button is still down, so past six seconds the
	# sheet opens 0.6s before the release instead of at the throwing click.
	elif phase == 3 and hold > 6.0 and t > hold - 0.6 and frames.is_empty():
		frames.append(get_root().get_texture().get_image())
	elif phase == 3 and hold > 6.0 and not frames.is_empty() and t <= hold:
		if tick % STRIDE == 0: frames.append(get_root().get_texture().get_image())
	elif phase == 3 and t > hold:
		# Letting go keeps the charge; the click after it throws it.
		phase = 5; t = 0.0
		_let_go()
	elif phase == 5 and t > 0.8:
		phase = 4; t = 0.0
		world.run_client_chunk("click", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer()")
		_let_go()
	elif phase == 4:
		if tick % STRIDE == 0 and frames.size() < COLS * ROWS:
			frames.append(get_root().get_texture().get_image())
		if frames.size() >= COLS * ROWS:
			var cw: int = int(frames[0].get_width() / 3.0)
			var ch: int = int(frames[0].get_height() / 3.0)
			var sheet := Image.create(cw * COLS, ch * ROWS, false, Image.FORMAT_RGBA8)
			for i in frames.size():
				var f: Image = frames[i].duplicate()
				f.resize(cw, ch, Image.INTERPOLATE_BILINEAR)
				f.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(f, Rect2i(0, 0, cw, ch), Vector2i((i % COLS) * cw, (i / COLS) * ch))
			var out := shots.path_join(("cast-front" if front else "cast") + ("-hold%d" % int(hold) if hold > 0.0 else "") + ".png")
			sheet.save_png(out)
			print("  -> ", out)
			quit(0)
	return false

func _let_go() -> void:
	world.run_client_chunk("release", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer('release')")
