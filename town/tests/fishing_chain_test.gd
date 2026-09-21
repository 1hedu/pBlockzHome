# Space fishing against the local dev chain, nothing stood in: the Fishing contract decides the
# bite and the catch, and the player's own wallet signs every cast and reel.
#
#   node scripts/dev-chain.js --block-time 2        (in another shell, and leave it running)
#   PBLOCKZ_RPC_URL=http://127.0.0.1:8545 godot --path . -s res://tests/fishing_chain_test.gd -- <shots dir>
#
# Windowed, for the clicks; the confirm prompt is off because nobody is there to press it.
# The Everliving Fish can be found once per chain, so on a chain that has given it up that half
# is skipped.
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
	print("space fishing on the dev chain")
	if OS.get_environment("PBLOCKZ_RPC_URL") == "":
		printerr("  FAIL set PBLOCKZ_RPC_URL to the dev chain (node scripts/dev-chain.js prints it)")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").confirm_purchases = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("fishing:") or line.begins_with("TEST") or line.begins_with("NEWS"): print("    ", line))
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
	await create_timer(0.3).timeout

func _aim() -> void:
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(Vector3.new(0, 12, %f), Vector3.new(0, -3, %f))
""" % [EDGE_Z - 16, EDGE_Z + 19])
	await create_timer(0.5).timeout

func _server(body: String) -> String:
	said = said.filter(func(l): return not l.begins_with("TEST "))
	world.run_chunk("t", """
local player = game:GetService("Players"):GetPlayers()[1]
local Angling = require(game:GetService("ServerScriptService").Angling)
""" + body)
	await create_timer(0.5).timeout
	return _last("TEST ")

## One whole go: cast, wait for the bite, reel.
func _fish(before_reel: Callable = Callable()) -> String:
	said = said.filter(func(l): return not l.begins_with("fishing:"))
	await _click()
	if not await _wait_for("fishing: Waiting for a bite", 60.0):
		return "never cast (%s)" % _last("fishing: ")
	if before_reel.is_valid(): await before_reel.call()
	if not await _wait_for("fishing: Something's biting", 60.0):
		return "never bit (%s)" % _last("fishing: ")
	await _click()
	if not await _wait_for("fishing: You caught", 60.0):
		return "no catch (%s)" % _last("fishing: ")
	return _last("fishing: ")

## The text of one leaderboard row; the twelve seconds are the board's own reads off the chain.
func _board(row: String) -> String:
	await _server("game:GetService('ReplicatedStorage').FunRemote:FireClient(player, 'fishboard')")
	await create_timer(12.0).timeout
	said = said.filter(func(l): return not l.begins_with("TEST "))
	world.run_client_chunk("read", """
local board = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("FishBoard")
local rowFrame = board and board:FindFirstChild("%s", true)
local bits = {}
if rowFrame then
	for _, d in ipairs(rowFrame:GetDescendants()) do
		if d:IsA("TextLabel") and d.Name ~= "Shadow" and d.Text ~= "" then table.insert(bits, d.Text) end
	end
end
print("TEST " .. table.concat(bits, " | "))
board.Enabled = false
""" % row)
	await create_timer(0.5).timeout
	return _last("TEST ")

func _run() -> void:
	await create_timer(12.0).timeout
	DisplayServer.window_move_to_foreground()
	# 'fishing' on FunRemote is Funmaster Mike handing the rod over; the shot is his notification.
	world.run_client_chunk("ask", "game:GetService('ReplicatedStorage'):WaitForChild('FunRemote'):FireServer('fishing')")
	await create_timer(1.5).timeout
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_rod_notification.png"))
	var address := await _server("""
local root = player.Character.HumanoidRootPart
root.Anchored = true
root.CFrame = CFrame.lookAt(Vector3.new(0, 3, %f), Vector3.new(0, 3, %f + 10))
print("TEST " .. tostring(player:GetAttribute("WalletAddress")))
""" % [EDGE_Z, EDGE_Z])
	print("    angler ", address)
	world.run_client_chunk("news", """
game:GetService("ReplicatedStorage"):WaitForChild("CombatNews").OnClientEvent:Connect(function(text) print("NEWS " .. tostring(text)) end)
""")
	check(address.begins_with("0x"), "the player is signed in with a wallet (%s)" % address)
	world.run_client_chunk("unwear", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('remove', 'Dysnomia Rod')")
	await create_timer(1.0).timeout
	await _aim()
	await _click()          # the press a window swallows after it comes forward
	world.run_client_chunk("wear", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('wear', 'Dysnomia Rod')")
	await create_timer(1.5).timeout

	var before := await _server("""
Angling.readCatches(player)
local n = 0
for s = 0, 9 do n += Angling.caught(player, s) end
print("TEST " .. n)
""")
	var got := await _fish()
	print("    first go: ", got)
	check(got.begins_with("You caught"), "cast, bite and reel on chain land a fish (%s)" % got)
	var after := await _server("""
