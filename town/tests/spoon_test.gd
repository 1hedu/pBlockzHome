# The Spoonie swings on a click, alternates, and returns to its rest pose. The arm is driven
# through the shoulder Motor6D rather than by moving the part, so the hand and the spoon in it
# come along.
#
#   node scripts/stage-preview.js crudespoon <dir>
#   godot --headless --path . -s res://tests/spoon_test.gd -- <dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var said: Array[String] = []
var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

var t := 0.0
var phase := 0
var stage := ""
func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	# Past the intro gate: players are let in as they join (tests/Arrive.gd).
	Arrive.now(world)
	world.script_print.connect(func(n, x): said.append(str(x)))
	print("== spoon swing")
func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		var json := FileAccess.get_file_as_string(stage.path_join("crudespoon.json"))
		DirAccess.make_dir_recursive_absolute("user://preview")
		world.add_model("ReplicatedStorage/OnChain", "Spoonie", json)
		world.run_chunk("wear", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local src = rs:WaitForChild("OnChain", 2):FindFirstChild("Spoonie")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = src:Clone(); c.Parent = ch; hum:AddAccessory(c)
print("worn " .. tostring(c.Name))
local torso = ch:FindFirstChild("Torso")
local j = torso and torso:FindFirstChild("Right Shoulder")
print("joint " .. tostring(j and j.ClassName or "MISSING"))
""")
	elif phase == 1 and t > 5.0:
		phase = 2
		world.run_client_chunk("swing", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remote = rs:WaitForChild("WeaponRemote", 3)
local ch = Players.LocalPlayer.Character
local j = ch:FindFirstChild("Torso"):FindFirstChild("Right Shoulder")
local before = j.Transform
-- Transform, not C0, and the difference is the whole test. A limb is drawn at
-- Part0 * C0 * Transform * C1^-1, and the renderer only takes that chain over when some
-- Transform up it is not the identity -- C0 can be swung through a full arc, read back
-- changed, and pose nothing. So what is checked is that the property the renderer watches
-- is the one being written.
--
-- Reading the spoon's Position would not settle it either way: limbs are posed on their
-- meshes, not their part data, so a correctly swinging arm reports the same Position from
-- the first frame to the last. Only a screenshot can show the arc; tests/swing_shot.gd
-- takes one.
task.spawn(function()
    for i = 1, 2 do
        remote:FireServer()
        task.wait(0.15)
        local moved = (j.Transform.Position - before.Position).Magnitude
            + math.abs(j.Transform.LookVector:Dot(before.LookVector) - 1)
        print(("swing %d: joint moved %.4f"):format(i, moved))
        print(("swing %d: drives %s"):format(i, tostring(j.Transform ~= CFrame.new())))
        task.wait(0.95)
    end
    print(("rest: %s"):format(tostring(j.Transform == before)))
end)
""")
	elif phase == 2 and t > 9.5:
		var all := " ".join(said)
		check(all.contains("joint Motor6D"), "the arm hangs off a shoulder joint the swing can drive")
		check(all.contains("weapons: slash"), "the first click slashes")
		check(all.contains("weapons: thrust"), "and the second thrusts, alternating")
		var moved := false
		var carried := false
		for line in said:
			if line.begins_with("swing ") and line.contains("joint moved "):
				if line.split("joint moved ")[1].to_float() > 0.05:
					moved = true
			# driven() in pulseblockz_world.cpp poses a limb from its joints only while some Transform
			# up the chain is not the identity; a swing written to C0 leaves Transform identity.
			if line.begins_with("swing ") and line.contains("drives true"):
				carried = true
		check(moved, "the shoulder actually moves mid-swing")
		check(carried, "through Transform, the property that actually poses the limb, not C0")
		check(all.contains("rest: true"), "and returns to its rest pose, rather than staying mid-slash")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
	return false
