# Photographs one of the town's panels. They are all ScreenGuis under PlayerGui, so rather than
# reproduce the key, prompt or chain reply that opens each, this enables the one asked for and
# hides the rest. Not headless, and the wallet runs: most panels are empty until the chain answers.
#
#   godot --path . -s res://tests/panel_shot.gd -- <ScreenGui name> <shots dir> [seconds]
extends SceneTree

var world: PulseBlockzWorld
var which := ""
var shots := ""
var wait_for := 18.0
var t := 0.0
var phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	which = args[0] if args.size() > 0 else ""
	shots = args[1] if args.size() > 1 else "."
	wait_for = float(args[2]) if args.size() > 2 else 18.0
	if which == "":
		printerr("usage: godot --path . -s res://tests/panel_shot.gd -- <ScreenGui> <shots> [secs]")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var main: Node = load("res://Main.tscn").instantiate()
	# Otherwise the shot catches the title card, depending on how the session's wallet starts.
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))   # a panel that stays empty usually says why here
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > wait_for:
		phase = 1
		# Stand at the NPC that owns the panel: most close themselves past sixteen studs, and
		# the shops sit on the rim, so anywhere else in the square is past it.
		var npc: String = {
			"PulseX": "Trader", "Screener": "Screener", "ShopShelf": "Shopkeeper",
			"PaintTable": "Tailor", "Explorer": "Archivist", "TownDialog": "Teller",
		}.get(which, "")
		if npc != "":
			world.run_chunk("stand", """
local Players = game:GetService("Players")
local map = workspace:FindFirstChild("Map")
local who = map and map:FindFirstChild("%s")
local torso = who and who:FindFirstChild("Torso")
local ch = Players:GetPlayers()[1] and Players:GetPlayers()[1].Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if root and torso then
    root.CFrame = CFrame.new(torso.Position + Vector3.new(0, 0, 5))
    print("STAND at %s")
end
""" % [npc, npc])
		t = 0.0
	elif phase == 1 and t > 1.2:
		phase = 2
		# Fill the panel the way its own dialog does, so the shot has the chain's real stock.
		if which == "TownDialog":
			world.run_chunk("talk", """
local rs = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
rs:WaitForChild("BankRemote"):FireClient(Players:GetPlayers()[1], "open", {
    title = "Rivet  <Wallet Services>", npc = "Teller",
    greeting = "Morning. Your holdings are read straight off the chain -- no account here.",
    menu = {
        { id = "holding", label = "What am I holding?" },
        { id = "items", label = "Show me my items" },
        { id = "address", label = "What's my address?" },
        { id = "send", label = "Send someone money" },
    },
})
print("TALKED")
""")
		if which == "ShopShelf":
			world.run_client_chunk("ask", """
local rs = game:GetService("ReplicatedStorage")
rs:WaitForChild("ShopRemote"):FireServer("shop")
print("ASKED for the shelf")
""")
		world.run_client_chunk("show", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local want = "%s"
local found = false
for _, s in ipairs(gui:GetChildren()) do
    if s:IsA("ScreenGui") then
        s.Enabled = (s.Name == want)
        if s.Name == want then found = true end
    end
end
for _, d in ipairs(workspace:GetDescendants()) do
    if d:IsA("BillboardGui") then d.Enabled = false end
end
print(("PANEL %%s %%s"):format(want, found and "shown" or "NOT FOUND"))
-- Every enabled panel's outer frame and the frame inside it, so anything covering the
-- whole screen and swallowing clicks is obvious at a glance.
for _, sg2 in ipairs(gui:GetChildren()) do
    if sg2:IsA("ScreenGui") and sg2.Enabled then
        for _, k in ipairs(sg2:GetChildren()) do
            if k:IsA("GuiObject") then
                print(("EXTENT %%s outer %%s"):format(sg2.Name, tostring(k.AbsoluteSize)))
                for _, k2 in ipairs(k:GetDescendants()) do
                    if k2:IsA("GuiObject") and k2.AbsoluteSize.X > 1100 then
                        print(("  COVERS %%s %%s"):format(k2.Name, tostring(k2.AbsoluteSize)))
                    end
                end
            end
        end
    end
end
-- Every panel's real extent, so an overlay covering the screen is obvious.
for _, s2 in ipairs(gui:GetChildren()) do
    if s2:IsA("ScreenGui") then
        for _, k in ipairs(s2:GetDescendants()) do
            if k:IsA("GuiObject") and k.Name == "Content" then
                print(("EXTENT %%s/%%s %%s"):format(s2.Name, k.Name, tostring(k.AbsoluteSize)))
            end
        end
    end
end
local sg = gui:FindFirstChild(want)
if sg then
    print(("  screengui abs %%s"):format(tostring(sg.AbsoluteSize)))
    for _, k in ipairs(sg:GetChildren()) do
        if k:IsA("GuiObject") then
            print(("  %%s pos %%s size %%s"):format(k.Name, tostring(k.AbsolutePosition), tostring(k.AbsoluteSize)))
        end
    end
end
local cam = workspace.CurrentCamera
print(("  camera viewport %%s"):format(tostring(cam and cam.ViewportSize)))
""" % which)
		t = 0.0
	elif phase == 2 and t > 1.5:
		var img := get_root().get_texture().get_image()
		var file: String = shots.path_join("panel-%s.png" % which.to_lower())
		img.save_png(file)
		print("wrote ", file)
		quit(0)
		return true
	return false
