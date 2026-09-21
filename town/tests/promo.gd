# Footage of the town for a promo: one shot a run, written as a movie, with stills along the way.
#
#   node scripts/stage-preview.js all .preview
#   godot --path . --write-movie <out>.avi --fixed-fps 60 --resolution 1920x1080 -s res://tests/promo.gd -- <shot> <stills dir>
#
# tests/promo.sh runs every shot and cuts each movie down to its clip. Movie mode steps the game a
# fixed sixtieth at a time however long a frame takes to draw, so the footage is smooth at full
# quality on a machine that could not play it that way. Quality is set to 10 and edges are
# smoothed (MSAA, which the game itself leaves off); nothing is saved.
#
# The shots: arrival (the real intro, HUD and all), flyover, tree, earth, fires, outfit, cast, spoon,
# pets, fish, walk (the game as played, HUD and all).
#
# It prints CLIP <first frame> <last frame>: the part of the movie that is the shot, the rest
# being the town loading.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const Preview = preload("res://tests/Preview.gd")
const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var shot := "flyover"
var stills := ""
var frame := 0
var preview_dir := ""
var said: Array[String] = []          # what the scripts have said, for _until

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	shot = args[0] if args.size() > 0 else "flyover"
	stills = args[1] if args.size() > 1 else "user://promo"
	DirAccess.make_dir_recursive_absolute(stills)
	preview_dir = ProjectSettings.globalize_path("res://../../../.preview")
	StandIns.stage("promo")
	Preview.stage("promo", preview_dir)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	# The wallet, for the shots that cannot work without one.
	#
	# The shop's shelf, Kara's canvas and the bank all read what THIS WALLET holds, so with
	# auto_start off they sit on "Still reading the ledger" for as long as you care to wait --
	# there is nothing to read for. Same for wearing a saved outfit: the wardrobe cannot
	# confirm an item nobody holds.
	#
	# Only for the shots that need it. Everything else stays offline and quick: a scenery
	# shot has no business touching the chain, and a chain read is the slowest thing here.
	main.get_node("Wallet").auto_start = shot in ["ui", "newfit", "jump", "counters", "sitdown"]
	world.set_quality(1, false)             # the lead-in is discarded; do not spend time drawing it
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		if String(line).begins_with("PROMO ") or String(line).begins_with("wardrobe:"):
			said.append(String(line))
			print("  PROMO ", line))
	root.add_child(main)
	root.msaa_3d = Viewport.MSAA_DISABLED   # _rich() turns it on when the shot begins
	# Exactly the frame asked for. Left alone the window opened the size of the screen -- three by
	# two on this laptop -- and the movie's frames with it, whatever --resolution said.
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.size = Vector2i(1920, 1080)
	root.position = Vector2i(0, 0)
	if shot != "arrival": Arrive.now(world)
	_run()

func _process(_delta: float) -> bool:
	frame += 1
	return false

func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout

func _still(name: String) -> void:
	var file := stills.path_join("%s-%s.png" % [shot, name])
	root.get_texture().get_image().save_png(file)
	print("  STILL ", file)

## The lens on a circle round a point: angle, radius and height each go from one value to another
## over the seconds given, looking at the point raised by `look_y`. Angle 0 is out along +Z.
## `on_me` puts the point on the player's root instead of at a place in the town.
func _orbit(centre: Vector3, a0: float, a1: float, r0: float, r1: float, h0: float, h1: float, look_y: float, seconds: float, fov := 50.0, on_me := false) -> void:
	world.run_client_chunk("camera", """
local RunService = game:GetService("RunService")
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.FieldOfView = %f
local mine = (workspace:GetAttribute("PromoCam") or 0) + 1
workspace:SetAttribute("PromoCam", mine)
local t = 0
local conn
conn = RunService.RenderStepped:Connect(function(dt)
	if workspace:GetAttribute("PromoCam") ~= mine then conn:Disconnect() return end
	t = math.min(t + dt, %f)
	local a = t / %f
	local c = Vector3.new(%f, %f, %f)
	if %s then
		local ch = game:GetService("Players").LocalPlayer.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if root then c = root.Position + c end
	end
	local ang = math.rad(%f + (%f) * a)
	local r = %f + (%f) * a
	local h = %f + (%f) * a
	cam.CFrame = CFrame.lookAt(c + Vector3.new(math.sin(ang) * r, h, math.cos(ang) * r), c + Vector3.new(0, %f, 0))
end)
""" % [fov, seconds, seconds, centre.x, centre.y, centre.z, "true" if on_me else "false", a0, a1 - a0, r0, r1 - r0, h0, h1 - h0, look_y])

## No panels, no top bar, no chat: the town and nothing else. Name tags stay -- they are in the world.
func _clean() -> void:
	world.run_client_chunk("clean", """
local Players = game:GetService("Players")
for _, s in ipairs(Players.LocalPlayer.PlayerGui:GetChildren()) do
	if s:IsA("ScreenGui") then s.Enabled = false end
end
local sg = game:GetService("StarterGui")
pcall(function() sg:SetCore("TopbarEnabled", false) end)
pcall(function() sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
""")

