# Casting off the edge of the map and reeling a fish in, driven by real clicks.
#
#   godot --path . -s res://tests/fishing_cast_test.gd -- <shots dir>
#
# Windowed and in the foreground: a click is a ray through the pixel under the pointer, and a
# headless window has no pixels. No Fishing contract is deployed, so both sides of it are stood in
# for below: OwnWallet.request on the client, Ledger.request on the server.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const EDGE_Z := 66.0

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var shots := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("casting and reeling")
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("fishing:") or line.begins_with("FAKE") or line.begins_with("LINE"): print("    ", line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _heard(needle: String) -> bool:
	for line in said:
		if line.contains(needle): return true
	return false

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _wait_for(needle: String, seconds: float) -> bool:
	var t := 0.0
	while t < seconds:
		if _heard(needle): return true
		await create_timer(0.25).timeout
		t += 0.25
	return _heard(needle)

func _click() -> void:
	var at := Vector2(get_root().size) / 2.0
	Input.warp_mouse(at)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	Input.parse_input_event(move)
	await create_timer(0.2).timeout
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = at
		e.global_position = at
		Input.parse_input_event(e)
		await create_timer(0.1).timeout
	await create_timer(0.4).timeout

## Holds the button down for `seconds`. WOUND is the shoulder angle, read before the release.
func _hold(seconds: float) -> void:
	var at := Vector2(get_root().size) / 2.0
	Input.warp_mouse(at)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	down.global_position = at
	Input.parse_input_event(down)
	await create_timer(seconds).timeout
	said = said.filter(func(l): return not l.begins_with("WOUND "))
	world.run_chunk("wound", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local s = ch.Torso["Right Shoulder"]
local _, _, z = s.Transform:ToEulerAnglesXYZ()
local look = s.Transform.LookVector
print(("WOUND %.1f"):format(math.deg(math.acos(math.clamp(s.Transform.UpVector.Y, -1, 1)))))
""")
	await create_timer(0.1).timeout
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	up.global_position = at
	Input.parse_input_event(up)
	await create_timer(1.2).timeout

## The angler's WalkSpeed and JumpPower, space-separated, as the server has them.
func _held() -> String:
	said = said.filter(func(l): return not l.begins_with("HELD "))
	world.run_chunk("held", """
local hum = game:GetService("Players"):GetPlayers()[1].Character:FindFirstChildOfClass("Humanoid")
print(("HELD %g %g"):format(hum.WalkSpeed, hum.JumpPower))
""")
	await create_timer(0.4).timeout
	return _last("HELD ")

## Clicks a named button in the fishing HUD, twice: the first press is sometimes swallowed.
func _press(button: String) -> void:
	said = said.filter(func(l): return not l.begins_with("AT "))
	world.run_client_chunk("at", """
local b = game:GetService("Players").LocalPlayer.PlayerGui.FishingHud:FindFirstChild("%s")
print("AT " .. (b and b.Visible and string.format("%%d,%%d", math.floor(b.AbsolutePosition.X + b.AbsoluteSize.X / 2), math.floor(b.AbsolutePosition.Y + b.AbsoluteSize.Y / 2)) or "-"))
""" % button)
	await create_timer(0.4).timeout
	var xy := _last("AT ").split(",")
	if xy.size() != 2: return
	var at := Vector2(float(xy[0]), float(xy[1]))
	for n in 2:
		Input.warp_mouse(at)
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.position = at
			e.global_position = at
			Input.parse_input_event(e)
			await create_timer(0.15).timeout
		if _heard("fishing: You let the line go"): return
		await create_timer(0.5).timeout

func _look(from: Vector3, at: Vector3) -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(%f, %f, %f), Vector3.new(%f, %f, %f))
""" % [from.x, from.y, from.z, at.x, at.y, at.z])
	await create_timer(0.5).timeout

## The camera a click is aimed through: behind the player, looking out past them into space.
func _aim() -> void:
	await _look(Vector3(0, 12, EDGE_Z - 16), Vector3(0, -3, EDGE_Z + 19))

## The camera for the screenshots: off to the side, player, line and float all in frame.
func _side() -> void:
	await _look(Vector3(26, 7, EDGE_Z + 6), Vector3(0, -1, EDGE_Z + 10))
	await create_timer(0.6).timeout

func _line() -> String:
	said = said.filter(func(l): return not l.begins_with("LINE "))
	world.run_chunk("line", """
local folder = workspace:FindFirstChild("SpaceFishing")
local player = game:GetService("Players"):GetPlayers()[1]
local m = folder and folder:FindFirstChild(player.Name)
local rod = player.Character and player.Character:FindFirstChild("Dysnomia Rod")
local hang = rod and rod:FindFirstChild("Line", true)
if not m then
	print("LINE none rodline=" .. tostring(hang and hang.Transparency))
else
	local p = m.PrimaryPart.Position
	local beam = m:FindFirstChildOfClass("Beam")
	print(("LINE %s at %.1f,%.1f,%.1f beam=%s rodline=%s"):format(tostring(m:GetAttribute("State")), p.X, p.Y, p.Z,
		tostring(beam ~= nil and beam.Attachment0 ~= nil and beam.Attachment1 ~= nil), tostring(hang and hang.Transparency)))
end
""")
	await create_timer(0.4).timeout
	return _last("LINE ")

func _run() -> void:
	await create_timer(9.0).timeout
	DisplayServer.window_move_to_foreground()
	await create_timer(0.5).timeout

	# Server side: Ledger.request answers caughtOf from the FakeCaught attribute, one count per species.
	world.run_chunk("setup", """
local rs = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
local store = game:GetService("ServerStorage")
local player = game:GetService("Players"):GetPlayers()[1]
if not player:GetAttribute("WalletAddress") or player:GetAttribute("WalletAddress") == "" then
	player:SetAttribute("WalletAddress", "0x00000000000000000000000000000000F15Ab0B0")
end
local Contracts = require(rs.Contracts)
Contracts.Fishing = "0x000000000000000000000000000000000000F15B"
local Ledger = require(sss.Ledger)
local real = Ledger.request
Ledger.request = function(req, timeout)
	if req.to == Contracts.Fishing then
		if req.fn == "caughtOf(address)" then
			local w = {}
			for n in (store:GetAttribute("FakeCaught") or "0,0,0,0,0,0,0,0,0,0"):gmatch("%%d+") do table.insert(w, tonumber(n)) end
			return { ok = true, words = w, data = "0x" .. string.rep("0", 640) }
		elseif req.fn == "discoverer()" then
			return { ok = true, words = { "0x0000000000000000000000000000000000000000" } }
		end
	end
	return real(req, timeout)
end
store:SetAttribute("FakeCaught", "0,0,0,0,0,0,0,0,0,0")
require(sss.Angling).giveRod(player)
local root = player.Character.HumanoidRootPart
root.Anchored = true
root.CFrame = CFrame.lookAt(Vector3.new(0, 3, %f), Vector3.new(0, 3, %f + 10))
print("SETUP done")
""" % [EDGE_Z, EDGE_Z])
	# Client side: OwnWallet.request against a chain of its own, a block every two seconds.
	world.run_client_chunk("wallet", """
local rs = game:GetService("ReplicatedStorage")
local OwnWallet = require(rs.OwnWallet)
local Contracts = require(rs.Contracts)
Contracts.Fishing = "0x000000000000000000000000000000000000F15B"
local t0 = os.clock()
local function block() return 100 + math.floor((os.clock() - t0) / 2) end
local line = nil
OwnWallet.request = function(req, timeout)
	if req.action == "write" then
		task.wait(1)
		local b = block()
		if req.fn == "cast()" then
			if line and b <= line.last then return { ok = false, message = "it reverted on chain" } end
			line = { bite = b + 2, last = b + 5 }
			print("FAKE cast at " .. b .. ", bite " .. line.bite .. ", last " .. line.last)
			return { ok = true, hash = "0x1" }
		elseif req.fn == "reel()" then
			if not line or b < line.bite then return { ok = false, message = "it reverted on chain" } end
			local got = b <= line.last
			line = nil
			print("FAKE reel " .. (got and "caught" or "gotaway") .. " at " .. b)
			return { ok = true, hash = "0x2" }
		end
	elseif req.action == "read" and req.fn == "lineOf(address)" then
		task.wait(0.1)
		local b = block()
		if line then return { ok = true, words = { true, line.bite, line.last, b } } end
		return { ok = true, words = { false, 0, 0, b } }
	end
	return { ok = false, message = "not stood in for: " .. tostring(req.fn) }
end
print("FAKE wallet ready")
""")
	await create_timer(1.0).timeout
	# The first press after the window comes forward is swallowed: spend it with no rod in hand.
	# The bag wears the rod by itself the first time it has one, hence the remove before the wear.
	world.run_client_chunk("unwear", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('remove', 'Dysnomia Rod')")
	await create_timer(1.5).timeout
	await _look(Vector3(0, 12, EDGE_Z - 16), Vector3(0, -3, EDGE_Z + 19))
	await _click()
	said.clear()
	world.run_client_chunk("wear", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('wear', 'Dysnomia Rod')")
	await create_timer(1.5).timeout

	# CLEAR prints: line height over the edge from a far cast, the town's top, the far and near float
	# heights, and where a full-depth sink from the edge lands.
	said = said.filter(func(l): return not l.begins_with("CLEAR "))
	world.run_chunk("clear", """
local SpaceFishing = require(game:GetService("ReplicatedStorage").SpaceFishing)
local edge, top = SpaceFishing.edge()
local function lineAtEdge(fromZ, out)
	local from = Vector3.new(0, 3, fromZ)
	local y = SpaceFishing.floatHeight(from, Vector3.new(0, 0, 1), out)
	local tipY = from.Y + 3
	local along = (edge - fromZ) / out
	return tipY + (y - tipY) * along, y
end
local farEdge, farY = lineAtEdge(%f, 90)
local nearEdge, nearY = lineAtEdge(%f, 90)
print(string.format("CLEAR %%.2f %%.2f %%.2f %%.2f %%.2f", farEdge, top, farY, nearY, top - SpaceFishing.depth(90)))
""" % [EDGE_Z - 46.0, EDGE_Z])
	await create_timer(0.5).timeout
	var clear := _last("CLEAR ").split(" ")
	check(clear.size() == 5 and float(clear[0]) >= float(clear[1]) + 1.9,
		"cast from well back, the line passes over the edge of the town (%s)" % _last("CLEAR "))
	check(clear.size() == 5 and absf(float(clear[3]) - float(clear[4])) < 0.01,
		"cast from the edge, the float sinks its full depth (%s)" % _last("CLEAR "))

	await _look(Vector3(0, 14, EDGE_Z - 20), Vector3(0, 0, EDGE_Z - 40))
	await _click()
	check(_heard("fishing: Cast off the edge of the map."), "clicking the town says to cast off the edge")
	check((await _line()).begins_with("none"), "and puts nothing out")

	await _look(Vector3(0, 12, EDGE_Z - 16), Vector3(0, -3, EDGE_Z + 19))
	await _click()
	await create_timer(1.0).timeout
	var out := await _line()
	var parts := out.split(" ")
	var z := 0.0
	if parts.size() >= 3:
		var xyz := parts[2].split(",")
		if xyz.size() == 3: z = float(xyz[2])
	check(out.contains("beam=true"), "clicking off the edge puts a float out with a line to it (%s)" % out)
	var y := 0.0
	if parts.size() >= 3 and parts[2].split(",").size() == 3: y = float(parts[2].split(",")[1])
	check(z > 74.0 and z < EDGE_Z + 30.0 and y < -5.0, "a tap lands a short way out past the edge, under the town (z %.1f, y %.1f)" % [z, y])
	check(out.contains("rodline=1"), "and the rod's resting line is hidden")
	await _side()
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_line_out.png"))
	# Close up on the float, which should read half red over half white.
	await _look(Vector3(3.5, y + 1.2, z - 1.0), Vector3(0, y, z))
	await create_timer(0.4).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_float.png"))
	await _aim()

	check(await _wait_for("FAKE cast", 6.0), "the player's wallet is asked to cast")
	check(await _wait_for("fishing: Waiting for a bite", 8.0), "the line waits for a bite")
	check(await _wait_for("fishing: Something's biting!", 12.0), "then something bites")
	check((await _line()).begins_with("bite"), "and the float says so for everybody")
	await _side()
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_bite.png"))
	await _aim()

	await _click()
	check(await _wait_for("FAKE reel caught", 5.0), "clicking on the bite asks the wallet to reel, in time")
	world.run_chunk("caught", "game:GetService('ServerStorage'):SetAttribute('FakeCaught', '0,0,0,0,1,0,0,0,0,0')")
	await _side()
	check(await _wait_for("fishing: You caught a Cyan Fish!", 10.0), "the server reads the catch and says what it was")
	await create_timer(1.4).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_caught.png"))
	said = said.filter(func(l): return not l.begins_with("SHOW "))
	world.run_chunk("show", """
local m = workspace.SpaceFishing:FindFirstChild("Caught")
print("SHOW " .. (m and string.format("%.1f", m:GetScale()) or "none"))
if m then print("SERVERFISH " .. tostring(m:GetPivot().Position) .. " handle " .. tostring(m.PrimaryPart and m.PrimaryPart.Position)) end
""")
	world.run_client_chunk("cam", """
local m = workspace.SpaceFishing:FindFirstChild("Caught")
print('CLIENTFISH ' .. (m and (tostring(m:GetPivot().Position) .. ' parts ' .. #m:GetDescendants()) or 'none') .. ' cam ' .. tostring(workspace.CurrentCamera.CFrame.Position))
""")
	await create_timer(0.4).timeout
	check(_last("SHOW ") == "3.0", "the fish comes up three times its size (%s)" % _last("SHOW "))
	await create_timer(1.5).timeout
	var after := await _line()
	check(after.begins_with("none") and after.contains("rodline=0.3"), "the line comes in and the rod's own line is back (%s)" % after)
	said.clear()
	world.run_chunk("bag", "print('BAG cyan=' .. require(game:GetService('ServerScriptService').Angling).caught(game:GetService('Players'):GetPlayers()[1], 4))")
	await create_timer(0.5).timeout
	check(_last("BAG ") == "cyan=1", "and the fish is in the bag (%s)" % _last("BAG "))

	# The real holdings land after the reel, and an outfit takes off what it does not name: the rod
	# giveRod handed out goes with them, so it has to be put back on. Same in play -- the rod stays
	# off until the player picks it out of the bag.
	world.run_client_chunk("rod", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('wear', 'Dysnomia Rod')")
	await create_timer(2.0).timeout
	# The hold below sits past CHARGE_FULL's 1 s so reach() takes its FULL_FLOOR..1 roll
	await _aim()
	await create_timer(3.5).timeout
	said.clear()
	await _hold(1.6)
	var thrown := await _line()
	var tz := 0.0
	var tparts := thrown.split(" ")
	if tparts.size() >= 3 and tparts[2].split(",").size() == 3: tz = float(tparts[2].split(",")[2])
	check(_last("WOUND ").length() > 0 and float(_last("WOUND ")) > 100.0, "holding it winds him up, the rod back over his shoulder (%s degrees)" % _last("WOUND "))
	check(tz >= EDGE_Z + 90.0 * 0.6 - 1.0 and tz <= EDGE_Z + 91.0, "a full charge throws it between 60%% and all the way out (z %.1f)" % tz)
	await _side()
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_full_cast.png"))
	await _aim()
	check(await _wait_for("fishing: Something's biting!", 20.0), "a second cast bites")
	var holding := await _held()
	check(holding == "0 0", "while the line is out, the angler is held where they stand (%s)" % holding)
	check(await _wait_for("fishing: It got away.", 16.0), "and left alone past its window, it gets away")
	await create_timer(0.5).timeout
	check((await _line()).begins_with("none"), "taking the line in")
	var freed := await _held()
	check(freed != "0 0" and freed.split(" ")[0].to_float() > 0, "and letting them go again (%s)" % freed)

	await create_timer(4.0).timeout
	said.clear()
	await _click()
	check(await _wait_for("fishing: Waiting for a bite", 12.0), "another cast goes out")
	await _press("Cancel")
	check(_heard("fishing: You let the line go"), "Cancel lets the line go")
	await create_timer(0.8).timeout
	var let_go := await _line()
	var walk := await _held()
	check(let_go.begins_with("none") and walk.split(" ")[0].to_float() > 0, "and the angler can walk away (%s, %s)" % [let_go, walk])
	said.clear()
	await _aim()
	await _click()
	check(await _wait_for("fishing: Your line is still out", 12.0), "fishing again picks the line back up rather than casting over it")
	check((await _line()).begins_with("out") or _heard("biting"), "drawn back out")

	world.run_client_chunk("off", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('remove', 'Dysnomia Rod')")
	await create_timer(2.0).timeout
	check((await _line()).begins_with("none"), "putting the rod away takes the line in")

	print("%d passed, %d failed" % [passed, failed])
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(1 if failed > 0 else 0)
