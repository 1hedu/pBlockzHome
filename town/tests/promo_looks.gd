# Stills of him in one look after another, from one spot with one lens, for a rapid-fire cut.
#
#   node scripts/stage-preview.js all .preview
#   godot --path . --resolution 1920x1080 -s res://tests/promo_looks.gd -- <out dir> [random looks, default 60]
#
# He stands south of the fountain with his back to it and the Earth over it; the lens never moves.
# Looks are put on through the real wardrobe (wear / remove on its remote), and a still is only
# taken once the wardrobe's own list says he is wearing exactly that -- so nothing is doubled in
# a hand and nothing is half on. What he can wear is whatever the chain says this wallet holds.
#
# Nothing the rest of the film already shows. He struts around the other shots in the gold suit,
# the top hat, the Rolex, Louis and the cane, with the White Roma at his heel, and wields the cane,
# the spoons and the wand -- so a montage that keeps offering those reads as the same few things
# again rather than as a wardrobe. Every one of them is left out here (WORN_ELSEWHERE); what is
# left is what you have not seen.
#
# Three runs of looks, numbered in order so they sort as they were shot:
#   A  one thing on a bare body, every item, slot by slot
#   B  the matched colours: tee, sweatpants and pegs of each colour together
#   C  full looks, one thing in each slot, picked by a fixed shuffle (the same every run)
#
# Writes <out>/looks-<month><day>-<hour><minute>/NNN-<run>-<what>.png and never over anything.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const Preview = preload("res://tests/Preview.gd")
const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var out := ""
var randoms := 60
var shot := 0
var only := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var base: String = args[0] if args.size() > 0 else "user://promo"
	randoms = int(args[1]) if args.size() > 1 else 60
	only = args[2] if args.size() > 2 else ""    # one slot, e.g. "back": everything else is skipped
	var now := Time.get_datetime_dict_from_system()
	out = base.path_join("looks-%02d%02d-%02d%02d" % [now.month, now.day, now.hour, now.minute])
	DirAccess.make_dir_recursive_absolute(out)
	var preview_dir := ProjectSettings.globalize_path("res://../../../.preview")
	StandIns.stage("looks")
	Preview.stage("looks", preview_dir)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(_heard)
	root.add_child(main)
	root.msaa_3d = Viewport.MSAA_4X
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	root.position = Vector2i(0, 0)
	Arrive.now(world)
	await create_timer(1.0).timeout
	world.set_quality(10, false)
	await create_timer(11.0).timeout
	Preview.install(world, "looks", preview_dir)
	await create_timer(2.0).timeout
	world.run_chunk("stand", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root = ch.HumanoidRootPart
local y = root.Position.Y
root.CFrame = CFrame.new(Vector3.new(0, y, -19), Vector3.new(0, y, -60))
""")
	world.run_client_chunk("looks", LOOKS.replace("RANDOMS", str(randoms)).replace("ONLYSLOT", only))

## A look is ready: two frames for the renderer to have it, the still, and on to the next.
func _heard(_name, line) -> void:
	var s := String(line)
	if s.begins_with("LOOKS done"):
		print("  %d still(s) -> %s" % [shot, out])
		quit(0)
		return
	if s.begins_with("LOOKS note "):
		print("  ", s)
		return
	if not s.begins_with("LOOKS ready "): return
	var label := s.substr(12)
	await process_frame
	await process_frame
	shot += 1
	root.get_texture().get_image().save_png(out.path_join("%03d-%s.png" % [shot, label]))
	world.run_client_chunk("next", "workspace:SetAttribute('LooksNext', %d)" % shot)

const LOOKS := """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local remote = game:GetService("ReplicatedStorage"):WaitForChild("WardrobeRemote")
local player = Players.LocalPlayer

-- The town and nothing else, and one lens that never moves: low in front of him, looking up past
-- him at the fountain and the Earth over it.
for _, s in ipairs(player.PlayerGui:GetChildren()) do if s:IsA("ScreenGui") then s.Enabled = false end end
local sg = game:GetService("StarterGui")
pcall(function() sg:SetCore("TopbarEnabled", false) end)
pcall(function() sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
-- And no name tags: they are drawn over everything, so the archivist's, a square behind him, sat
-- in the middle of his chest in every frame.
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BillboardGui") and d.Name == "NameTag" then d.Enabled = false end
end
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = 55
-- Where he was stood, not where he is: the server moves him there a moment after this starts, and
-- the idle sway should move him in the frame, not the frame with him.
local at = Vector3.new(0, player.Character.HumanoidRootPart.Position.Y, -19)
RunService.RenderStepped:Connect(function()
	cam.CFrame = CFrame.lookAt(at + Vector3.new(0.6, -1.4, -11.5), at + Vector3.new(0, 1.9, 0))
end)

-- What the other shots already put him in, by model name. Skipped everywhere below, so the
-- montage is the part of the wardrobe the film has not shown yet.
local WORN_ELSEWHERE = {}
for _, m in ipairs({
	-- what he wears while he struts: the staged dressing, and the pet that goes with it.
	-- By the name the wardrobe lists, which is the item's name and not the catalogue key.
	"Gold Glitter Suit Coat", "Top Hat", "Rainbow Diamond Rolex", "Louis", "Gold-Topped Cane",
	-- what he carries or is followed by in a shot of its own
	"PulseCape", "White Roma", "Cane", "Spoonie", "BFS 9000", "Pup", "Familiar",
	-- the look the wallet's own outfit holds, which has its own shot
	"414Cape", "blackshoes", "TeeBlack", "Wig", "blackpants", "mariajacket",
}) do WORN_ELSEWHERE[m] = true end

-- The wardrobe's own list: what he holds, which slot each thing is for, and what is on.
local items = nil
remote.OnClientEvent:Connect(function(kind, list) if kind == "items" then items = list end end)
repeat remote:FireServer("list") task.wait(1) until items and #items > 20
print("LOOKS note " .. #items .. " things to wear")

-- Exactly this and nothing else, asked for until the wardrobe's list agrees.
local function wear(want)
	for _ = 1, 14 do
		local settled = true
		for _, it in ipairs(items) do
			if it.worn and not want[it.model] then remote:FireServer("remove", it.model) settled = false end
			if not it.worn and want[it.model] then remote:FireServer("wear", it.model) settled = false end
		end
		if settled then return true end
		task.wait(0.5)
	end
	return false
end

local count = 0
local function still(run, what, want)
	if not wear(want) then print("LOOKS note never settled: " .. what) return end
	task.wait(0.7)                                  -- the pieces arrive and the body stops moving
	count += 1
	print("LOOKS ready " .. run .. "-" .. (what:gsub("[^%w]+", "_")))
	while workspace:GetAttribute("LooksNext") ~= count do task.wait() end
end

local ORDER = { "head", "neck", "back", "chest", "shirt", "hands", "wrist", "waist", "legs", "feet", "mainhand", "offhand", "pet" }
local bySlot = {}
local skipped = 0
for _, it in ipairs(items) do
	-- Capes are exempt from that rule.
	--
	-- Leaving out what is worn elsewhere in the film stops the same hat appearing twice, but
	-- there are only eleven capes and two of them -- the 414 and the Pulse -- are the ones he
	-- wears in other shots. Dropping those leaves the wardrobe looking like it has nine.
	if (WORN_ELSEWHERE[it.model] or WORN_ELSEWHERE[it.name]) and it.slot ~= "back" then
		skipped += 1
	elseif it.slot and it.slot ~= "" then
		bySlot[it.slot] = bySlot[it.slot] or {}
		table.insert(bySlot[it.slot], it)
	end
end
for _, list in pairs(bySlot) do table.sort(list, function(a, b) return a.name < b.name end) end
print("LOOKS note " .. skipped .. " left out, already worn elsewhere in the film")

-- A: one thing on a bare body.
--
-- Back to the lens for the capes. A cape hangs down the back, so eleven of them photographed
-- from the front are eleven pictures of the same man standing still -- "it looks like nothing
-- is happening". He is turned round for that slot and turned back after it.
local ONLY = "ONLYSLOT"
local function face(camera)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local p = root.Position
	-- The lens sits at -Z of him, so facing it is -Z and showing him off is +Z.
	root.CFrame = CFrame.new(p, p + Vector3.new(0, 0, camera and -10 or 10))
	task.wait(0.35)
end
for _, slot in ipairs(ORDER) do
	if ONLY == "" or ONLY == slot then
		if slot == "back" then face(false) end
		for _, it in ipairs(bySlot[slot] or {}) do
			still("A_" .. slot, it.name, { [it.model] = true })
		end
		if slot == "back" then face(true) end
	end
end

if ONLY ~= "" then print("LOOKS done " .. count) return end

-- B: a colour at a time -- the tee, the sweatpants and the pegs that share it.
local COLOURS = { "Red", "Magenta", "Purple", "Blue", "Cyan", "Yellow", "Orange", "Indigo", "Green", "White", "Black" }
for _, colour in ipairs(COLOURS) do
	local want, n = {}, 0
	for _, it in ipairs(items) do
		local first = it.name:gsub("^yourfriend's ", ""):match("^(%a+) ")
		if first == colour and not WORN_ELSEWHERE[it.model] and not WORN_ELSEWHERE[it.name]
			and (it.name:find("Tee") or it.name:find("Sweatpants") or it.name:find("Pegs")) then
			want[it.model] = true
			n += 1
		end
	end
	if n >= 2 then still("B_colour", colour, want) end
end

-- C: full looks, one thing in most slots, by a shuffle that comes out the same every run.
local seed = 943
local function roll(n)
	seed = (seed * 1103515245 + 12345) % 2147483648
	return (math.floor(seed / 65536) % n) + 1
end
for i = 1, RANDOMS do
	local want, names = {}, {}
	for _, slot in ipairs(ORDER) do
		local list = bySlot[slot]
		-- Most slots most of the time: a look with everything on every time is one look.
		if list and roll(10) <= 7 then
			local it = list[roll(#list)]
			want[it.model] = true
		end
	end
	still("C_look", ("%02d"):format(i), want)
end
wear({})
print("LOOKS done")
"""