## Put on the way the wardrobe puts it on, by instance name -- so a second thing for the same hand
## takes the first one's place, as it does in the game. The town has already dressed him in one
## of everything the staged catalogue gives: the gold suit, the top hat, the Rolex, Louis, the cane.
## The pet that goes with that suit is the White Roma, so every shot with him in it asks for it.
## The gold suit, and the outfit he has saved. Named once here rather than spelled out at each
## shot that wants one: a list copied into six places is six places to get it wrong.
const GOLD := ["goldcoat", "goldpants", "GoldShoes", "TopHat", "RainbowRolex", "LeatherDuck"]
const SAVED := ["414Cape", "blackshoes", "Familiar", "Spoonie", "TeeBlack", "Wig", "blackpants", "mariajacket"]

## Dresses him, and dresses him again once the town has had its turn.
##
## Every shot that puts clothes on him needs this, not only the one somebody noticed. The
## greeting (Wardrobe's dressOnce) lands a few seconds after a body spawns and puts the SAVED
## outfit on, so a single _wear before it is simply overruled -- which is how a bird's eye of
## the town came out with him in Maria's wig. Whoever speaks last wins; this speaks last.
func _dress(names: Array) -> void:
	_wear(names)
	await _wait(4.0)
	_wear(names)
	await _wait(2.0)

func _wear(names: Array) -> void:
	world.run_client_chunk("wear", """
local remote = game:GetService("ReplicatedStorage"):WaitForChild("WardrobeRemote")
local ch = game:GetService("Players").LocalPlayer.Character
-- A pet is not on the body: it is a model in the world named for its owner, so it is told from
-- its template by its parts.
local function isPet(name)
	local pet = workspace:FindFirstChild("Pet_" .. game:GetService("Players").LocalPlayer.Name, true)
	local template = game:GetService("ReplicatedStorage").OnChain:FindFirstChild(name)
	if not pet or not template then return false end
	local function parts(m)
		local names = {}
		for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then table.insert(names, d.Name) end end
		table.sort(names)
		return table.concat(names, ",")
	end
	return parts(pet) == parts(template)
end
-- Asked again until it is on: the wardrobe only honours what the chain says he holds, and a
-- windowed run reads that off the chain -- it lands some seconds in, not at a time one can name.
-- Everything asked for at once, each pass, until it is all on.
--
-- This used to take the list one at a time and give each item twelve tries a second apart, so
-- dressing him in ten things could take two minutes -- and a shot that starts seven seconds in
-- got the first two pieces and nothing else. A whole gold suit arrived as a coat and trousers.
local want = {}
for name in string.gmatch("%s", "[^|]+") do table.insert(want, name) end
for _ = 1, 20 do
	local missing = 0
	for _, name in ipairs(want) do
		if not (ch:FindFirstChild(name) or isPet(name)) then
			remote:FireServer("wear", name)
			missing += 1
		end
	end
	-- Joined with .. rather than formatted: this whole chunk is built with GDScript's own
	-- "%%" operator, so a second specifier in here is one GDScript tries to fill and cannot --
	-- the string comes out broken and the chunk never runs. Which is what happened: the log
	-- had the town dressing him and not one line from this.
	if missing == 0 then print("PROMO wearing all " .. #want) return end
	task.wait(0.4)
end
for _, name in ipairs(want) do
	if not (ch:FindFirstChild(name) or isPet(name)) then print("PROMO never got " .. name .. " on") end
end
""" % "|".join(names))

## Walked the way the controls walk him: a Move a frame. MoveTo does not carry a client's own body here.
## Through each point in turn. The square has lamps, benches, a fountain and Funmaster Mike in it,
## and a straight line across it ends at the first of them: the corners are what keep him walking.
func _walk(points: Array) -> void:
	var list := PackedStringArray()
	for p in points: list.append("Vector3.new(%f, 0, %f)" % [p.x, p.z])
	world.run_client_chunk("walk", """
local ch = game:GetService("Players").LocalPlayer.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local root = ch.HumanoidRootPart
for _, target in ipairs({ %s }) do
	while true do
		local away = Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
		if away.Magnitude < 2 then break end
		hum:Move(away.Unit)
		task.wait()
	end
end
hum:Move(Vector3.zero)
""" % ", ".join(list))

## Where to stand, facing what.
func _stand(at: Vector3, facing: Vector3) -> void:
	world.run_chunk("stand", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root = ch.HumanoidRootPart
local y = root.Position.Y
root.CFrame = CFrame.new(Vector3.new(%f, y, %f), Vector3.new(%f, y, %f))
""" % [at.x, at.z, facing.x, facing.z])

func _click() -> void:
	world.run_client_chunk("click", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer()")

## A jump, asked for the way a script asks for one: Humanoid.Jump.
func _jump() -> void:
	world.run_chunk("jump", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
if hum then hum.Jump = true end
""")

