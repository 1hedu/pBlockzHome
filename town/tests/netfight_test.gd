# A fight across the wire: a hit lands on a body the server does not simulate.
#
#   godot --headless --path . -s res://tests/netfight_test.gd
#
# combat_test and pvp_test run Play Solo, where the character is local to the thing judging
# the fight. On a server every other character is remote -- its own client simulates it and
# reports where it got to, as on Roblox -- so the body here is a bot in its own process.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld

## Every script error the server threw while this ran; asserted on in _finish.
var errors: Array[String] = []
var main: Node
var said: Array[String] = []
var bot := -1
var phase := 0
var t := 0.0

const PORT := 8811          # not 8800: a bots.ps1 session may be listening there

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := String(line).find(prefix)
		if at >= 0:
			out.append(String(line).substr(at + prefix.length()).strip_edges())
	return out

func _initialize() -> void:
	print("a fight across the wire")
	main = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	# Mode 1 is MODE_SERVER (pulseblockz_world.h). Set before the world enters the tree: the
	# socket opens in _ready, and a write after that is a frame too late.
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

	var exe := OS.get_executable_path()
	bot = OS.create_process(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://tests/bot.gd", "--", "--name=Spoonie", "--port=%d" % PORT])
	if bot <= 0:
		printerr("could not start a bot process")

func _finish() -> void:
	if bot > 0: OS.kill(bot)
	check(errors.is_empty(), "the server threw nothing the whole time: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	# 22 s: the town has to come up and the bot has to connect and be given a body.
	if phase == 0 and t > 22.0:
		phase = 1
		t = 0.0
		said.clear()
		world.run_chunk("who", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local names = {}
for _, p in ipairs(Players:GetPlayers()) do
	table.insert(names, ("%s fights=%s"):format(p.Name, tostring(Health.fights(p))))
end
print("WHO " .. table.concat(names, " | "))
""")
	elif phase == 1 and t > 2.0:
		phase = 2
		t = 0.0
		var who := _lines("WHO ")
		check(who.size() > 0 and String(who[0]).find("Spoonie") >= 0,
			"the bot is in the town: %s" % str(who))
		if who.size() == 0 or String(who[0]).find("Spoonie") < 0:
			_finish()
			return false
		# The fight flag is forced on for both, whatever the chain says about either wallet:
		# under test is the blow crossing the wire, not who opted in.
		said.clear()
		world.run_chunk("hit", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)
local me, bot
for _, p in ipairs(Players:GetPlayers()) do
	if p.Name == "Spoonie" then bot = p else me = me or p end
end
Health.setFights(bot, true)
if me then Health.setFights(me, true) end
local char = bot.Character
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local before, healthBefore = root.Position, hum.Health
-- A blow with a shove in it, from nobody in particular: Health.hit takes a nil attacker,
-- which is how the void and the preview's hurt keys land one.
Health.hit(bot, nil, 2, 30)
task.wait(0.9)
print(("BLOW health %d -> %d, moved %.2f studs"):format(
	healthBefore, hum.Health, (root.Position - before).Magnitude))

-- The same shove by a Position write, as a control: only this one moving puts the fault in
-- the velocity path, neither moving puts it in the server's reach over a body it does not
-- simulate.
local was = root.Position
root.CFrame = root.CFrame + Vector3.new(0, 0, -12)
task.wait(0.9)
print(("SHIFT a Position write moved them %.2f studs"):format((root.Position - was).Magnitude))

-- Where a bot's swing actually reaches. The hitbox is built from the right shoulder's
-- Motor6D Transform -- the arm's animation pose -- so if the server does not have that pose
-- for a body it does not simulate, the head sits at the rest pose and the swing becomes a
-- sphere round the bot's own hip: omnidirectional melee, which is "killed from the side with
-- no conceivable way of being hit".
local torso = char:FindFirstChild("Torso")
local shoulder
for _, d in ipairs(char:GetDescendants()) do
	if d:IsA("Motor6D") and d.Name == "Right Shoulder" then shoulder = d end
end
if not shoulder then
	print("ARM no Right Shoulder motor")
else
	local tf = shoulder.Transform
	local rightCF = torso.CFrame * shoulder.C0 * tf * shoulder.C1:Inverse()
	-- The reach is negative: in worn space +Z runs up the shaft towards the butt, so a
	-- positive one measures out of the wrong end of the weapon.
	local head = rightCF:PointToWorldSpace(Vector3.new(0, -1, -1.7))
	local rel = root.CFrame:PointToObjectSpace(head)
	print(("ARM transform=%s head=(%.1f, %.1f, %.1f) in the swinger's own frame, reach 1.7"
		.. " -- forward is -Z"):format(
		tostring(tf) == tostring(CFrame.new()) and "identity" or "posed", rel.X, rel.Y, rel.Z))
end

-- Nothing of the hearts is on the server: each client draws them off replicated health and a
-- replicated flag. All the server owes is the flag; the drawing is checked in overhead_test.gd.
print(("FLAG fights=%s attr=%s"):format(
	tostring(Health.fights(bot)), tostring(bot:GetAttribute("Fights"))))
""")
	elif phase == 2 and t > 4.0:
		phase = 3
		var blow := _lines("BLOW ")
		check(blow.size() > 0, "the blow was struck: %s" % str(blow))
		if blow.size() > 0:
			var b := String(blow[0])
			var hp := b.substr(b.find("health ") + 7).split(" ")
			var moved := float(b.substr(b.find("moved ") + 6).split(" ")[0])
			check(int(hp[0]) > int(hp[2]),
				"it took hearts off somebody the server does not simulate: %s -> %s" % [hp[0], hp[2]])
			check(moved > 1.0,
				"and the knockback moved them: %.2f studs" % moved)
		for row in _lines("ARM "):
			print("    arm ", row)
		var flag := _lines("FLAG ")
		check(flag.size() > 0 and String(flag[0]).find("attr=true") >= 0,
			"the fight flag reached the wire, which is what draws their hearts: %s" % str(flag))
		var shift := _lines("SHIFT ")
		check(shift.size() > 0, "a Position write was tried too: %s" % str(shift))
		_finish()
	return false
