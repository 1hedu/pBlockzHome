# The Familiar's trick, as structure: a Sound in the world on the pet rather than in the clicker's
# own SoundService, with the reverb on it, the two clips in turn, and the rules -- not while he is
# put away, not for one you do not own, not five times a second. Nothing here listens to anything;
# whether another machine hears it is familiar_heard_test's question.
#
#   godot --headless --path . -s res://tests/familiar_voice_test.gd
#
# The clips are staged as place assets rather than published, so this runs without a chain.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the Familiar's voice")
	# The host normally writes these out of the chain; here they come off disk.
	DirAccess.make_dir_recursive_absolute("user://preview")
	for name in ["familiar1", "familiar2"]:
		var bytes := FileAccess.get_file_as_bytes("res://../../../scripts/sfx/%s.wav" % name)
		var w := FileAccess.open("user://preview/%s.wav" % name, FileAccess.WRITE)
		if w:
			w.store_buffer(bytes)
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	# Nobody clicks through the intro: let players in as they join (tests/Arrive.gd).
	Arrive.now(world)
	_run()

## Runs a chunk on the server and hands back every "N <name> <value>" line it printed.
func _read(body: String, wait := 0.9) -> Dictionary:
	said.clear()
	world.run_chunk("voice", body)
	await create_timer(wait).timeout
	var out := {}
	for line in said:
		if line.begins_with("N "):
			var bits := line.substr(2).split(" ", true, 1)
			if bits.size() >= 2:
				out[bits[0]] = bits[1]
	return out

# A one-part pet in ServerStorage, and the two clips where PlaceAssets says they are.
const SETUP := '''
local ServerStorage = game:GetService("ServerStorage")
local rs = game:GetService("ReplicatedStorage")
local made = Instance.new("Model")
made.Name = "TestFamiliar"
local body = Instance.new("Part")
body.Name = "Head"
body.Size = Vector3.new(1, 1, 1)
body.Anchored = true
body.Parent = made
made.PrimaryPart = body
made.Parent = ServerStorage

-- The clips, as the host would have left them.
local folder = rs:FindFirstChild("PlaceAssets")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "PlaceAssets"
	folder.Parent = rs
end
for i, name in ipairs({"SfxFamiliar1", "SfxFamiliar2"}) do
	local v = folder:FindFirstChild(name) or Instance.new("StringValue")
	v.Name = name
	v.Value = "user://preview/familiar" .. i .. ".wav"
	v.Parent = folder
end
'''