## Drops him onto a trampoline, which throws him off the roof.
##
## Found by name rather than by position: Trampoline.server.luau wires every part in the map
## called Trampoline-something, so adding a building with two more on it is an edit to a
## .model.json and nothing here. Landing ON one is what fires Touched.
func _trampoline() -> void:
	world.run_chunk("tramp", """
local map = workspace:WaitForChild("Map", 10)
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if not map or not root then return end
for _, part in ipairs(map:GetDescendants()) do
	if part:IsA("BasePart") and part.Name:match("^Trampoline") and not part.Name:match("Bed$") then
		root.CFrame = CFrame.new(part.Position + Vector3.new(0, 3.5, 0))
		print("PROMO standing on " .. part.Name)
		return
	end
end
print("PROMO no trampoline in the map")
""")

## Walks up to a desk and asks for it, the way a player does: the NPC's own Talk prompt.
##
## InputHoldBegin is what the key press calls, so the desk opens through its own handler with
## its own menu -- rather than this faking a window the server never sent.
func _talk(npc: String) -> void:
	world.run_client_chunk("talk", """
local map = workspace:WaitForChild("Map", 10)
local m = map and map:FindFirstChild("%s")
local torso = m and m:FindFirstChild("Torso")
local ch = game:GetService("Players").LocalPlayer.Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if not torso or not root then print("PROMO no desk: %s") return end
-- Where they are LOOKING, which is where a customer stands.
--
-- This used to walk to whichever side faced the middle of the square, and for the bank that
-- is behind Penn's counter: the prompt showed and never fired, because the reach is measured
-- to a spot on the wrong side of the desk. An NPC faces the person they are serving.
local at = torso.Position
local dir = torso.CFrame.LookVector
dir = Vector3.new(dir.X, 0, dir.Z)
dir = dir.Magnitude > 0.1 and dir.Unit or Vector3.new(0, 0, 1)
root.CFrame = CFrame.new(at + dir * 4.0 + Vector3.new(0, 0.5, 0), at)
task.wait(0.45)
local prompt = torso:FindFirstChild("Talk")
if prompt then prompt:InputHoldBegin() else print("PROMO no Talk prompt on %s") end
""" % [npc, npc, npc])

## Picks an item off the desk's own menu, the way the button does: the id the server listed.
func _menu(remote: String, id: String) -> void:
	world.run_client_chunk("menu", """
local r = game:GetService("ReplicatedStorage"):FindFirstChild("%s")
if r then r:FireServer("%s") end
""" % [remote, id])

