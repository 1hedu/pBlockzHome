# Duelling on and off: the Fights flag every client reads, the hearts meter and the action bar.
#
#   godot --path . -s res://tests/pvp_test.gd -- <shots dir>
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	var w := FileAccess.open("user://preview/heart.png", FileAccess.WRITE)
	if w:
		w.store_buffer(FileAccess.get_file_as_bytes("res://../../../scripts/models/heart.png"))
		w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# Without this the title ScreenGui covers the window and is what gets photographed.
	main.show_title = false
	root.add_child(main)
	# Skip the intro gate, so players spawn as they join (tests/Arrive.gd).
	Arrive.now(world)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		t = 0.0
		world.run_chunk("assets", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
if not place:FindFirstChild("HeartIcon") then
	local v = Instance.new("StringValue")
	v.Name = "HeartIcon"
	v.Value = "user://preview/heart.png"
	v.Parent = place
end
""")
	elif phase == 1 and t > 3.0:
		phase = 2
		t = 0.0
		world.run_chunk("pvp", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("PVP %-40s %-6s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end

local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
-- The town's own default, asked of somebody the chain has not spoken about.
--
-- Not of the player: the Funmaster reads fighting(address) off the Duelling contract a
-- second into every start and applies the answer, so what the signed-in wallet is set to on
-- chain decides this -- and the wallet these tests run as has duelling turned OFF. That is a
-- fact about an account, not about the town, and a test that asserts it fails for whoever
-- has opted out and passes for everyone else.
check("the town's default, before the chain says otherwise", Health.fights("nobody"), true)

-- And then the state this test needs, set rather than assumed.
Health.setFights(player, true)
check("duelling can be turned on", Health.fights(player), true)

-- The hearts over the head are not the server's any more: each client draws the players it
-- can see, so there is nothing in this tree to look at and no client here to look from.
-- overhead_test.gd is where that lives, and it needs a real client to say anything at all.
--
-- What the server still owes is the flag those clients read. That is the half of the feature
-- this test can honestly hold: it is what the row appearing over a head hangs off.
task.wait(1.0)
check("and the flag every client reads says so", player:GetAttribute("Fights"), true)

-- A blow between two people who are both in. There is nobody else, so the player is both
-- ends of it -- which is refused for a different reason -- so this checks the gate itself.
check("a fight is allowed", Health.fights(player), true)

Health.setFights(player, false)
task.wait(0.6)
check("duelling off", Health.fights(player), false)
check("and the flag goes with it, so the rows come down", player:GetAttribute("Fights"), false)

-- Out of it, nothing anybody swings lands. The attacker is the same player, which is what
-- the gate reads: someone who has opted out cannot be hit and cannot hit either.
local before = hum.Health
Health.hit(player, player, 2, 0)
check("no blow lands while out of it", hum.Health, before)
Health.burn(player, player, 3, 5, "hex")
task.wait(0.4)
check("and no torch lights you", hum.Health, before)

Health.setFights(player, true)
task.wait(0.8)
check("back in", Health.fights(player), true)
check("and the flag is back up", player:GetAttribute("Fights"), true)

-- The void does not care about any of this.
Health.setFights(player, false)
Health.hit(player, nil, 1, 0)
check("a fall still hurts", hum.Health, before - 1)
Health.setFights(player, true)

print(("PVP done: %d right, %d wrong"):format(ok, bad))
""")
	elif phase == 2 and t > 8.0:
		phase = 3
		t = 0.0
		world.run_client_chunk("meter", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local hearts = gui:WaitForChild("Hearts", 10)
local Health = nil
print("HEARTS shown while in it: " .. tostring(hearts and hearts.Enabled) .. " (wanted true)")
""")
		world.run_client_chunk("bar", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local bar = gui:WaitForChild("ActionBar", 10)
print("BAR the bar is up: " .. tostring(bar ~= nil))
if bar then
	print("BAR it is a HUD, not a window: " .. tostring(bar:GetAttribute("Hud") == true))
	local n = 0
	for _, d in ipairs(bar:GetDescendants()) do
		if d:IsA("ImageButton") and d.Name:sub(1, 4) == "Slot" then n += 1 end
	end
	print("BAR slots: " .. tostring(n) .. " (wanted 10)")
end
""")
	elif phase == 3 and t > 2.0:
		phase = 4
		t = 0.0
		world.run_chunk("out", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
Health.setFights(Players:GetPlayers()[1], false)
""")
	elif phase == 4 and t > 2.0:
		phase = 5
		t = 0.0
		world.run_client_chunk("meter2", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local hearts = gui:FindFirstChild("Hearts")
print("HEARTS gone while out of it: " .. tostring(hearts and not hearts.Enabled) .. " (wanted true)")
""")
	elif phase == 5 and t > 2.0:
		get_root().get_texture().get_image().save_png(shots.path_join("pvp.png"))
		print("  -> pvp.png")
		quit(0)
	return false
