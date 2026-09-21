# Which way does the shoulder actually turn?
#
#   godot --headless --path . -s res://tests/joint_probe.gd -- <staged dir>
#
# The R6 Right Shoulder bakes a quarter-turn into its C0, so CFrame.Angles(x, y, z) on its
# Transform is not pitch, yaw and roll in the body's axes. Evaluates the renderer's own formula
# (Part1 = Part0 * C0 * Transform * C1^-1) for a turn about each axis and prints where the tip
# lands in the character's frame: +X his right, +Y up, -Z the way he faces.
extends SceneTree

var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_print.connect(func(_n, x): print(x))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var json := FileAccess.get_file_as_string(stage.path_join("crudespoon.json"))
		world.add_model("ReplicatedStorage/OnChain", "Spoonie", json)
		world.run_chunk("probe", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("Spoonie")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = src:Clone(); c.Parent = ch; hum:AddAccessory(c)

local torso = ch:FindFirstChild("Torso")
local arm = ch:FindFirstChild("Right Arm")
local j = torso:FindFirstChild("Right Shoulder")
local root = ch:FindFirstChild("HumanoidRootPart")

-- The spoon's tip in the arm's own space, from where the two sit at rest.
local tipLocal = arm.CFrame:PointToObjectSpace(Vector3.new(arm.Position.X, 2.98, arm.Position.Z - 1.42))

local function place(T)
    local armCF = torso.CFrame * j.C0 * T * j.C1:Inverse()
    local tip = armCF:PointToWorldSpace(tipLocal)
    return root.CFrame:PointToObjectSpace(tip), armCF
end

local rest = place(CFrame.new())
print(("rest tip  right %+.2f  up %+.2f  fwd %+.2f"):format(rest.X, rest.Y, -rest.Z))
for _, probe in ipairs({
    {"Angles(+60,0,0)", CFrame.Angles(math.rad(60), 0, 0)},
    {"Angles(-60,0,0)", CFrame.Angles(math.rad(-60), 0, 0)},
    {"Angles(0,+60,0)", CFrame.Angles(0, math.rad(60), 0)},
    {"Angles(0,-60,0)", CFrame.Angles(0, math.rad(-60), 0)},
    {"Angles(0,0,+60)", CFrame.Angles(0, 0, math.rad(60))},
    {"Angles(0,0,-60)", CFrame.Angles(0, 0, math.rad(-60))},
}) do
    local p = place(probe[2])
    print(("%-16s tip right %+.2f  up %+.2f  fwd %+.2f   (moved right %+.2f up %+.2f fwd %+.2f)")
        :format(probe[1], p.X, p.Y, -p.Z, p.X - rest.X, p.Y - rest.Y, -(p.Z - rest.Z)))
end

-- The left shoulder, whose C0 carries the mirror of the right one's baked quarter-turn --
-- so the same Angles(x, y, z) means something different on each side, and a carry pose
-- written for one arm and negated for the other lands nowhere near it. Reported as where
-- the left hand ends up, since that is the thing that has to reach the shaft.
local lj = torso:FindFirstChild("Left Shoulder")
local larm = ch:FindFirstChild("Left Arm")
if lj and larm then
    local function hand(T)
        local armCF = torso.CFrame * lj.C0 * T * lj.C1:Inverse()
        return root.CFrame:PointToObjectSpace(armCF:PointToWorldSpace(Vector3.new(0, -1, 0)))
    end
    local h0 = hand(CFrame.new())
    print(("Lhand rest  right %+.2f  up %+.2f  fwd %+.2f"):format(h0.X, h0.Y, -h0.Z))
    for _, probe in ipairs({
        {"L Angles(+60,0,0)", CFrame.Angles(math.rad(60), 0, 0)},
        {"L Angles(0,+60,0)", CFrame.Angles(0, math.rad(60), 0)},
        {"L Angles(0,0,+60)", CFrame.Angles(0, 0, math.rad(60))},
        {"L Angles(0,0,-60)", CFrame.Angles(0, 0, math.rad(-60))},
    }) do
        local h = hand(probe[2])
        print(("%-18s hand moved right %+.2f up %+.2f fwd %+.2f")
            :format(probe[1], h.X - h0.X, h.Y - h0.Y, -(h.Z - h0.Z)))
    end
end

-- And the waist, which is what carries the body into a swing. RootJoint's Part1 is the
-- Torso, so the shoulder hangs below it and the tip moves through both.
local rj = root:FindFirstChild("RootJoint")
local function waist(T)
    local torsoCF = root.CFrame * rj.C0 * T * rj.C1:Inverse()
    local armCF = torsoCF * j.C0 * j.C1:Inverse()
    return root.CFrame:PointToObjectSpace(armCF:PointToWorldSpace(tipLocal))
end
local w0 = waist(CFrame.new())
print(("waist rest  right %+.2f  up %+.2f  fwd %+.2f"):format(w0.X, w0.Y, -w0.Z))
for _, probe in ipairs({
    {"root Angles(+40,0,0)", CFrame.Angles(math.rad(40), 0, 0)},
    {"root Angles(0,+40,0)", CFrame.Angles(0, math.rad(40), 0)},
    {"root Angles(0,0,+40)", CFrame.Angles(0, 0, math.rad(40))},
}) do
    local p = waist(probe[2])
    print(("%-21s tip moved right %+.2f up %+.2f fwd %+.2f")
        :format(probe[1], p.X - w0.X, p.Y - w0.Y, -(p.Z - w0.Z)))
end
""")
	elif phase == 1 and t > 6.5:
		quit(0)
		return true
	return false