## Runs a list past the eye. A shelf nobody scrolls is a screenshot of a shelf.
func _scroll(gui: String, seconds: float, frames: int) -> void:
	world.run_client_chunk("scroll", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("%s")
local list
for _, d in ipairs(gui and gui:GetDescendants() or {}) do
	if d:IsA("ScrollingFrame") then list = d break end
end
if not list then print("PROMO nothing to scroll in %s") return end
task.spawn(function()
	-- How far there is to go, and a fallback when the engine does not say.
	--
	-- This read AbsoluteCanvasSize alone, got zero, and scrolled nothing: the shelf sat on its
	-- first four items for the whole shot. Asking for more than there is costs nothing, because
	-- CanvasPosition clamps itself -- so a number too big just means it reaches the bottom.
	local far = list.AbsoluteCanvasSize.Y - list.AbsoluteSize.Y
	if not far or far <= 0 then far = 1600 end
	print(("PROMO scrolling %s by %d"):format(list.Name, far))
	local t = 0
	while t < %f do
		local dt = task.wait()
		t += dt
		list.CanvasPosition = Vector2.new(0, far * math.min(1, t / %f))
	end
end)
""" % [gui, gui, seconds, seconds])

## Everything off, through the wardrobe's own list.
##
## Asked repeatedly rather than once: the town dresses you a moment after you spawn (Wardrobe's
## dressOnce), so a single strip can be undone half a second later by the greeting.
func _bare() -> void:
	world.run_client_chunk("bare", """
local remote = game:GetService("ReplicatedStorage"):WaitForChild("WardrobeRemote")
local items
remote.OnClientEvent:Connect(function(kind, list) if kind == "items" then items = list end end)
-- Kept up rather than done once: stripping him works, and then the town dresses him again a
-- few seconds later and the shot ends on a clothed body. This holds him bare for the whole
-- shot instead of winning the argument once and walking away from it.
for _ = 1, 70 do
	remote:FireServer("list")
	task.wait(0.4)
	if items then
		for _, it in ipairs(items) do
			if it.worn then remote:FireServer("remove", it.model) end
		end
	end
end
""")

## The face reveal: he turns and walks at the camera, and the camera gives ground.
##
## The lens starts where it already is -- behind him, the shot you have been watching -- and
## does not jump anywhere. He turns round and walks into it. Once he has closed about half the
## gap the camera starts backing away at his pace, so he stays the same size in frame and keeps
## coming, rather than arriving under the lens and out of the bottom of the picture.
##
## Picking a stop distance by hand went wrong three times: 4.5 studs walked him past it, 6.5
## crowded it, 9.0 was further than the camera sits so he turned round and stood still. A
## fraction of the real gap cannot fail that way, and it says both numbers out loud.
func _face(seconds: float) -> void:
	world.run_client_chunk("face", """
local RunService = game:GetService("RunService")
local ch = game:GetService("Players").LocalPlayer.Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local root = ch:FindFirstChild("HumanoidRootPart")
if not root or not hum then return end
local cam = workspace.CurrentCamera
local eye = cam.CFrame.Position                  -- where it already is: nothing jumps
cam.CameraType = Enum.CameraType.Scriptable
local flat = Vector3.new(eye.X - root.Position.X, 0, eye.Z - root.Position.Z)
local start = flat.Magnitude
local toCam = start > 0.1 and flat.Unit or Vector3.new(0, 0, 1)
local keep = start * 0.55
print(("PROMO the lens is %%.1f studs off; holding at %%.1f once he is in"):format(start, keep))
local mine = (workspace:GetAttribute("PromoCam") or 0) + 1
workspace:SetAttribute("PromoCam", mine)
local conn
conn = RunService.RenderStepped:Connect(function()
	if workspace:GetAttribute("PromoCam") ~= mine then conn:Disconnect() return end
	local r = ch:FindFirstChild("HumanoidRootPart")
	if not r then return end
	local gap = Vector3.new(eye.X - r.Position.X, 0, eye.Z - r.Position.Z)
	if gap.Magnitude < keep then eye = eye + toCam * (keep - gap.Magnitude) end
	cam.CFrame = CFrame.lookAt(eye, r.Position + Vector3.new(0, 1.0, 0))
end)
task.spawn(function()
	local t = 0
	while t < %f do
		local r = ch:FindFirstChild("HumanoidRootPart")
		if not r then break end
		local away = Vector3.new(eye.X - r.Position.X, 0, eye.Z - r.Position.Z)
		hum:Move(away.Unit)
		t += task.wait()
	end
	hum:Move(Vector3.zero)
	print(("PROMO walked at the lens for %%.1fs"):format(t))
end)
""" % seconds)

## Shuts a panel by switching it off, whatever it is.
##
## "close" on a remote only works for the desks that listen for one, and Kara's drawing table
## does not -- it stayed on screen through the swap and was still there at the bank counter,
## palette and all.
## Waits for a script to say something, rather than for a number of seconds.
func _until(token: String, most: float) -> void:
	var spent := 0.0
	while spent < most:
		for line in said:
			if line.find(token) >= 0: return
		await _wait(0.25)
		spent += 0.25
	printerr("promo: waited %.0fs and never heard %s" % [most, token])

## Says READY once the chain has answered what this wallet holds.
##
## The desks that matter -- the shelf, the drawing table, the bank -- all wait on that read, and
## a fixed thirty second settle was the crudest possible way to wait for it: always too long
## when the answer came back quickly, and no help at all when it did not.
func _chain_ready() -> void:
	world.run_client_chunk("ready", """
local remote = game:GetService("ReplicatedStorage"):WaitForChild("WardrobeRemote")
local items
remote.OnClientEvent:Connect(function(kind, list) if kind == "items" then items = list end end)
for _ = 1, 120 do
	remote:FireServer("list")
	task.wait(0.25)
	if items and #items > 20 then
		print(("PROMO READY -- the chain says %d things"):format(#items))
		return
	end
end
print("PROMO READY -- gave up waiting on the chain")
""")

func _hide(names: Array) -> void:
	var want := PackedStringArray()
	for n in names: want.append('"%s"' % n)
	world.run_client_chunk("hide", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
for _, name in ipairs({ %s }) do
	local s = gui:FindFirstChild(name)
	if s then s.Enabled = false end
end
""" % ", ".join(want))

func _shut(remote: String) -> void:
	world.run_client_chunk("shut", """
local r = game:GetService("ReplicatedStorage"):FindFirstChild("%s")
if r then r:FireServer("close") end
""" % remote)

func _release() -> void:
	world.run_client_chunk("release", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer('release')")

## Full quality and smoothed edges, from here on.
##
## Called the moment a shot starts, and not before. Everything ahead of that -- the town
## loading, the stand-ins mounting, a settle waiting on the chain -- is thrown away by the trim
## in promo.sh, and there is no sense drawing frames at full quality and four-times MSAA to
## throw them away. In movie mode every frame is rendered however long it takes, so the lead-in
## was minutes of somebody's afternoon spent on footage that never reaches the film.
func _rich() -> void:
	get_root().msaa_3d = Viewport.MSAA_4X
	world.set_quality(10, false)

func _run() -> void:
	await _wait(1.0)
	if shot == "arrival":
		var first := frame; _rich()
		await _wait(6.0); _bare()
		await _wait(3.0); _still("descent")
		await _wait(3.0); _bare()          # again: the greeting dresses you a beat after you land
		await _wait(2.0); _still("landed")
		await _wait(5.0); _still("in-town")
		_face(3.4)                         # walks in, then stands facing the lens
		await _wait(6.5); _still("face")
		await _wait(0.5)
		_finish(first)
		return
	await _wait(11.0)
	Preview.install(world, "promo", preview_dir)
	await _wait(2.0)
	var first := 0
	match shot:
		"flyover":
			await _dress(GOLD)             # or he wears whatever is saved on chain that day
			# Down INTO the place, not above it.
			#
			# This was a hundred and twenty-five studs out at forty-eight up, which framed the
			# whole town inside the moon and made it read as a model on a table -- "it makes the
			# place feel small". So it starts wide and descends to nine studs off the ground at
			# fifty-five out, which is just outside the ring of buildings: they pass close to the
			# lens and rise above it, and a thing you look UP at is a thing with size.
			#
			# Seventy-two out and fourteen up at the end, and the sweep stops at 265 rather than
			# 292: fifty-five was NOT outside the ring, and the last third of that take flew into
			# the side of the Finch shop -- a brown wall, full frame. The first half was right, so
			# this keeps the move and stops before the shop is in the way.
			_clean()
			_orbit(Vector3(0, 0, 0), 200, 265, 95, 72, 26, 14, 5, 12.0, 70.0)
			await _wait(1.0); first = frame; _rich()
			await _wait(4.0); _still("a")
			await _wait(5.0); _still("b")
			await _wait(4.0)
		"tree":
			_clean()
			_orbit(Vector3(41, 0, 40), 215, 250, 62, 40, 5, 9, 17, 10.0, 60.0)
			await _wait(1.0); first = frame; _rich()
			await _wait(4.0); _still("a")
			await _wait(5.0); _still("b")
		"earth":
			# The tree from low on its -Z side, looking up: the Earth hangs over +Z.
			_clean()
			_orbit(Vector3(41, 0, 40), 196, 164, 34, 27, 1.0, 1.5, 24, 10.0, 80.0)   # inside the trading house, which stands between
			await _wait(1.0); first = frame; _rich()
			await _wait(4.0); _still("a")
			await _wait(5.0); _still("b")
		"fires":
			_clean()
			_orbit(Vector3(45, 0, -45), 300, 345, 30, 22, 5, 7, 4, 10.0, 50.0)
			await _wait(1.0); first = frame; _rich()
			await _wait(4.0); _still("a")
			await _wait(5.0); _still("b")
		"outfit":
			_wear(["PulseCape", "White Roma"])
			_stand(Vector3(-22, 0, 22), Vector3(-22, 0, -40))
			_clean()
			await _wait(7.0)
			# He faces -Z and the Earth hangs over +Z: the turn starts in front of him, looking up past him at it.
			_orbit(Vector3(0, 0, 0), 180, 540, 10, 8, 1.0, 1.6, 1.4, 12.0, 50.0, true)
			await _wait(1.0); first = frame; _rich()
			await _wait(2.5); _still("front")
			await _wait(3.0); _still("side")
			await _wait(3.0); _still("back")
			await _wait(2.5)
		"cast":
			_wear(["Cane", "White Roma"])
			_stand(Vector3(-34, 0, -32), Vector3(40, 0, -32))   # the open lane between the bank and the fountain
			_clean()
			await _wait(7.0)
			_orbit(Vector3(0, 0, 0), 35, 70, 13, 18, 2.5, 3.5, 0.8, 11.0, 50.0, true)
			await _wait(1.0); first = frame; _rich()
			_click()                       # held: the arm goes up and it charges
			await _wait(4.0); _still("charging")
			await _wait(2.6); _still("full")
			_release()                     # let go keeps the charge...
			await _wait(0.6)
			_click(); _release()           # ...and the click after throws it
			await _wait(0.5); _still("thrown")
			await _wait(2.3)
		"spoon":
			# BOTH spoons, one after the other: Spoonie, which is quick and takes a half heart,
			# then the BFS 9000, which takes a whole one and throws you.
			#
			# Standing in the open lane between the bank and the fountain -- the spot the wand
			# shot uses -- because the old mark put him beside the Hall of Records and the orbit
			# swung the camera INSIDE it. Most of that take is a red wall.
			await _dress(GOLD + ["Spoonie", "White Roma"])
			_stand(Vector3(-34, 0, -32), Vector3(40, 0, -32))
			_clean()
			await _wait(4.0)
			_orbit(Vector3(0, 0, 0), 35, 70, 10, 12, 2.2, 3.0, 1.2, 13.0, 55.0, true)
			await _wait(1.0); first = frame; _rich()
			_click(); _release()
			await _wait(0.45); _still("spoonie-1")
			await _wait(1.25)
			_click(); _release()
			await _wait(0.45); _still("spoonie-2")
			await _wait(1.1)
			_wear(["BFS 9000"])          # one thing per slot, so this takes the other out of his hand
			await _wait(1.3)
			_click(); _release()
			await _wait(0.6); _still("bfs-1")
			await _wait(1.4)
			_click(); _release()
			await _wait(0.6); _still("bfs-2")
			await _wait(1.6)
		"pets":
			# The White Roma, which is his: a little white car that follows him about.
			#
			# It reads as scenery from far off, which is why the camera is where it is now --
			# seven studs back at under two up, rather than fourteen back at three. Close and low,
			# a car trailing him is plainly a pet rather than something parked.
			# Dressed here, unlike the arrival.
			#
			# Naked is right for the intro -- that is him before the town has given him anything.
			# A bare body walking the square a second time reads as a gap rather than as a point,
			# so here he has the gold suit the staged catalogue dresses him in, with the HEX cape
			# over it. No wallet on this shot, so that suit IS what the town puts him in, and
			# nothing here reaches any other shot: every shot records in its own process.
			# The gold suit, named piece by piece, and the HEX cape over it.
			#
			# Asking for a cape alone did not work: the town dresses him in the SAVED outfit --
			# Maria's wig and jacket, the black tee and pants -- whether or not this shot has a
			# wallet, and _wear only fills the slots it is given. A cape on its own lands on top
			# of that and everything under it stays. So every slot the gold suit occupies is
			# named here, and each one takes the saved outfit's piece out of it.
			#
			# The names are the models' own, read out of .preview: goldcoat and goldpants are
			# lower case, GoldShoes and TopHat are not, the duck is LeatherDuck and the pegs are
			# GoldClothespins. Guessing at these is how the shoes went missing for three takes.
			await _dress(GOLD + ["Cane", "HEXCape", "White Roma"])
			_stand(Vector3(-27, 0, 27), Vector3(-27, 0, -40))
			_clean()
			await _wait(10.0)              # ten pieces to put on, and the chain read to land first
			# Behind and low, so the thing following him is in the frame.
			#
			# The old one sat fourteen studs out at three up and looked level at his middle, which
			# put a lamp post through his face and the pet somewhere off the bottom of the picture.
			_walk([Vector3(-27, 0, -27), Vector3(27, 0, -27), Vector3(27, 0, 27)])   # round the outside of the square
			_orbit(Vector3(0, 0, 0), 195, 235, 7, 6, 1.8, 1.5, 0.0, 9.0, 60.0, true)   # low enough to see what is on the ground behind him
			await _wait(1.0); first = frame; _rich()
			await _wait(3.0); _still("a")
			await _wait(4.0); _still("b")
			await _wait(1.0)
		"fish":
			world.run_chunk("fish", """
local rs = game:GetService("ReplicatedStorage")
local ch = game:GetService("Players"):GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local root = ch.HumanoidRootPart
root.CFrame = CFrame.new(Vector3.new(-32, root.Position.Y, 30), Vector3.new(-32, root.Position.Y, -40))   -- open ground, his back to the Earth
root.Anchored = true
for _, name in ipairs({ "Everliving Fish", "Fishing Rod" }) do
	local m = rs.Made:FindFirstChild(name)
	if m then hum:AddAccessory(m:Clone()) else print("PROMO missing " .. name) end
end
local names = { "Red Fish", "Magenta Fish", "Purple Fish", "Blue Fish", "Cyan Fish", "Yellow Fish", "Orange Fish", "Indigo Fish", "Green Fish", "Everliving Fish" }
for i, name in ipairs(names) do
	local m = rs.Made:FindFirstChild(name)
	if m then
		local holder = Instance.new("Model")
		holder.Name = name .. " Display"
		local copy = m:Clone()
		for _, d in ipairs(copy:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = true end end
		copy.Parent = holder
		holder.PrimaryPart = copy:FindFirstChild("Handle")
		holder.Parent = workspace
		holder:PivotTo(CFrame.new(root.Position.X + 3 + (i - 1) * 2.7, root.Position.Y + 0.8, root.Position.Z) * CFrame.Angles(0, math.rad(-90), 0))
	end
end
""")
			_wear(["White Roma"])
			_clean()
			await _wait(7.0)
			# Low, from in front of him, looking up the row with the Earth over it.
			_orbit(Vector3(13, 0, 0), 180, 180, 13, 13, 0.2, 0.2, 3.5, 1.0, 70.0, true)
			await _wait(1.0); first = frame; _rich()
			_orbit(Vector3(13, 0, 0), 180, 196, 13, 16, 0.2, 1.0, 3.5, 8.0, 70.0, true)
			await _wait(1.0); _still("row")
			await _wait(6.5); _still("wide")
			await _wait(0.5)
		"newfit":
			# The outfit he SAVED, read off the chain rather than guessed at: an item with
			# kind "outfit" under his wallet holds the list of model names, and this is it.
			# Maria's wig and jacket, the black tee and pants, black shoes, the 414 cape, a
			# Spoonie in hand and a Familiar at his heel.
			await _dress(SAVED)
			_stand(Vector3(-22, 0, 22), Vector3(-22, 0, -40))
			_clean()
			await _wait(8.0)
			_orbit(Vector3(0, 0, 0), 180, 540, 10, 8, 1.0, 1.6, 1.4, 12.0, 50.0, true)
			await _wait(1.0); first = frame; _rich()
			await _wait(2.5); _still("front")
			await _wait(3.0); _still("side")
			await _wait(3.0); _still("back")
			await _wait(2.5)
		"jump":
			# Three jumps on the flat, and then the roof throws him.
			await _dress(SAVED)
			_stand(Vector3(-34, 0, -32), Vector3(40, 0, -32))
			_clean()
			await _wait(8.0)
			_orbit(Vector3(0, 0, 0), 205, 245, 13, 15, 3.0, 5.0, 1.5, 16.0, 62.0, true)
			await _wait(1.0); first = frame; _rich()
			_jump(); await _wait(1.4)
			_jump(); await _wait(1.4)
			_jump(); await _wait(1.6); _still("jump")
			_trampoline()
			await _wait(1.2); _still("launched")
			await _wait(2.6); _still("falling")
			await _wait(2.6)
		"ui":
			# The desks, each one OPENED and then waited on until it has filled.
			#
			# Every window here says "give me a moment" first -- the shelf is a chain read and
			# so is the scan -- so a shot that opens one and cuts is a shot of the town saying
			# please wait. The scan and the shelf are also two clicks deep: the dialog is the
			# greeting, and the panel behind it is what people came to see.
			# Thirty seconds before a single desk is touched.
			#
			# "Still reading the ledger. Stay there -- I'll speak up the moment it lands" is what
			# Finch and Kara said in the last take, because a desk asks the chain what this
			# wallet holds and the answer takes its time. That read happens ONCE per player, so
			# waiting it out here costs half a minute of recording and every window after it
			# opens already full. Waiting at each desk instead did not work: the menu item fired
			# into a window that was not listening yet.
			_stand(Vector3(-22, 0, 22), Vector3(-22, 0, -40))
			_clean()
			_bare()
			_chain_ready()
			await _until("READY", 40.0)    # as soon as the chain answers, not half a minute later
			await _wait(1.5)
			first = frame; _rich()

			_talk("Screener")                      # DexScreener: prices, live
			await _wait(4.5); _still("dex")
			_shut("ScreenerRemote")

			_talk("Archivist")                     # the Hall of Records, then the scan itself
			await _wait(3.0)
			_menu("RecordsRemote", "scan")
			await _wait(5.0); _still("scan")
			_scroll("Explorer", 3.0, 0)
			await _wait(3.2); _still("scan-scrolled")
			_shut("ExplorerRemote")

			_talk("Shopkeeper")                    # Finch, then the shelf, scrolled
			await _wait(3.0)
			_menu("ShopRemote", "shop")
			await _wait(1.0)
			_menu("ShopRemote", "shop")            # twice: the first can land a frame early
			await _wait(4.5); _still("shelf")
			_scroll("ShopShelf", 2.2, 0)   # a quick run down the whole shelf, not a crawl
			await _wait(2.6); _still("shelf-scrolled")

			_talk("Tailor")                        # Kara, and the canvas you draw an item on
			await _wait(3.0); _still("tailor")
			_menu("TailorRemote", "paint")
			await _wait(1.0)
			_menu("TailorRemote", "paint")
			await _wait(4.5); _still("paint")

			_talk("Trader")                        # the swap
			await _wait(1.5)
			_talk("Trader")                        # again: it did not take the first time
			await _wait(4.5); _still("swap")

			_talk("Teller")                        # the bank
			await _wait(4.5); _still("bank")
		"counters":
			# The swap: walked up to and asked ONCE, the way every other desk is.
			#
			# It opened on the first take of the row and on none after, and the difference was me:
			# I added a second _talk for reliability, and Rebh's prompt TOGGLES -- onTalk shuts
			# the window if it is already open. Everything I did after that was chasing my own
			# damage: opening it on the remote instead, then hiding the very window I was asking
			# for, then waiting on market data that was never the problem.
			#
			# Once. Then leave it alone and let it fill.
			_stand(Vector3(-22, 0, 22), Vector3(-22, 0, -40))
			_clean()
			_bare()
			_chain_ready()
			await _until("READY", 40.0)
			await _wait(1.0)
			_hide(["PaintTable", "ShopShelf", "Explorer", "Screener", "Wardrobe"])
			await _wait(0.5)
			first = frame; _rich()
			# Stood where a customer stands, read off the map rather than off his facing.
			#
			# Trader.model.json puts Rebh's Torso at (45.4, 3.5, 0) with his Counter at
			# (43.5, 1.5, 0), so the far side of that counter is about X = 41. His Orientation is
			# unset, which makes his LookVector -Z -- along the counter and into his own
			# building, which is the wall _talk kept walking him into.
			_stand(Vector3(41, 0, 0), Vector3(45.4, 0, 0))
			await _wait(1.0)
			world.run_client_chunk("ask", """
local map = workspace:WaitForChild("Map", 10)
local m = map and map:FindFirstChild("Trader")
local torso = m and m:FindFirstChild("Torso")
local prompt = torso and torso:FindFirstChild("Talk")
if prompt then prompt:InputHoldBegin() print("PROMO asked Rebh") else print("PROMO no prompt on Rebh") end
""")
			await _wait(2.5)
			# Opened at the counter, then walked out into the open to be looked at.
			#
			# The window is a ScreenGui -- it stays up and stays where it is on screen -- but the
			# Trading House fills the right of frame from the customer's side, and every other
			# desk in the film sits against open ground or a clean interior. One shot with a wall
			# through it is what stops the row reading as a set.
			_stand(Vector3(-22, 0, 22), Vector3(-22, 0, -40))
			await _wait(3.5); _still("swap")
			await _wait(2.0)
		"sitdown":
			# The last shot: him dressed, sat on the corner of the world with the drop in front
			# of him, and the camera going round.
			#
			# The corner is read off the map rather than searched for: Plaza.model.json has a
			# Part called Ground, 140 by 140 at the origin with its top at y = 0, so the edge is
			# seventy out and the corner is (-70, 0, 70) -- the +Z side, where the Earth hangs,
			# across the square from the tree.
			await _dress(SAVED)
			_stand(Vector3(-66, 0, 66), Vector3(-100, 0, 100))
			_clean()
			await _wait(3.0)
			# /sit, the way a player sits down. Humanoid.Sit on its own does nothing to the pose:
			# the engine draws a seated body from its SeatPart, and there is no seat on a cliff
			# edge. Emotes.server.luau registers /sit as a TextChatCommand and poses the legs
			# itself, and it holds until you move -- which suits a shot that ends by standing up.
			world.run_client_chunk("sit", """
local tcs = game:GetService("TextChatService")
local channels = tcs:FindFirstChild("TextChannels")
local ch = channels and (channels:FindFirstChild("RBXGeneral") or channels:GetChildren()[1])
if ch then ch:SendAsync("/sit") print("PROMO asked to sit") else print("PROMO no chat channel to sit with") end
""")
			await _wait(1.5)
			_orbit(Vector3(0, 0, 0), 20, 160, 9, 7.5, 2.6, 1.9, 0.6, 12.0, 55.0, true)
			await _wait(1.0); first = frame; _rich()
			await _wait(3.6); _still("sat")
			await _wait(3.6); _still("sat-round")
			# And on the last beat he gets up and throws a line off the edge. A cast has to be
			# fair (SpaceFishing.fair): past 73.5 out, within 98 studs of him, above the floor.
			# From (-66, 66) a float at (-95, -4, 95) is forty one studs out and well past it.
			world.run_chunk("rod", """
local rs = game:GetService("ReplicatedStorage")
local ch = game:GetService("Players"):GetPlayers()[1].Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
if not hum then print("PROMO nobody to cast") return end
hum.Sit = false
hum:Move(Vector3.new(0, 0, 0.2))   -- moving is what ends a /sit; a nudge is enough
task.wait(0.15)
hum:Move(Vector3.zero)
local rod = rs:FindFirstChild("Made") and rs.Made:FindFirstChild("Fishing Rod")
if rod and not ch:FindFirstChild("Fishing Rod") then hum:AddAccessory(rod:Clone()) end
print("PROMO on his feet with a rod")
""")
			await _wait(1.3)
			world.run_client_chunk("cast", """
local r = game:GetService("ReplicatedStorage"):WaitForChild("FishingRemote")
r:FireServer("charge")
task.wait(0.75)
r:FireServer("cast", Vector3.new(-95, -4, 95))
print("PROMO cast off the edge")
""")
			await _wait(2.4); _still("cast")
			await _wait(0.6)
		"walk":
			# The game as it is played: the HUD, the default camera, a walk across the square.
			_wear(["White Roma"])
			_stand(Vector3(-27, 0, 27), Vector3(-27, 0, -40))
			await _wait(7.0)
			_walk([Vector3(-27, 0, -27), Vector3(27, 0, -27), Vector3(27, 0, 27)])
			await _wait(0.5); first = frame; _rich()
			await _wait(4.0); _still("a")
			await _wait(6.0)
		_:
			printerr("promo: no shot called ", shot)
	_finish(first)

func _finish(first: int) -> void:
	print("CLIP %d %d" % [first, frame])
	quit(0)
