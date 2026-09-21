# How far under the HumanoidRootPart the character's feet are: the lowest point of any of its
# parts, against the root.
#
#   godot --path . -s res://tests/foot_probe.gd -- <stage dir>
#
# Pets are placed at root minus a constant; this measures what that constant should be.
extends SceneTree
var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		world.run_chunk("feet", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root = ch:WaitForChild("HumanoidRootPart")
for i = 1, 4 do
	local low, name = math.huge, "?"
	for _, d in ipairs(ch:GetDescendants()) do
		if d:IsA("BasePart") then
			local b = d.Position.Y - d.Size.Y / 2
			if b < low then low, name = b, d.Name end
		end
	end
	print(("FEET root.y %.3f  lowest %s at %.3f  -> feet are %.3f under the root"):format(
		root.Position.Y, name, low, root.Position.Y - low))
	task.wait(0.7)
end
""")
		t = 0.0
	elif phase == 1 and t > 4.0:
		quit(0)
	return false
