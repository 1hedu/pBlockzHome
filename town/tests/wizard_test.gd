# The Wizard Hat halves what a blade takes and makes every wand shot throw as hard as a full
# charge.
#
#   godot --headless --path . -s res://tests/wizard_test.gd
#
# Three bots on a real server, harnessed as in cast_hit_test.gd: Spoonie swinging, Cane shooting,
# and a Runner pinned in front of whichever is aimed at. Blows are counted at Health.hit and the
# Runner healed to full after each, so no shot is ever a killing one.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const PORT := 8827

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var bots: Array[int] = []
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _lines(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line in said:
		var i := line.find(prefix)
		if i >= 0: out.append(line.substr(i + prefix.length()).strip_edges())
	return out

func _spawn(name: String, extra: Array) -> void:
	var args := ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/bot.gd", "--",
		"--name=%s" % name, "--port=%d" % PORT]
	args.append_array(extra)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid > 0: bots.append(pid)

func _initialize() -> void:
	StandIns.stage("wizard")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.data_store_path = ""
	world.default_camera = false
	world.default_controls = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]); printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	_spawn("Spoonie", ["--every=0.8"])
	_spawn("Cane", ["--every=3", "--holds=0"])
	_spawn("Runner", ["--every=99"])

## Aims the Runner at one swinger and puts the hat on or off it; blows carry the stage name,
## so each stage is judged on its own.
func _stage(name: String, aim: String, hat: bool) -> void:
	world.run_chunk("stage", """
local rs = game:GetService("ReplicatedStorage")
local who = game:GetService("Players"):FindFirstChild("%s")
rs:SetAttribute("WizardAim", "%s")
rs:SetAttribute("WizardStage", "%s")
local ch = who and who.Character
local hat = ch and ch:FindFirstChild("Wizard Hat")
if %s and not hat and ch then
	local acc = Instance.new("Accessory")
	acc.Name = "Wizard Hat"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.CanCollide = false
	handle.Massless = true
	handle.Parent = acc
	acc.Parent = ch
elseif not %s and hat then
	hat:Destroy()
end
print("STAGE %s")
""" % [aim, aim, name, "true" if hat else "false", "true" if hat else "false", name])

func _process(delta: float) -> bool:
	t += delta
	match phase:
		0:
			if t > 24.0:
				phase = 1; t = 0.0
				world.run_chunk("standins", StandIns.chunk("wizard"))
				world.run_chunk("open", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local rs = game:GetService("ReplicatedStorage")
local Health = require(game:GetService("ServerScriptService").Health)
local spoon, cane, victim = Players:FindFirstChild("Spoonie"), Players:FindFirstChild("Cane"), Players:FindFirstChild("Runner")
if not spoon or not cane or not victim then print("OPEN missing") return end
for _, p in ipairs({ spoon, cane, victim }) do Health.setFights(p, true) end
local function arm(p, weapon, length)
	local acc = Instance.new("Accessory")
	acc.Name = weapon
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, length, 0.3)
	handle.Parent = acc
	acc.Parent = p.Character
end
arm(spoon, "Spoonie", 2.2)
arm(cane, "Cane", 2)

local realHit = Health.hit
Health.hit = function(who, attacker, half, shove)
	local hum = who.Character and who.Character:FindFirstChildOfClass("Humanoid")
	local landed = realHit(who, attacker, half, shove)
	if landed and who == victim and attacker then
		print(("BLOW stage=%s by=%s half=%s shove=%s"):format(tostring(rs:GetAttribute("WizardStage")), attacker.Name,
			tostring(half), tostring(shove)))
		if hum and hum.Health > 0 then hum.Health = hum.MaxHealth end
	end
	return landed
end

-- The two swingers stood well apart facing south, the Runner held in front of whichever is aimed
-- at: close for the spoon, ten studs out for the cane. Nobody moves.
RunService.Heartbeat:Connect(function()
	local aim = rs:GetAttribute("WizardAim")
	local spots = { Spoonie = Vector3.new(0, 0, 56), Cane = Vector3.new(30, 0, 56) }
	local out = { Spoonie = 2.2, Cane = 10 }
	for name, spot in pairs(spots) do
		local p = Players:FindFirstChild(name)
		local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if r then
			local here = Vector3.new(spot.X, r.Position.Y, spot.Z)
			r.CFrame = CFrame.new(here, here + Vector3.new(0, 0, 1))
			r.AssemblyLinearVelocity = Vector3.zero
		end
	end
	local v = victim.Character and victim.Character:FindFirstChild("HumanoidRootPart")
	local spot = aim and spots[aim]
	if v and spot then
		local here = Vector3.new(spot.X, v.Position.Y, spot.Z + out[aim])
		v.CFrame = CFrame.new(here, here - Vector3.new(0, 0, 1))
		v.AssemblyLinearVelocity = Vector3.zero
	elseif v then
		v.CFrame = CFrame.new(-40, v.Position.Y, 90)
	end
end)
print("OPEN ok")
""")
				_stage("spoon-bare", "Spoonie", false)
		1:
			if t > 9.0:
				phase = 2; t = 0.0
				_stage("spoon-hat", "Spoonie", true)
		2:
			if t > 9.0:
				phase = 3; t = 0.0
				_stage("cane-bare", "Cane", false)
		3:
			if t > 16.0:
				phase = 4; t = 0.0
				_stage("cane-hat", "Cane", true)
		4:
			if t > 16.0:
				phase = 5
				_verdict()
	return false

func _blows(stage: String) -> Array[String]:
	var out: Array[String] = []
	for b in _lines("BLOW "):
		if b.begins_with("stage=%s " % stage): out.append(b)
	return out

func _verdict() -> void:
	check(not _lines("OPEN ok").is_empty(), "three bots in the town, one with a spoon and one with a cane")
	var bare := _blows("spoon-bare")
	var hat := _blows("spoon-hat")
	var cbare := _blows("cane-bare")
	var chat := _blows("cane-hat")
	print("    spoon, bare: ", bare.slice(0, 3))
	print("    spoon, hat:  ", hat.slice(0, 3))
	print("    cane, bare:  ", cbare.slice(0, 3))
	print("    cane, hat:   ", chat.slice(0, 3))
	check(not bare.is_empty() and bare.all(func(b): return b.contains("by=Spoonie half=1 ")),
		"bare-headed, the spoon takes a whole half-heart a blow (%d blows)" % bare.size())
	check(not hat.is_empty() and hat.all(func(b): return b.contains("by=Spoonie half=0.5 ")),
		"in the Wizard Hat, it takes half that (%d blows)" % hat.size())
	check(hat.all(func(b): return b.contains("shove=26")), "and it still shoves as it did")
	check(not cbare.is_empty() and cbare.all(func(b): return b.contains("by=Cane half=1 shove=0")),
		"bare-headed, an ordinary cane shot throws nobody (%d shots)" % cbare.size())
	check(not chat.is_empty() and chat.all(func(b): return b.contains("by=Cane half=1 shove=54")),
		"in the hat, every shot throws as hard as a full charge (%d shots)" % chat.size())
	check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
	for pid in bots: OS.kill(pid)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
