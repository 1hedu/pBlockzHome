# The ordinary game to walk around, with the unpublished models loaded off disk and granted to
# the player. Nothing is photographed and nothing touches the camera.
#
#   node scripts/stage-preview.js roma,pup,steven <stage dir>
#   godot --path . -s res://tests/preview_run.gd -- <stage dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0

# Seconds to hold the place assets back (`-- <stage> 12`), so the cold-start wait the intro's
# dark covers can be seen on a machine where every asset is already a local file.
var cold := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	if args.size() > 1:
		cold = float(args[1])
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	# Place assets rather than items, so they are not in the staging directory.
	for f in ["rocket.obj", "rocket-colors.png", "tree.obj", "tree-colors.png", "heart.png",
			"flame.png", "splash.png"]:
		var src := "res://../../../scripts/models/".path_join(f)
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(src))
			w.close()
	# The fight's own sounds, decoded by scripts/prep-sfx.js.
	for f in ["sword1.wav", "sword2.wav", "master.wav", "fire.wav", "enemyhit.wav",
			"enemydies.wav", "hurt.wav", "dies.wav", "lowhp.wav", "fall.wav"]:
		var src := "res://../../../scripts/sfx/".path_join(f)
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(src))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		for key in ["roma", "pup", "steven", "crudespoon", "spoonie",
				"plstorch", "plsxtorch", "hextorch", "prvxtorch", "inctorch",
				"redcandle", "greencandle"]:
			var raw := FileAccess.get_file_as_string(stage.path_join(key + ".json"))
			world.add_model("ReplicatedStorage", key,
				raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		# Before the faked cold wait: the card ships with the client and is what covers the fetch.
		world.run_chunk("splash", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets")
if not place then
	place = Instance.new("Folder")
	place.Name = "PlaceAssets"
	place.Parent = rs
end
local v = Instance.new("StringValue")
v.Name = "SplashImage"
v.Value = "user://preview/splash.png"
v.Parent = place
""")
		world.run_chunk("preview", ("""
-- A cold start, faked: nothing has been fetched yet and the place waits on it.
local COLD = %f
if COLD > 0 then
	print(("preview: holding the place assets back %%.0fs, as a cold start would"):format(COLD))
	task.wait(COLD)
end
""" % cold) + """
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local Health = require(game:GetService("ServerScriptService").Health)
local rs = game:GetService("ReplicatedStorage")

-- The place assets, as the chain would hand them over: a folder of paths. Rocket, Tree and
-- Hearts all wait on this, so filling it locally exercises the real scripts rather than a
-- copy of them.
local place = rs:FindFirstChild("PlaceAssets")
if not place then
	place = Instance.new("Folder")
	place.Name = "PlaceAssets"
	place.Parent = rs
end
for name, file in pairs({
	RocketMesh = "rocket.obj", RocketColors = "rocket-colors.png",
	TreeMesh = "tree.obj", TreeColors = "tree-colors.png",
	HeartIcon = "heart.png", FlameSprite = "flame.png",
	SfxSword1 = "sword1.wav", SfxSword2 = "sword2.wav", SfxMaster = "master.wav",
	SfxFire = "fire.wav",
	SfxEnemyHit = "enemyhit.wav", SfxEnemyDies = "enemydies.wav",
	SfxHurt = "hurt.wav", SfxDies = "dies.wav",
	SfxLowHp = "lowhp.wav", SfxFall = "fall.wav",
}) do
	if not place:FindFirstChild(name) then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "user://preview/" .. file
		v.Parent = place
	end
end

-- Where the wardrobe looks for the model behind an owned item.
local onchain = rs:FindFirstChild("OnChain")
if not onchain then
	onchain = Instance.new("Folder")
	onchain.Name = "OnChain"
	onchain.Parent = rs
end

-- Owned, so the wardrobe keeps them instead of taking them off you. Nothing is on a chain,
-- so the ledger is answered with these on top of whatever it really returns.
local GRANT = {
	{ model = "White Roma", name = "White Roma", slot = "pet", kind = "pet" },
	{ model = "Pup", name = "Pup", slot = "pet", kind = "pet" },
	{ model = "Familiar", name = "Familiar", slot = "pet", kind = "pet" },
	{ model = "Spoonie", name = "Spoonie", slot = "mainhand", kind = "accessory" },
	{ model = "BFS 9000", name = "BFS 9000", slot = "mainhand", kind = "accessory" },
	{ model = "PLS Torch", name = "PLS Torch", slot = "mainhand", kind = "accessory" },
	{ model = "PLSX Torch", name = "PLSX Torch", slot = "mainhand", kind = "accessory" },
	{ model = "HEX Torch", name = "HEX Torch", slot = "mainhand", kind = "accessory" },
	{ model = "PRVX Torch", name = "PRVX Torch", slot = "mainhand", kind = "accessory" },
	{ model = "INC Torch", name = "INC Torch", slot = "mainhand", kind = "accessory" },
	{ model = "Red Candle", name = "Red Candle", slot = "mainhand", kind = "accessory" },
	{ model = "Green Candle", name = "Green Candle", slot = "mainhand", kind = "accessory" },
}
for _, g in ipairs(GRANT) do
	local m = rs:FindFirstChild(g.model)
	if m and m.Parent ~= onchain then m.Parent = onchain end
end

local realData = Ledger.data
Ledger.data = function()
	local d = realData()
	if not d or d.status == "loading" then d = { status = "ok", items = {} } end
	local items = {}
	for _, it in ipairs(d.items or {}) do table.insert(items, it) end
	for i, g in ipairs(GRANT) do
		if onchain:FindFirstChild(g.model) then
			table.insert(items, { id = 9000 + i, qty = 1, model = g.model, name = g.name,
				thumb = "", slot = g.slot, kind = g.kind, tier = 0, tier_name = "" })
		end
	end
	local copy = { items = items }
	for k, v in pairs(d) do if k ~= "items" then copy[k] = v end end
	copy.status = "ok"
	return copy
end

-- A way to be hit without a second player. Four of the nine combat sounds only happen to
-- someone taking a blow, and there is nobody else here to land one -- so H takes half a
-- heart and J takes a whole one, which is enough to hear hurt, low hp and dying.
--
-- The harness's, not the game's: nothing in scripts/src knows this exists.
local hurt = Instance.new("RemoteEvent")
hurt.Name = "PreviewHurt"
hurt.Parent = rs
hurt.OnServerEvent:Connect(function(who, half)
	Health.hit(who, nil, half == 2 and 2 or 1, 0)
end)

print("PREVIEW rocket, tree, hearts, pets, spoons, torches and candles are yours -- H hurts you, J hurts more")
""")
		world.run_client_chunk("hurtkeys", """
local UserInputService = game:GetService("UserInputService")
local rs = game:GetService("ReplicatedStorage")
local hurt = rs:WaitForChild("PreviewHurt", 30)
UserInputService.InputBegan:Connect(function(input, typing)
	if typing or not hurt then return end
	if input.KeyCode == Enum.KeyCode.H then hurt:FireServer(1)
	elseif input.KeyCode == Enum.KeyCode.J then hurt:FireServer(2) end
end)
print("PREVIEW H takes half a heart, J takes a whole one")
""")
	return false
