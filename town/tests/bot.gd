# One bot: a real client joining a real server and firing WeaponRemote, which only a client may
# do -- the server refuses input from anywhere else. --name is the weapon serve_bots.gd hands
# out; "Runner" gets none and is walked by the server instead.
#
#   godot --headless --path . -s res://tests/bot.gd -- --name="HEX Torch" [--port=8800] [--every=1.6]
#   godot --headless --path . -s res://tests/bot.gd -- --name=Cane --every=9 --holds=0,6.3
#   godot --headless --path . -s res://tests/bot.gd -- --name=Wanderer --roam=1 --host=play.safewrap.xyz
#
# --holds: seconds to hold the button, one per click in turn, 0 a plain click, for a weapon that
# charges while it is down. --walk=<click>:<from>:<to> holds W from/to seconds into that click's
# hold, clicks counted from 0. --roam: the bot walks itself through the place's controls, so its
# own machine simulates it and its hitbox is a player's; a server-walked body has neither and, to
# every other client, stands still with its limbs left wherever they last were. The live town hands
# out no weapons, so roaming is the only thing a bot can do there.
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var since := 0.0
var started := false
var every := 1.6
var who := "Spoonie"
var holds: Array[float] = []
var clicks := 0
var letGoAt := -1.0
var walkClick := -1
var walkFrom := 0.0
var walkTo := 0.0
var walkStartAt := -1.0
var walkStopAt := -1.0
var roam := false
var roamKey := -1              # the direction key held now, -1 for none
var roamUntil := 0.0
var roamJumpAt := 0.0
var roamToldAt := 0.0
const ROAM_KEYS := [KEY_W, KEY_A, KEY_S, KEY_D]
var roamAt := Vector3.INF          # last position it reported; INF until one arrives
var roamMovedAt := 0.0             # when that last changed
const ROAM_OPPOSITE := { KEY_W: KEY_S, KEY_S: KEY_W, KEY_A: KEY_D, KEY_D: KEY_A }

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	roam = _flag("roam", "") != ""
	every = float(_flag("every", str(every)))
	for h in _flag("holds", "").split(",", false):
		holds.append(float(h))
	var walk := _flag("walk", "").split(":")
	if walk.size() == 3:
		walkClick = int(walk[0]); walkFrom = float(walk[1]); walkTo = float(walk[2])
	# A key per bot, from its name: otherwise every bot signs in as the dev key in .env.testnet,
	# the same address as the person playing.
	if OS.get_environment("PBLOCKZ_PLAYER_KEY") == "":
		OS.set_environment("PBLOCKZ_PLAYER_KEY", PulseBlockzCrypto.keccak256_hex("pulseblockz bot " + who))
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	var main: Node = load("res://Main.tscn").instantiate()
	# Nothing here presses Start, and Arrival.server.luau only loads a character once the intro lifts.
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2                                   # client
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8800"))
	world.player_name = who
	world.script_print.connect(_heard)
	world.default_camera = false                     # headless: nothing to look through
	world.default_controls = false
	main.get_node("Wallet").auto_start = false       # a bot has no wallet
	get_root().add_child(main)
	print("[bot] %s asking %s:%d for the town" % [who, world.server_address, world.server_port])

func _process(delta: float) -> bool:
	t += delta
	if not world.is_server_connected():
		return false
	if not started:
		started = true
		print("[bot] %s is in" % who)
	if roam:
		_roam(delta)
		return false
	if who == "Runner":                              # the server walks this one
		return false
	if walkStartAt >= 0.0 and t >= walkStartAt:
		walkStartAt = -1.0
		_walk(true)
	if walkStopAt >= 0.0 and t >= walkStopAt:
		walkStopAt = -1.0
		_walk(false)
	if letGoAt >= 0.0 and t >= letGoAt:
		letGoAt = -1.0
		_release()
	since += delta
	if since < every:
		return false
	since = 0.0
	# A click carries nothing: the server decides the weapon, whether it is drawn, and what it hits.
	world.run_chunk("swing", """
local rs = game:GetService("ReplicatedStorage")
local r = rs:FindFirstChild("WeaponRemote")
if r then r:FireServer() end
""")
	if not holds.is_empty():
		var hold: float = holds[clicks % holds.size()]
		if clicks == walkClick:
			walkStartAt = t + walkFrom
			walkStopAt = t + walkTo
			print("[bot] %s walks from %.1fs to %.1fs into this hold" % [who, walkFrom, walkTo])
		clicks += 1
		if hold <= 0.0: _release()
		else: letGoAt = t + hold
	return false

## Synthesised key input: Controls.client turns it into Humanoid:Move every frame, so a Move
## called from here would be undone on the next one.
func _key(code: int, on: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = on
	Input.parse_input_event(e)

func _walk(on: bool) -> void:
	_key(KEY_W, on)

func _roam(_delta: float) -> void:
	if t >= roamUntil:
		if roamKey >= 0: _key(roamKey, false)
		roamKey = ROAM_KEYS[randi() % ROAM_KEYS.size()]
		_key(roamKey, true)
		roamUntil = t + randf_range(1.0, 3.0)
	if t >= roamJumpAt:
		_key(KEY_SPACE, true)
		_key(KEY_SPACE, false)
		roamJumpAt = t + randf_range(3.0, 7.0)
	# Stuck -- the fountain basin, a wall -- is six seconds with a key held and the position unchanged.
	if roamAt != Vector3.INF and t - roamMovedAt > 6.0:
		roamMovedAt = t
		if roamKey >= 0: _key(roamKey, false)
		roamKey = ROAM_OPPOSITE.get(roamKey, KEY_S)
		_key(KEY_SPACE, true)
		_key(KEY_SPACE, false)
		_key(roamKey, true)
		roamUntil = t + 2.5
		print("[bot] stuck; jumping and turning back")
	if t >= roamToldAt:
		roamToldAt = t + 2.0
		world.run_client_chunk("where", """
local p = game:GetService("Players").LocalPlayer
local ch = p.Character
local root = ch and ch:FindFirstChild("HumanoidRootPart")
if root then print(("[bot] at %.1f %.1f %.1f"):format(root.Position.X, root.Position.Y, root.Position.Z)) end
""")

## Reads the position back out of the bot's own print -- a headless client has no other channel.
func _heard(_script: String, line: String) -> void:
	var l := String(line)
	if not l.begins_with("[bot] at "): return
	var p := l.substr(9).split(" ")
	if p.size() != 3: return
	var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
	if roamAt == Vector3.INF or at.distance_to(roamAt) > 0.5:
		roamAt = at
		roamMovedAt = t

func _release() -> void:
	world.run_chunk("release", """
local r = game:GetService("ReplicatedStorage"):FindFirstChild("WeaponRemote")
if r then r:FireServer("release") end
""")