local n = 0
for s = 0, 9 do n += Angling.caught(player, s) end
print("TEST " .. n)
""")
	check(int(after) == int(before) + 1, "the contract counts one more fish for them (%s -> %s)" % [before, after])
	get_root().get_texture().get_image().save_png(shots.path_join("fishing_chain_caught.png"))

	var species := got.trim_prefix("You caught a ").trim_prefix("You caught an ").trim_suffix("!")
	var row := await _board("Row%d" % _species_index(species))
	check(row.contains("1.") and row.contains("caught"), "the leaderboard, read off the chain, has the catch (%s)" % row)

	await create_timer(2.0).timeout
	said = said.filter(func(l): return not l.begins_with("fishing:"))
	await _click()
	check(await _wait_for("fishing: Waiting for a bite", 60.0), "another cast goes out")
	var cast_at := await _server("""
local m = workspace.SpaceFishing:FindFirstChild(player.Name)
print("TEST " .. (m and string.format("%.1f,%.1f", m.PrimaryPart.Position.X, m.PrimaryPart.Position.Z) or "none"))
""")
	world.run_client_chunk("down", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('remove', 'Dysnomia Rod')")
	await create_timer(2.0).timeout
	var gone := await _server("print('TEST ' .. tostring(workspace.SpaceFishing:FindFirstChild(player.Name) ~= nil))")
	world.run_client_chunk("up", "game:GetService('ReplicatedStorage').WardrobeRemote:FireServer('wear', 'Dysnomia Rod')")
	check(await _wait_for("fishing: Your line is still out", 20.0), "picking the rod up again finds the line still out")
	await create_timer(2.0).timeout
	var back_at := await _server("""
local m = workspace.SpaceFishing:FindFirstChild(player.Name)
print("TEST " .. (m and string.format("%.1f,%.1f", m.PrimaryPart.Position.X, m.PrimaryPart.Position.Z) or "none"))
""")
	check(gone == "false" and back_at == cast_at and back_at != "none", "and draws it back where it was cast (%s -> %s)" % [cast_at, back_at])
	if not _heard("biting"):
		await _wait_for("fishing: Something's biting", 60.0)
	await _click()
	check(await _wait_for("fishing: You caught", 60.0), "and it can still be reeled in (%s)" % _last("fishing: "))

	var queued := {"out": ""}
	var discover := func() -> void:
		var out := []
		OS.execute("node", [ProjectSettings.globalize_path("res://../../../scripts/dev-chain.js"), "discover", address], out, true)
		queued.out = "".join(out).strip_edges()
		print("    ", queued.out)
	await create_timer(2.0).timeout
	var found := await _fish(discover)
	if String(queued.out).contains("already found"):
		print("    (the Everliving Fish was found on this chain already; skipping that half)")
	else:
		check(String(queued.out).begins_with("queued"), "the next reel is queued to find it")
		check(found == "You caught an Everliving Fish!", "the reel finds the Everliving Fish (%s)" % found)
		await create_timer(4.0).timeout
		said = said.filter(func(l): return not l.begins_with("TEST "))
		world.run_client_chunk("offer", """
local offer = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("EverlivingOffer")
local words = offer and offer:FindFirstChild("Words", true)
local mint = offer and offer:FindFirstChild("Mint", true)
print("TEST " .. tostring(offer and offer.Enabled) .. "|" .. tostring(words and words.Text:sub(1, 48)) .. "|"
	.. (mint and string.format("%d,%d", mint.AbsolutePosition.X + mint.AbsoluteSize.X / 2, mint.AbsolutePosition.Y + mint.AbsoluteSize.Y / 2) or "-"))
""")
		await create_timer(0.5).timeout
		var offer := _last("TEST ").split("|")
		check(offer.size() == 3 and offer[0] == "true" and offer[1].begins_with("Congratulations, you caught the Everliving Fish!"),
			"catching it offers the choice to mint (%s)" % _last("TEST "))
		check(not _heard("NEWS"), "and nothing is announced before they choose")
		get_root().get_texture().get_image().save_png(shots.path_join("fishing_chain_offer.png"))
		if offer.size() == 3 and offer[2].contains(","):
			var xy := offer[2].split(",")
			var at := Vector2(float(xy[0]), float(xy[1]))
			for n in 2:   # the first press after a panel opens can be swallowed
				Input.warp_mouse(at)
				for pressed in [true, false]:
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_LEFT
					e.pressed = pressed
					e.position = at
					e.global_position = at
					Input.parse_input_event(e)
					await create_timer(0.15).timeout
				if _heard("NEWS") or _heard("fishing: The Everliving Fish is yours"): break
				await create_timer(0.6).timeout
		check(await _wait_for("NEWS", 40.0) and _last("NEWS ").ends_with("unlocked it for everyone!"), "minting it tells the town who discovered it (%s)" % _last("NEWS "))
		var top := await _board("Row9")
		check(top.contains("Everliving Fish") and top.contains("found by"), "the leaderboard's top row names the finder (%s)" % top)
		get_root().get_texture().get_image().save_png(shots.path_join("fishing_chain_everliving.png"))

	print("%d passed, %d failed" % [passed, failed])
	print("  -> ", ProjectSettings.globalize_path(shots))
	quit(1 if failed > 0 else 0)

func _species_index(name: String) -> int:
	var names := ["Red Fish", "Magenta Fish", "Purple Fish", "Blue Fish", "Cyan Fish", "Yellow Fish", "Orange Fish", "Indigo Fish", "Green Fish", "Everliving Fish"]
	var i := names.find(name)
	return i if i >= 0 else 0
