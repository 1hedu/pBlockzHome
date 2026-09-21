# Can anybody HEAR the Familiar? Serves a town, drives the real speak() a left-click in the bag
# reaches, and asks a second process (familiar_peer.gd) whether the clip opened on that machine.
# TimeLength is the proxy for audible: a perfectly spelled path pointing at nothing reads nought.
# The structure -- Sound on the pet, reverb, clips in turn, cooldown -- is familiar_voice_test's
# half; this one only asks whether it was heard.
#
#   godot --headless --path . -s res://tests/familiar_heard_test.gd
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var errors: Array[String] = []
var said: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

const PORT := 8893

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		var at := s.find(prefix)
		if at >= 0: return s.substr(at + prefix.length()).strip_edges()
	return ""

func _initialize() -> void:
	print("the Familiar's voice, heard from another machine")
	report = OS.get_user_data_dir().path_join("familiar.txt")
	DirAccess.remove_absolute(report)

	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.auto_join = false
	StandIns.stage("familiar")
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

	var all := ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/familiar_peer.gd", "--",
		"--name=Ear", "--port=%d" % PORT, "--out=%s" % report]
	var pid := OS.create_process(OS.get_executable_path(), all)
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	var heard := ""
	if FileAccess.file_exists(report):
		heard = FileAccess.get_file_as_string(report).strip_edges()
	print("    the client heard: ", heard if heard != "" else "(nothing at all)")

	check(heard.find("seen=true") >= 0,
		"a FamiliarVoice reached the other machine: %s" % heard)
	check(heard.find("loaded=true") >= 0,
		"and the clip actually opened on that machine")
	var length := 0.0
	if heard.find("length=") >= 0:
		length = float(heard.substr(heard.find("length=") + 7).split(" ")[0])
	check(length > 0.05, "and it has a length, so there is something to hear: %.3fs" % length)
	check(heard.find("playing=true") >= 0, "and it was playing")

	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 20.0:
		phase = 1; t = 0.0
		world.run_chunk("standins", StandIns.chunk("familiar"))
	elif phase == 1 and t > 4.0:
		phase = 2; t = 0.0
		# The real Familiar model arrives with a catalogue fetched off chain, which this town has
		# not done; Pets.summon wants only a Model with a BasePart, so a stand-in serves. Which
		# one was used is printed.
		world.run_chunk("speak", """
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pets = require(game:GetService("ServerScriptService").Pets)
local ItemActions = require(game:GetService("ServerScriptService").ItemActions)

local player = Players:FindFirstChild("Ear")
if not player or not player.Character then print("SPEAK nobody to speak to") return end

local function source(name)
	local chain = ReplicatedStorage:FindFirstChild("OnChain")
	local found = chain and chain:FindFirstChild(name)
	if found then return found, "on chain" end
	local made = ReplicatedStorage:FindFirstChild("Made")
	found = made and made:FindFirstChild(name)
	if found then return found, "made" end
	return nil, nil
end

local template, where = source("Familiar")
if not template then
	local m = Instance.new("Model")
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(1, 1, 1)
	body.Parent = m
	m.PrimaryPart = body
	template, where = m, "a stand-in"
end
local model = Pets.summon(player, template, "float")
print(("SPEAK the pet is out (%s): %s"):format(tostring(where), model and model.Name or "NOTHING"))

-- The same call a left-click on the tile makes.
local note = ItemActions.run(player, { model = "Familiar" })
print(("SPEAK said %s"):format(note and ("nothing: " .. note) or "his piece"))
""")
	elif phase == 2 and t > 3.0:
		phase = 3; t = 0.0
		var spoke := _last("SPEAK ")
		print("    ", spoke)
		check(spoke.find("his piece") >= 0, "the server got as far as speaking: %s" % spoke)
	elif phase == 3 and t > 4.0:
		phase = 4
		_finish()
	return false
