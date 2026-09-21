# What three real clients hear around a fight, read off their own engines.
#
#   godot --headless --path . -s res://tests/melee_heard_test.gd
#
# A bot swings while chunk_peer.gd --voices records the clips each client played. The swing is
# Health.soundNear, heard by everyone within earshot (70 studs); the blow is Health.sound to
# each end of it and nobody else.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const Arrive = preload("res://tests/Arrive.gd")
const PORT := 8820

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var kids: Array[int] = []
var errors: Array[String] = []
var reports := {}
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

## What one watcher heard: clip name -> how many times it started.
func _heard(who: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(reports[who]): return out
	var last := ""
	for line in FileAccess.get_file_as_string(reports[who]).split("\n", false):
		if line.begins_with("HEARD "): last = line.substr(6)
	var bits := last.split(" ")
	if bits.size() > 1:
		for pair in bits[1].split(",", false):
			var kv := pair.split("=")
			# Godot suffixes a Sound node added beside one of the same name ("Sfxmaster2"),
			# so overlapping swings only add up once the digits come off.
			if kv.size() == 2:
				var clip := String(kv[0])
				while clip.length() > 0 and clip[clip.length() - 1] >= "0" and clip[clip.length() - 1] <= "9":
					clip = clip.substr(0, clip.length() - 1)
				out[clip] = int(out.get(clip, 0)) + int(kv[1])
	return out

func _peer(who: String) -> void:
	var report := OS.get_user_data_dir().path_join("melee_%s.txt" % who)
	DirAccess.remove_absolute(report)
	reports[who] = report
	var chunk := OS.get_user_data_dir().path_join("melee_%s.luau" % who)
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("print('SEEN in')")
	f.close()
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/chunk_peer.gd", "--", "--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % report,
		"--voices=1", "--name=%s" % who])
	if pid > 0: kids.append(pid)

func _initialize() -> void:
	print("a fight, heard")
	StandIns.stage("melee")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]); printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)
	for who in ["Near", "Bystander", "Far"]: _peer(who)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/bot.gd", "--", "--name=BFS 9000", "--port=%d" % PORT, "--every=1.6"])
	if pid > 0: kids.append(pid)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("stage", StandIns.chunk("melee"))
		# Every frame, because a hit or a step otherwise walks them off their spots.
		world.run_chunk("places", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local WEAPONS = require(game:GetService("ReplicatedStorage"):WaitForChild("Weapons"))
local SPOTS = {
	["BFS 9000"] = Vector3.new(0, 0, 40),
	Near = Vector3.new(0, 0, 43.5),
	Bystander = Vector3.new(12, 0, 30),
	Far = Vector3.new(0, 0, -45),
}
local function arm(p)
	local ch = p.Character
	if not ch or ch:FindFirstChild("BFS 9000") then return end
	for _, d in ipairs(ch:GetChildren()) do
		if d:IsA("Accoutrement") and WEAPONS[d.Name] then d:Destroy() end
	end
	local acc = Instance.new("Accessory")
	acc.Name = "BFS 9000"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
end
RunService.Heartbeat:Connect(function()
	for _, p in ipairs(Players:GetPlayers()) do
		local spot = SPOTS[p.Name]
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if spot and root then
			local at = Vector3.new(spot.X, root.Position.Y, spot.Z)
			-- The swinger faces the one it is swinging at; everyone else faces it.
			local toward = p.Name == "BFS 9000" and Vector3.new(0, at.Y, 60) or Vector3.new(0, at.Y, 40)
			root.CFrame = CFrame.lookAt(at, toward)
			root.AssemblyLinearVelocity = Vector3.zero
			if p.Name == "BFS 9000" then arm(p) end
			-- The one being hit is kept alive, so the fight goes on.
			local hum = p.Character:FindFirstChildOfClass("Humanoid")
			if p.Name == "Near" and hum and hum.Health > 0 and hum.Health < 3 then hum.Health = hum.MaxHealth end
		end
	end
end)
print("PLACED")
""")
	elif phase == 1 and t > 50.0:
		phase = 2
		var near := _heard("Near")
		var stand := _heard("Bystander")
		var far := _heard("Far")
		print("    Near heard ", near)
		print("    Bystander heard ", stand)
		print("    Far heard ", far)
		var swings_near := int(near.get("Sfxmaster", 0))
		var swings_stand := int(stand.get("Sfxmaster", 0))
		check(swings_near >= 5, "in reach, the swings are heard: %d" % swings_near)
		check(int(near.get("Sfxhurt", 0)) + int(near.get("Sfxstronghit", 0)) >= 2,
			"and the one being hit hears themselves hurt: %d" % (int(near.get("Sfxhurt", 0)) + int(near.get("Sfxstronghit", 0))))
		check(swings_stand >= 5 and abs(swings_stand - swings_near) <= 2,
			"a bystander in earshot hears the same swings: %d against %d" % [swings_stand, swings_near])
		check(int(stand.get("Sfxhurt", 0)) == 0 and int(stand.get("Sfxenemyhit", 0)) == 0,
			"but not the blows, which are only for the two in the fight: %s" % str(stand))
		check(far.is_empty() or (int(far.get("Sfxmaster", 0)) == 0 and int(far.get("Sfxhurt", 0)) == 0),
			"past earshot, none of it: %s" % str(far))
		check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
		for pid in kids: OS.kill(pid)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
