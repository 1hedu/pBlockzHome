# Which control is on top of the shop's Buy button.
#
#   godot --path . -s res://tests/hit_test.gd
#
# A click goes to the last control in tree order whose rect covers the point and that does not
# ignore the mouse, so every GuiObject covering the button's centre is listed in that order.
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var lines: Array[String] = []

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.script_print.connect(func(_n, line): lines.append(String(line)))
	main.show_title = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 24.0:
		phase = 1
		world.run_chunk("stand", """
local Players = game:GetService("Players")
local map = workspace:FindFirstChild("Map")
local who = map and map:FindFirstChild("Shopkeeper")
local torso = who and who:FindFirstChild("Torso")
local ch = Players:GetPlayers()[1] and Players:GetPlayers()[1].Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if root and torso then root.CFrame = CFrame.new(torso.Position + Vector3.new(0, 0, 5)) end
""")
		t = 0.0
	elif phase == 1 and t > 1.5:
		phase = 2
		# FireServer is the client's call: from a server chunk it does nothing.
		world.run_client_chunk("ask", """
game:GetService("ReplicatedStorage"):WaitForChild("ShopRemote"):FireServer("shop")
print("ASKED")
""")
		t = 0.0
	elif phase == 2 and t > 2.5:
		phase = 3
		world.run_client_chunk("hit", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local shelf = gui:FindFirstChild("ShopShelf")
if not shelf then print("HIT no shop") return end

-- Any button on the shelf will do.
local target
for _, d in ipairs(shelf:GetDescendants()) do
    if d:IsA("TextButton") and (d.Text == "Buy" or d.Text == "Close") then target = d break end
end
if not target then print("HIT no button") return end
local c = target.AbsolutePosition + target.AbsoluteSize / 2
print(("HIT probing %s at %.0f,%.0f"):format(target.Text, c.X, c.Y))

-- Everything whose rectangle covers that point, in tree order.
local n = 0
local function walk(inst, depth)
    for _, d in ipairs(inst:GetChildren()) do
        if d:IsA("GuiObject") and d.Visible then
            local p, s = d.AbsolutePosition, d.AbsoluteSize
            if c.X >= p.X and c.X <= p.X + s.X and c.Y >= p.Y and c.Y <= p.Y + s.Y then
                n += 1
                print(("  %2d %s%s  %s  %.0fx%.0f at %.0f,%.0f"):format(
                    n, string.rep("  ", depth), d.ClassName, d.Name, s.X, s.Y, p.X, p.Y))
            end
            walk(d, depth + 1)
        end
    end
end
for _, sg in ipairs(gui:GetChildren()) do
    if sg:IsA("ScreenGui") and sg.Enabled then
        print(("SCREEN %s"):format(sg.Name))
        walk(sg, 0)
    end
end
""")
		t = 0.0
	elif phase == 3 and t > 2.0:
		# The last line printed is the control a click would reach; it must be the button.
		var passed := 0
		var failed := 0
		var probed := false
		var last := ""
		for l in lines:
			if l.begins_with("HIT probing"): probed = true
			elif l.begins_with("HIT "): printerr("  FAIL ", l); failed += 1
			elif probed and l.strip_edges().length() > 3 and l.strip_edges()[0].is_valid_int(): last = l.strip_edges()
		if probed and last != "":
			var on_top := last.contains("TextButton")
			if on_top: passed += 1; print("  PASS the button is the topmost control under its own centre: ", last)
			else: failed += 1; printerr("  FAIL something covers the button: ", last)
		elif failed == 0:
			failed += 1; printerr("  FAIL nothing was probed")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
		return true
	return false