func _run() -> void:
	await create_timer(4.0).timeout

	# ---- he cannot speak from inside your bag -------------------------------------------
	var away := await _read(SETUP + '''
local Actions = require(game:GetService("ServerScriptService").ItemActions)
local player = game:GetService("Players"):GetPlayers()[1]
print("N away " .. tostring(Actions.run(player, { model = "Familiar", name = "Familiar" })))
''')
	check(String(away.get("away", "")).find("out") >= 0,
		"put away he says nothing, and says why: %s" % away.get("away", "(nothing)"))

	# ---- and nothing at all happens to a hat ----------------------------------------------
	var hat := await _read('''
local Actions = require(game:GetService("ServerScriptService").ItemActions)
local player = game:GetService("Players"):GetPlayers()[1]
print("N does " .. tostring(Actions.of({ model = "Top Hat" })))
print("N familiar " .. tostring(Actions.of({ model = "Familiar" })))
''')
	check(hat.get("does", "") == "nil", "a hat has no trick, and is not given one")
	check(hat.get("familiar", "") == "Speak", "the Familiar's is called what the tooltip says")

	# ---- out, and clicked ------------------------------------------------------------------
	var spoke := await _read('''
local Pets = require(game:GetService("ServerScriptService").Pets)
local Actions = require(game:GetService("ServerScriptService").ItemActions)
local ServerStorage = game:GetService("ServerStorage")
local player = game:GetService("Players"):GetPlayers()[1]
Pets.summon(player, ServerStorage.TestFamiliar, "float")
task.wait(0.3)
Actions.run(player, { model = "Familiar", name = "Familiar" })
task.wait(0.2)
local head = Pets.speaker(player)
local sound = head and head:FindFirstChild("FamiliarVoice")
print("N onpet " .. tostring(sound ~= nil))
print("N where " .. (sound and sound:GetFullName() or "nowhere"))
print("N clip " .. (sound and sound.SoundId or ""))
print("N playing " .. tostring(sound and sound.Playing))
local reverb = sound and sound:FindFirstChildOfClass("ReverbSoundEffect")
print("N reverb " .. tostring(reverb ~= nil))
print("N decay " .. tostring(reverb and reverb.DecayTime))
print("N far " .. tostring(sound and sound.RollOffMaxDistance))
''', 1.4)
	check(spoke.get("onpet", "") == "true", "clicked, a Sound appears on the pet itself")
	check(String(spoke.get("where", "")).begins_with("Workspace"),
		"in the world where others can hear it, not in your own SoundService: %s"
		% spoke.get("where", ""))
	check(String(spoke.get("clip", "")).ends_with("familiar1.wav"),
		"and it is the first of his two lines: %s" % spoke.get("clip", ""))
	check(spoke.get("playing", "") == "true", "actually playing, not merely present")
	check(spoke.get("reverb", "") == "true", "with the reverb hung on it -- the first DSP here")
	check(spoke.get("decay", "") == "3", "tuned rather than left at the default: decay %s"
		% spoke.get("decay", ""))
	check(spoke.get("far", "") == "55", "and it stops carrying at %s studs" % spoke.get("far", ""))

	# ---- the two alternate, and he will not be machine-gunned -----------------------------
	# Sounds cleared and the cooldown waited out first, so the three clicks below stand alone.
	var again := await _read('''
local Pets = require(game:GetService("ServerScriptService").Pets)
local Actions = require(game:GetService("ServerScriptService").ItemActions)
local player = game:GetService("Players"):GetPlayers()[1]
local head = Pets.speaker(player)
for _, d in ipairs(head:GetChildren()) do
	if d:IsA("Sound") then d:Destroy() end
end
task.wait(1.2)

local function sounds()
	local n, last = 0, nil
	for _, d in ipairs(head:GetChildren()) do
		if d:IsA("Sound") then n = n + 1 last = d end
	end
	return n, last and last.SoundId or ""
end

Actions.run(player, { model = "Familiar" })
Actions.run(player, { model = "Familiar" })      -- the same instant: refused
task.wait(0.2)
local n, id = sounds()
print("N rushed " .. tostring(n))
print("N saidnow " .. id)

task.wait(1.2)
Actions.run(player, { model = "Familiar" })
task.wait(0.2)
local m, other = sounds()
print("N after " .. tostring(m))
print("N second " .. other)
''', 3.4)
	check(again.get("rushed", "") == "1",
		"clicking twice in an instant speaks once rather than stacking voices: %s sound(s)"
		% again.get("rushed", ""))
	check(again.get("after", "") == "2", "and the third click, past the cooldown, is heard")
	var first := String(again.get("saidnow", ""))
	var second := String(again.get("second", ""))
	check(first != "" and second != "" and first != second,
		"the two lines come out in turn rather than the same one twice: %s then %s"
		% [first.get_file(), second.get_file()])

	# ---- and the DSP is really on the mixer, not just in the tree --------------------------
	# A ReverbSoundEffect the engine ignored would pass every check above and still come out dry.
	# Godot hangs effects on buses, not voices, so a Sound with any gets a bus of its own named
	# after it; the audio server is asked for that bus directly.
	var buses := 0
	var reverbs := 0
	for i in AudioServer.get_bus_count():
		if String(AudioServer.get_bus_name(i)).begins_with("pblockz_sfx_"):
			buses += 1
			for k in AudioServer.get_bus_effect_count(i):
				if AudioServer.get_bus_effect(i, k) is AudioEffectReverb:
					reverbs += 1
	check(buses > 0, "the Sound got a bus of its own: %d" % buses)
	check(reverbs > 0, "with a real reverb on it, which is the DSP reaching the mixer")

	# ---- and you cannot click what you do not own -------------------------------------------
	# Through WardrobeRemote from the client, the way the panel asks, naming a Familiar that is not
	# in the bag: the server checks the chain's list and does nothing, as for a made-up wear.
	await _read('''
local Pets = require(game:GetService("ServerScriptService").Pets)
local player = game:GetService("Players"):GetPlayers()[1]
for _, d in ipairs(Pets.speaker(player):GetChildren()) do
	if d:IsA("Sound") then d:Destroy() end
end
''', 1.3)
	world.run_client_chunk("forge", '''
game:GetService("ReplicatedStorage").WardrobeRemote:FireServer("act", "Familiar")
''')
	var forged := await _read('''
local Pets = require(game:GetService("ServerScriptService").Pets)
local player = game:GetService("Players"):GetPlayers()[1]
local n = 0
for _, d in ipairs(Pets.speaker(player):GetChildren()) do
	if d:IsA("Sound") then n = n + 1 end
end
print("N forged " .. tostring(n))
''', 1.0)
	check(forged.get("forged", "") == "0",
		"asking for a Familiar the chain never said you had makes no sound: %s"
		% forged.get("forged", "(no answer)"))

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
