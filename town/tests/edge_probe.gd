# Whether the spoon leads with its edge or slaps with its flat.
#
#   node scripts/stage-preview.js spoonie <dir>
#   godot --headless --path . -s res://tests/edge_probe.gd -- <dir>
#
# The spoon is a flat paddle: its width axis runs across the bowl, its thin axis is the flat.
# Sampled every frame, the angle between the width axis and the head's travel is near 0 for a
# cut and near 90 for a slap. The pose is rebuilt from the live joint the way the renderer does
# it, Part1 = Part0 * C0 * Transform * C1^-1, so nothing here re-implements the animation.
extends SceneTree

var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0
var samples: Array = []

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in dir.get_files():
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_print.connect(_heard)

func _heard(_n, line) -> void:
	var s := str(line)
	if s.begins_with("edge "):
		var b := s.split(" ")
		var row := []
		for i in range(1, b.size()):
			row.append(float(b[i]))
		samples.append(row)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var json := FileAccess.get_file_as_string(stage.path_join("spoonie.json"))
		json = json.replace(stage.replace("\\", "/") + "/", "user://preview/")
		world.add_model("ReplicatedStorage/OnChain", "BFS 9000", json)
		world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("BFS 9000")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = src:Clone(); c.Parent = ch; hum:AddAccessory(c)
print("worn")
""")
	elif phase == 1 and t > 6.0:
		phase = 2
		world.run_client_chunk("probe", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local rs = game:GetService("ReplicatedStorage")
local ch = Players.LocalPlayer.Character
local arm = ch:FindFirstChild("Right Arm")
local torso = ch:FindFirstChild("Torso")
local j = torso:FindFirstChild("Right Shoulder")
local acc
for _, a in ipairs(ch:GetChildren()) do if a:IsA("Accoutrement") then acc = a end end
local shaft = acc and acc:FindFirstChild("Handle")
if not shaft then print("edge: no shaft") return end

-- The bowl's tip, in the arm's own frame, taken once while everything is still at rest.
-- Part positions never move -- limbs are posed on their meshes -- so this offset is fixed
-- and the whole swing can be reconstructed from the joint.
local mid = arm.CFrame:PointToObjectSpace(shaft.Position)
local tipLocal = mid - Vector3.new(0, 0, shaft.Size.Z / 2)

rs:WaitForChild("WeaponRemote", 3):FireServer()
local t0 = os.clock()
local conn
conn = RunService.RenderStepped:Connect(function()
    local e = os.clock() - t0
    if e > 1.1 then conn:Disconnect() return end
    local armCF = torso.CFrame * j.C0 * j.Transform * j.C1:Inverse()
    local tip = armCF:PointToWorldSpace(tipLocal)
    local width = armCF.UpVector          -- across the bowl: the cutting direction
    local side = armCF.RightVector        -- the flat's normal
    local shaft = armCF.LookVector        -- along the handle
    print(("edge %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f"):format(
        e, tip.X, tip.Y, tip.Z, width.X, width.Y, width.Z,
        side.X, side.Y, side.Z, shaft.X, shaft.Y, shaft.Z))
end)
""")
	elif phase == 2 and t > 8.6:
		_report()
		quit(0)
		return true
	return false

## Per stroke: how far off edge-first it is, and the roll of sx that would correct it.
func _report() -> void:
	print("== %d frames" % samples.size())
	if samples.size() < 8:
		printerr("nothing sampled")
		return
	# The two strokes as spans of the 0.82 s swing: keyframes 0.16->0.34 and 0.50->0.68.
	var windows := [[0.131, 0.279, "stroke 1 (down across to his left) "],
					[0.410, 0.558, "stroke 2 (down across to his right)"]]
	for w in windows:
		var edgeSum := 0.0
		var rollSum := 0.0
		var wt := 0.0
		for i in range(samples.size() - 1):
			var a: Array = samples[i]
			var b: Array = samples[i + 1]
			if a[0] < w[0] or a[0] > w[1]:
				continue
			var dt: float = b[0] - a[0]
			var travel := Vector3(b[1] - a[1], b[2] - a[2], b[3] - a[3])
			if dt < 0.004 or travel.length() < 1e-5:
				continue
			var speed := travel.length() / dt
			var width := Vector3(a[4], a[5], a[6])
			var side := Vector3(a[7], a[8], a[9])
			var shaft := Vector3(a[10], a[11], a[12])
			var dir := travel.normalized()
			# Only travel across the blade cuts: the along-the-shaft component comes out.
			var flat := (dir - shaft * dir.dot(shaft))
			if flat.length() < 1e-4:
				continue
			flat = flat.normalized()
			var edge := rad_to_deg(acos(clamp(abs(flat.dot(width)), 0.0, 1.0)))
			# The roll about the shaft that would put the width axis along the travel, signed.
			var roll := rad_to_deg(atan2(flat.dot(side), flat.dot(width)))
			if roll > 90.0:
				roll -= 180.0
			elif roll < -90.0:
				roll += 180.0
			edgeSum += edge * speed
			rollSum += roll * speed
			wt += speed
		if wt > 0:
			print("%s  off edge-first by %5.1f deg   roll sx by %+6.1f deg" % [w[2], edgeSum / wt, rollSum / wt])
