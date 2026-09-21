# Prints every Accoutrement on the live character with the attachment its Handle hangs from,
# which is what says whether a multi-piece item landed on the right limbs. Reads the real
# chain, so it is not part of the offline suite.
#
#   godot --headless --path . -s res://tests/worn_live.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	root.add_child(main)
	world.script_print.connect(func(n, txt): print("    [%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): print("    ERROR [%s] %s" % [n, e]))
	print("== what is being worn")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 75.0:
		phase = 1
		world.run_chunk("dump", """
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local character = player and player.Character
if not character then print("no character") return end
for _, child in ipairs(character:GetChildren()) do
    if child:IsA("Accoutrement") then
        local handle = child:FindFirstChild("Handle")
        local at = "?"
        if handle then
            for _, a in ipairs(handle:GetChildren()) do
                if a:IsA("Attachment") then at = a.Name break end
            end
        end
        print(("WORN %-22s -> %s"):format(child.Name, at))
    end
end
""")
	elif phase == 1 and t > 78.0:
		quit(0)
	return false
