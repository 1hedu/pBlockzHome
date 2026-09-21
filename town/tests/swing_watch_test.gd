# A player clicks, swings at somebody, and the hearts over their head go down on his own screen.
# Windowed and driven by real mouse events: the attacker's path runs through
# Weapons.client.luau's draw gate and panel refusal, which firing WeaponRemote would skip.
#
#   godot --path . -s res://tests/swing_watch_test.gd -- [<shots dir>] [--port=8892]
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var shots := ""
var said: Array[String] = []
var errors: Array[String] = []
var kids: Array[int] = []

const PORT := 8892
const TARGET := "Spoonie"     # the bot being hit; serve_bots arms it by name
const ME := "Swinger"             # serve_fight arms anybody, so this name is free

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var i := String(line).find(prefix)
		if i >= 0:
			out.append(String(line).substr(i + prefix.length()).strip_edges())
	return out

func _last(prefix: String) -> String:
	var rows := _lines(prefix)
	return String(rows[rows.size() - 1]) if rows.size() > 0 else ""

func _initialize() -> void:
	print("a player swings, and watches the hearts on his own screen")
	var args := OS.get_cmdline_user_args()
	shots = args[0] if args.size() > 0 and not String(args[0]).begins_with("--") else "user://shots"
	DirAccess.make_dir_recursive_absolute(shots)

	var here := ProjectSettings.globalize_path("res://")
	var srv := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", here, "-s", "res://tests/serve_fight.gd", "--", "--port=%d" % PORT])
	if srv > 0: kids.append(srv)

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = PORT
	world.player_name = ME
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	_run()

func _spawnTarget() -> void:
	var pid := OS.create_process(OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/bot.gd", "--", "--name=%s" % TARGET, "--port=%d" % PORT,
		"--every=99"])          # it stands there rather than swinging back
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## A real press and release of the left button, where the pointer already is. Weapons.client.luau
## listens on UserInputService.InputBegan and refuses anything the GUI has handled, so the event
## has to be genuine and the window has to have focus.
func _click() -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = Vector2(40, 40)
		e.global_position = Vector2(40, 40)
		Input.parse_input_event(e)
		await create_timer(0.1).timeout

## What this client's own screen says about the target's row, right now.
func _readRow() -> void:
	said.clear()
	world.run_chunk("row", ("""
local Players = game:GetService("Players")
local me = Players.LocalPlayer
local screen = me:WaitForChild("PlayerGui"):FindFirstChild("Overhead")
if not screen then print("ROW no Overhead screen") return end
local board = screen:FindFirstChild("Overhead" .. "TARGET_NAME")
if not board then print("ROW no board for TARGET_NAME") return end
local full, shown = 0, false
for _, d in ipairs(board:GetDescendants()) do
	if d:IsA("Frame") and d.Name == "Window" and d.Visible then full += d.Size.X.Scale end
	if d:IsA("Frame") and d.Name == "Hearts" then shown = d.Visible end
end
print(("ROW halves=%d shown=%s"):format(math.floor(full * 2 + 0.5), tostring(shown)))
""").replace("TARGET_NAME", TARGET))
	await create_timer(1.2).timeout

func _run() -> void:
	# The town, then the target, then me: a client that joins before the server is up never
	# arrives.
	await create_timer(22.0).timeout
	_spawnTarget()
	await create_timer(18.0).timeout

	DisplayServer.window_move_to_foreground()
	await create_timer(1.0).timeout

	# Held in front of the target every Heartbeat: a body its own client simulates drifts back
	# otherwise. 4.2 studs is inside a BFS 9000's reach.
	said.clear()
	world.run_chunk("stand", ("""
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local them = Players:FindFirstChild("TARGET_NAME")
if not them or not them.Character then print("STAND nobody to hit") return end
local theirs = them.Character:WaitForChild("HumanoidRootPart")
local mine = me.Character:WaitForChild("HumanoidRootPart")
task.spawn(function()
	for _ = 1, 1200 do
		RunService.Heartbeat:Wait()
		mine.CFrame = CFrame.new(theirs.Position - theirs.CFrame.LookVector * 4.2
			+ Vector3.new(0, 0.2, 0), theirs.Position)
	end
end)
print(("STAND in front of %s, holding %s"):format(them.Name,
	me.Character:FindFirstChildOfClass("Accoutrement") and "something" or "NOTHING"))
""").replace("TARGET_NAME", TARGET))
	await create_timer(2.5).timeout
	var stood := _last("STAND ")
	check(stood != "", "there is somebody to hit: %s" % stood)

	# serve_bots arms a player named after a weapon on its own clock, so wait for the stick: the
	# server refuses a swing from empty hands, which would read here as hearts that never moved.
	var armed := stood.find("holding something") >= 0
	for _i in 20:
		if armed: break
		await create_timer(1.0).timeout
		said.clear()
		world.run_chunk("armed", """
local Players = game:GetService("Players")
local me = Players.LocalPlayer
print(("STAND holding %s"):format(
	me.Character and me.Character:FindFirstChildOfClass("Accoutrement") and "something" or "NOTHING"))
""")
		await create_timer(0.4).timeout
		armed = _last("STAND ").find("holding something") >= 0
	check(armed, "this client has a weapon, so a click is a swing")
	if not armed:
		_finish()
		return

	await _readRow()
	var before := _last("ROW ")
	check(before.find("halves=") >= 0, "their row is on my screen before I swing: %s" % before)
	var startHalves := 0
	if before.find("halves=") >= 0:
		startHalves = int(before.substr(before.find("halves=") + 7).split(" ")[0])

	# The window taking focus swallows the first press, as gui_click_test's header explains, so one
	# click is spent before measuring.
	await _click()
	await create_timer(1.0).timeout

	# One click is one swing; holding does nothing. Six of them, with time for each to land.
	for i in 6:
		await _click()
		await create_timer(1.1).timeout

	await _readRow()
	var after := _last("ROW ")
	check(after != "", "the row is still on my screen after the fight: %s" % after)

	var img := get_root().get_texture().get_image()
	img.save_png(shots.path_join("swing.png"))
	print("  -> swing.png")

	# The replicated Humanoid.Health for the same body, to hold against the row.
	said.clear()
	world.run_chunk("theirs", ("""
local Players = game:GetService("Players")
local them = Players:FindFirstChild("TARGET_NAME")
local hum = them and them.Character and them.Character:FindFirstChildOfClass("Humanoid")
print(("MINE they read %s of %s on my machine"):format(
	hum and tostring(hum.Health) or "?", hum and tostring(hum.MaxHealth) or "?"))
""").replace("TARGET_NAME", TARGET))
	await create_timer(1.5).timeout
	print("    ", _last("MINE "))

	var half := -1
	if after.find("halves=") >= 0:
		half = int(after.substr(after.find("halves=") + 7).split(" ")[0])
	# Against the starting count, not a full bar: a dummy already in a fight is not on six.
	check(half >= 0 and half < startHalves,
		"the hearts over their head went DOWN on my own screen when I hit them: %d, was %d"
			% [half, startHalves])
	_finish()
