# The intro: card, black, engine, town -- and that it waits for a cold world.
#
#   godot --path . -s res://tests/intro_test.gd -- <shots dir>
#
# Read from the tree rather than from a picture: the order of the beats and when the black lifts.
extends SceneTree
const Verdict = preload("res://tests/Verdict.gd")
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var lines: Array[String] = []

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	DirAccess.make_dir_recursive_absolute("user://preview")
	for f in ["splash.png", "heart.png"]:
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes("res://../../../scripts/models/".path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# The title is a ScreenGui over the whole window; a shot behind it is a shot of the card.
	main.show_title = false
	world.script_print.connect(func(_n, line): lines.append(String(line)))
	root.add_child(main)
	# The title holds the intro until something is pressed; nothing below runs until it is.
	var title := main.get_node_or_null("Title")
	if title != null:
		title._start()

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 2.0:
		phase = 1
		t = 0.0
		# Only the card: the rest of the manifest stays missing, so the black has to wait.
		world.run_chunk("card", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
local v = Instance.new("StringValue")
v.Name = "SplashImage"
v.Value = "user://preview/splash.png"
v.Parent = game:GetService("ReplicatedFirst")   -- where Main.gd puts the card
""")
	# Clear of the boundary: the picture goes up at two seconds and is shown the frame after.
	elif phase == 1 and t > 2.0:
		phase = 2
		t = 0.0
		world.run_client_chunk("look", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local rs = game:GetService("ReplicatedStorage")
local intro = gui:FindFirstChild("Intro")
local card = intro and intro:FindFirstChild("Card")
print("INTRO the card is up: " .. tostring(card ~= nil and card.Visible and card.Image ~= ""))
local Mixer = require(rs:WaitForChild("Mixer"))
print("INTRO the tune starts from nothing: " .. tostring(Mixer.musicDuck() < 0.35))
""")
	# The middle of the dark, not past it. The black ends on the host reporting the manifest
	# done rather than on a timeout, so the whole dark runs under five seconds: the card goes
	# at 3.2s and the light comes up around 8.
	elif phase == 2 and t > 2.0:
		phase = 3
		t = 0.0
		# The sky and the meshes are still missing, so the black must still be up.
		world.run_client_chunk("dark", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local intro = gui:FindFirstChild("Intro")
local black = intro and intro:FindFirstChild("Black")
print("INTRO still dark while the world is unfinished: "
	.. tostring(black ~= nil and black.BackgroundTransparency < 0.05))
-- The bar is up and part way along: the fixture has given it the card and nothing else, so
-- one of thirteen is there and it should show that rather than nought or all.
local loading = intro and intro:FindFirstChild("Loading")
local word = loading and loading:FindFirstChild("Word", true)
local fill = loading and loading:FindFirstChild("Fill", true)
print("INTRO the bar is up in the dark: " .. tostring(loading ~= nil and loading.Visible))
print("INTRO and it says what it is doing: " .. tostring(word ~= nil and word.Text == "Loading"))
print("INTRO and part way, not empty or full: "
	.. tostring(fill ~= nil and fill.Size.X.Scale > 0 and fill.Size.X.Scale < 1))
local card = intro and intro:FindFirstChild("Card")
print("INTRO and the card has gone: " .. tostring(card ~= nil and not card.Visible))
""")
	elif phase == 3 and t > 2.0:
		phase = 4
		t = 0.0
		# The rest of what the intro waits on, all at once.
		world.run_chunk("finish", """
local Lighting = game:GetService("Lighting")
local rs = game:GetService("ReplicatedStorage")
local place = rs.PlaceAssets
for _, name in ipairs({ "SkyboxUp", "SkyboxDn", "SkyboxFt", "SkyboxBk", "SkyboxLf",
		"SkyboxRt", "RocketMesh", "TreeMesh", "HeartIcon", "FlameSprite" }) do
	if not place:FindFirstChild(name) then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "user://preview/heart.png"
		v.Parent = place
	end
end
if not Lighting:FindFirstChildOfClass("Sky") then
	local sky = Instance.new("Sky")
	sky.Parent = Lighting
end
for _, name in ipairs({ "Rocket", "Tree" }) do
	if not workspace:FindFirstChild(name) then
		local m = Instance.new("MeshPart")
		m.Name = name
		m.MeshId = "user://preview/heart.png"
		m.Anchored = true
		m.Position = Vector3.new(0, -400, 0)
		m.Parent = workspace
	end
end
""")
	elif phase == 4 and t > 4.0:
		phase = 5
		world.run_client_chunk("lit", """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local rs = game:GetService("ReplicatedStorage")
local Mixer = require(rs:WaitForChild("Mixer"))
print("INTRO the dark lifts once it is: " .. tostring(gui:FindFirstChild("Intro") == nil))
print("INTRO and the bar went with it: " .. tostring(gui:FindFirstChild("Intro") == nil))
print("INTRO and the tune is all the way up: " .. tostring(Mixer.musicDuck() == 1))
""")
	elif phase == 5 and t > 2.0:
		quit(Verdict.finish(lines, "INTRO"))
	return false
