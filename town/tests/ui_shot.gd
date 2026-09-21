# Photographs the shop shelf, fed fabricated stock, to <shots dir>/ui.png.
#
#   godot --path . -s res://tests/ui_shot.gd -- <font.ttf> <shots dir>
#
# Not headless: the dummy renderer draws nothing.
extends SceneTree

var world: PulseBlockzWorld
var src := ""
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	src = args[0] if args.size() > 0 else ""
	shots = args[1] if args.size() > 1 else "."
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	# On, unlike the other tests: the font and the sounds are published assets and have to come
	# off the chain rather than out of a local file.
	main.get_node("Wallet").auto_start = true
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 16.0:
		phase = 1
		# Every other ScreenGui off, so the shot is of the panel the town itself draws.
		world.run_client_chunk("hide", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
    if s:IsA("ScreenGui") and s.Name ~= "ShopShelf" then s.Enabled = false end
end
local rs = game:GetService("ReplicatedStorage")
local pa = rs:FindFirstChild("PlaceAssets")
print(("PLACEASSETS %s"):format(pa and "present" or "MISSING"))
if pa then
    for _, v in ipairs(pa:GetChildren()) do print(("  %s = %s"):format(v.Name, v.Value)) end
end
""")
		t = 0.0
	elif phase == 1 and t > 1.2:
		phase = 2
		world.run_chunk("shelf", """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remote = ReplicatedStorage:WaitForChild("ShopRemote")
local player = Players:GetPlayers()[1]
-- Stand at the stall first. The shelf closes itself the moment you are more than a few
-- studs from the shopkeeper, and since the shops moved out to the rim that is the whole
-- rest of the map -- the panel opened and shut again in the same frame.
local map = workspace:FindFirstChild("Map")
local npc = map and map:FindFirstChild("Shopkeeper")
local torso = npc and npc:FindFirstChild("Torso")
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
if torso and root then root.CFrame = CFrame.new(torso.Position + Vector3.new(4, 0, 0)) end
local items = {}
local stock = {
    {"Gold Glitter Suit Coat", "28", "chest", 4, false, false},
    {"Maria Glitter Jacket", "28", "chest", 4, false, false},
    {"BFS 9000", "34", "mainhand", 5, false, false},
    {"Spoonie", "24", "mainhand", 2, true, false},
    {"Rainbow Diamond Rolex", "250", "wrist", 9, false, true},
    {"Top Hat", "12", "head", 1, false, false},
    {"Maria Wig", "38", "head", 6, false, false},
    {"Familiar", "28", "pet", 4, false, false},
}
for i, r in ipairs(stock) do
    table.insert(items, { id = i, name = r[1], price = r[2], symbol = "mUSD",
        slot = r[3], tier = r[4], owned = r[5], locked = r[6], thumb = "" })
end
remote:FireClient(player, "shelf", {
    holder = { name = "Ada", next = "Rare", needed = "20" },
    tokens = { { balance = "1200", symbol = "mUSD" }, { balance = "16.3", symbol = "PLS" } },
    items = items,
})
print("SHELF sent")
""")
		t = 0.0
		world.run_chunk("shelf", """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local remote = ReplicatedStorage:WaitForChild("ShopRemote")
local player = Players:GetPlayers()[1]
local items = {}
local stock = {
    {"Gold Glitter Suit Coat", "28", "chest", 4, false, false},
    {"Maria Glitter Jacket", "28", "chest", 4, false, false},
    {"BFS 9000", "34", "mainhand", 5, false, false},
    {"Spoonie", "24", "mainhand", 2, true, false},
    {"Rainbow Diamond Rolex", "250", "wrist", 9, false, true},
    {"Top Hat", "12", "head", 1, false, false},
    {"Maria Wig", "38", "head", 6, false, false},
    {"Familiar", "28", "pet", 4, false, false},
}
for i, r in ipairs(stock) do
    table.insert(items, { id = i, name = r[1], price = r[2], symbol = "mUSD",
        slot = r[3], tier = r[4], owned = r[5], locked = r[6], thumb = "" })
end
remote:FireClient(player, "shelf", {
    holder = { name = "Ada", next = "Rare", needed = "20" },
    tokens = { { balance = "1200", symbol = "mUSD" }, { balance = "16.3", symbol = "PLS" } },
    items = items,
})
print("SHELF sent")
""")
		t = 0.0
	elif phase == 2 and t > 1.0:
		phase = 3
		world.run_client_chunk("probe", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
    if s:IsA("ScreenGui") then
        local kids = 0
        for _, k in ipairs(s:GetChildren()) do kids += 1 end
        print(("GUI %s enabled=%s kids=%d"):format(s.Name, tostring(s.Enabled), kids))
    end
end
local shelf = gui:FindFirstChild("ShopShelf")
if shelf then
    for _, k in ipairs(shelf:GetChildren()) do
        print(("  child %s %s abs=%s size=%s"):format(k.Name, k.ClassName,
            tostring(k:IsA("GuiObject") and k.AbsolutePosition or "-"),
            tostring(k:IsA("GuiObject") and k.AbsoluteSize or "-")))
    end
end
""")
		t = 0.0
	elif phase == 3 and t > 1.2:
		var img := get_root().get_texture().get_image()
		img.save_png(shots.path_join("ui.png"))
		print("wrote ", shots.path_join("ui.png"))
		quit(0)
		return true
	return false
