# Walking forward while steering with A / D in a Ctrl + right-drag, over a real connection: the
# client's Controls script writes the turn to the root every frame, and Play Solo orders that
# write differently, so this runs a server against steer_peer.gd in its own process.
#
#   godot --headless --path . -s res://tests/steer_net_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

const PORT := 8842

var world: PulseBlockzWorld
var peer := 0
var t := 0.0
var said: Array[String] = []
var ok := 0
var bad := 0

func check(cond: bool, what: String) -> void:
	if cond: ok += 1
	else: bad += 1
	print("  %s  %s" % ["PASS" if cond else "FAIL", what])

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_print.connect(func(_n, line): said.append(line))
	world.script_error.connect(func(n, e): print("  LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)
	# Past the intro gate: players are let in as they join (tests/Arrive.gd).
	Arrive.now(world)
	peer = OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/steer_peer.gd", "--", "--port=%d" % PORT])

var watching := false

func _process(delta: float) -> bool:
	t += delta
	if not watching and t > 12.0:
		watching = true
		world.run_chunk("watch", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local last, t0 = nil, os.clock()
RunService.Heartbeat:Connect(function()
	local p = Players:FindFirstChild("Steerer")
	local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	if not r then return end
	local now = os.clock() - t0
	if not last or now - last >= 0.1 then
		last = now
		local v = r.CFrame.LookVector
		print(("POSE t=%.2f heading=%.1f x=%.2f z=%.2f"):format(now, math.deg(math.atan2(-v.X, -v.Z)), r.Position.X, r.Position.Z))
	end
end)
""")
	elif t > 60.0:
		_judge()
		return true
	return false

func _judge() -> void:
	OS.kill(peer)
	var poses := []
	for line in said:
		if line.begins_with("POSE "):
			var f := {}
			for part in line.split(" "):
				if part.contains("="): f[part.split("=")[0]] = float(part.split("=")[1])
			poses.append(f)
	var first := -1
	var last := -1
	for i in range(1, poses.size()):
		var d: float = abs(fposmod(poses[i]["heading"] - poses[i - 1]["heading"] + 180.0, 360.0) - 180.0)
		if d > 2.0:
			if first < 0: first = i - 1
			last = i
	check(first >= 0, "the body turned as the server sees it (%d poses)" % poses.size())
	if first < 0:
		print("%d passed, %d failed" % [ok, bad])
		quit(1)
		return
	var a: Dictionary = poses[first]
	var b: Dictionary = poses[last]
	var seconds: float = b["t"] - a["t"]
	var turned := 0.0
	for i in range(first + 1, last + 1):
		turned += abs(fposmod(poses[i]["heading"] - poses[i - 1]["heading"] + 180.0, 360.0) - 180.0)
	var moved := Vector2(b["x"] - a["x"], b["z"] - a["z"]).length()
	# Walking 16 studs a second while turning half a turn a second is a circle about ten studs
	# across, so end to end stays short: sum the per-step path instead.
	var path := 0.0
	for i in range(first + 1, last + 1):
		path += Vector2(poses[i]["x"] - poses[i - 1]["x"], poses[i]["z"] - poses[i - 1]["z"]).length()
	check(turned > 180.0, "steering with D turned him %.0f degrees in %.1fs" % [turned, seconds])
	check(path > 16.0 * seconds * 0.6, "and walking with W he covered ground while he turned: %.1f studs of path in %.1fs, not walking in place" % [path, seconds])
	print("  (end to end %.1f studs)" % moved)
	print("%d passed, %d failed" % [ok, bad])
	quit(0 if bad == 0 else 1)
