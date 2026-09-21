# The cane's charge beam: hold to charge, let go to keep the charge, click to throw it. Six
# seconds is full, and the charge sets the orb's size, its damage and how low its shot is pitched.
#
#   node scripts/stage-preview.js cane <stage dir>
#   godot --headless --path . -s res://tests/cast_test.gd -- <stage dir>
#
# Damage landing on somebody needs a second body: cast_hit_test.gd.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

const StandIns = preload("res://tests/StandIns.gd")

var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var step := 0
var said: Array[String] = []
var ok := 0
var bad := 0

func check(cond: bool, what: String) -> void:
	if cond: ok += 1
	else: bad += 1
	print("  %s  %s" % ["PASS" if cond else "FAIL", what])

func _lines(prefix: String) -> Array[String]:
	var out: Array[String] = []
	for line in said:
		if line.begins_with(prefix): out.append(line.substr(prefix.length()))
	return out

func _field(line: String, key: String) -> String:
	for part in line.split(" "):
		if part.begins_with(key + "="): return part.substr(key.length() + 1)
	return ""

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	StandIns.stage("cast")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): said.append(line))
	world.script_error.connect(func(n, e): print("  LUA ERROR [%s] %s" % [n, e]))
	root.add_child(main)
	# Nobody here to click through the intro, so players are admitted on join.
	Arrive.now(world)
	print("== cast")

func _press() -> void:
	world.run_client_chunk("press", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer()")

func _release() -> void:
	world.run_client_chunk("release", "game:GetService('ReplicatedStorage'):WaitForChild('WeaponRemote', 3):FireServer('release')")

## Walks by feeding a key event, as a player does: Controls.client calls Humanoid:Move every
## frame, so a script's own Move would not survive one.
func _walk(on: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_W
	e.physical_keycode = KEY_W
	e.pressed = on
	Input.parse_input_event(e)

## Prints one `LOOK <tag> ...` line of cast state for _judge to read back by tag.
func _look(tag: String) -> void:
	world.run_chunk("look", """
local ch = game:GetService("Players"):GetPlayers()[1].Character
local root, torso = ch.HumanoidRootPart, ch.Torso
local j = torso["Right Shoulder"]
local w = root:FindFirstChild("RootJoint")
local torsoCF = root.CFrame * w.C0 * w.Transform * w.C1:Inverse()
local arm = torsoCF * j.C0 * j.Transform * j.C1:Inverse()
local tip = root.CFrame:PointToObjectSpace(arm:PointToWorldSpace(Vector3.new(0, -2.88, 0)))
local s = root:FindFirstChild("SfxCharge")
local strobe = ch:FindFirstChild("ChargedStrobe", true)
local room = s and s:FindFirstChild("Room")
local thin = s and s:FindFirstChild("Thin")
print(("LOOK TAG tip=%.2f rest=%s sound=%s at=%.2f strobe=%s orbs=%d wet=%.1f hp=%.0f"):format(tip.Y, tostring(j.Transform == CFrame.new()),
	s and (s.IsPlaying and "playing" or "paused") or "none", s and s.TimePosition or -1, tostring(strobe ~= nil), _G.castOrbs or 0,
	room and room.WetLevel or 99, thin and thin.Frequency or -1))
""".replace("TAG", tag))

# The script: [seconds after the previous step, what to do].
var steps := []

func _build() -> void:
	steps = [
		# A click, with nothing kept: an ordinary shot.
		[2.0, func(): _press(); _release()],
		[3.0, func(): _look("afterclick")],
		# 3.25s held: the arm takes a quarter of a second to come up, so three seconds of charge.
		[0.5, func(): _press()],
		[0.1, func(): _look("raising")],
		[1.5, func(): _look("charging")],
		[1.65, func(): _release()],
		[1.5, func(): _look("keptmid")],
		[0.5, func(): _press(); _release()],        # the click that throws it
		[3.0, func(): _look("afterthrow")],
		# Held past six and let go: kept full and strobing until the click.
		[0.5, func(): _press()],
		[3.5, func(): _look("midfull")],
		[3.4, func(): _look("fullheld")],
		[0.1, func(): _release()],
		[1.5, func(): _look("keptfull")],
		[0.5, func(): _press(); _release()],
		[0.3, func(): _look("fullthrown")],
		[3.0, func(): pass],
		# Two holds of a second and a half: the second resumes the first, sound and all, so the
		# click throws three seconds.
		[0.5, func(): _press()],
		[1.75, func(): _release()],
		[1.0, func(): _press()],
		[0.5, func(): _look("resumed")],
		[1.25, func(): _release()],
		[1.0, func(): _press(); _release()],
		[3.0, func(): pass],
		# Still, walking, still: only the time with the arm up and the feet still charges.
		[0.5, func(): _press()],
		[2.0, func(): _walk(true)],
		[1.2, func(): _look("walking")],
		[0.8, func(): _walk(false)],
		[3.0, func(): _release()],
		[1.5, func(): _press(); _release()],
		[3.0, func(): pass],
		[0.5, func(): world.run_chunk("wall", """
local root = game:GetService("Players"):GetPlayers()[1].Character.HumanoidRootPart
local wall = Instance.new("Part")
wall.Name = "TestWall"
wall.Anchored = true
wall.Size = Vector3.new(12, 12, 1)
wall.CFrame = root.CFrame * CFrame.new(0, 0, -10)
wall.Parent = workspace
""")],
		[0.5, func(): _press(); _release()],
		[3.0, func(): _judge()],
	]

func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 6.0:
		step = 1; t = 0.0
		_build()
		world.run_chunk("standins", StandIns.chunk("cast"))
		var json := FileAccess.get_file_as_string(stage.path_join("cane.json"))
		world.add_model("ReplicatedStorage/OnChain", "Cane", json.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("wear", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ch = Players:GetPlayers()[1].Character
local hum = ch:FindFirstChildOfClass("Humanoid")
local c = game:GetService("ReplicatedStorage").OnChain:FindFirstChild("Cane"):Clone()
c.Parent = ch
hum:AddAccessory(c)
local root = ch:FindFirstChild("HumanoidRootPart")
root.CFrame = CFrame.new(Vector3.new(0, root.Position.Y, 58), Vector3.new(0, root.Position.Y, 120))
root.Anchored = true

-- Every orb, from its first frame to its last.
_G.castOrbs = 0
local seen = {}
RunService.Heartbeat:Connect(function()
	for _, o in ipairs(workspace:GetChildren()) do
		if o.Name == "CaneOrb" and not seen[o] then
			_G.castOrbs += 1
			local mesh = o:FindFirstChildOfClass("SpecialMesh")
			local rel = root.CFrame:PointToObjectSpace(o.Position)
			seen[o] = { first = o.Position, last = o.Position, scale = 0, born = os.clock(), mesh = mesh, up = o.CFrame.UpVector, turned = 0,
				right = o.CFrame.RightVector:Dot(root.CFrame.RightVector),
				charge = o:GetAttribute("Charge") or -1, half = o:GetAttribute("Half") or -1,
				desc = ("%s|%s|%s|%.2f|%.2f,%.2f,%.2f"):format(mesh and mesh.MeshType.Name or "-", mesh and mesh.MeshId or "-",
					mesh and mesh.TextureId or "-", o.Transparency, rel.X, rel.Y, rel.Z) }
		end
	end
	for o, s in pairs(seen) do
		if o.Parent then
			s.last = o.Position
			-- How far round it has rolled: the turn of its up vector about the axis across its
			-- flight, added up frame by frame so a whole turn counts as a whole turn.
			local up = o.CFrame.UpVector
			s.turned += math.acos(math.clamp(s.up:Dot(up), -1, 1))
			s.up = up
			if s.mesh then s.scale = math.max(s.scale, s.mesh.Scale.X) end
		elseif not s.done then
			s.done = true
			print(("ORB born=%.3f charge=%.2f half=%d scale=%.2f travel=%.1f life=%.2f turns=%.2f right=%.3f look=%s"):format(
				s.born, s.charge, s.half, s.scale, (s.last - s.first).Magnitude, os.clock() - s.born, s.turned / (2 * math.pi), s.right, s.desc))
		end
	end
end)

-- Every sound the cast makes on his body, and how fast it plays.
local sounds = {}
RunService.Heartbeat:Connect(function()
	for _, d in ipairs(root:GetChildren()) do
		if (d:IsA("Sound") or d:IsA("AudioPlayer")) and not sounds[d] then
			sounds[d] = true
			print(("SOUND %s speed=%.3f"):format(d.Name, d.PlaybackSpeed))
		end
	end
end)
print("WORN")
""")
	elif step >= 1 and step <= steps.size():
		var s: Array = steps[step - 1]
		if t > float(s[0]):
			t = 0.0
			step += 1
			(s[1] as Callable).call()
	return false

func _judge() -> void:
	# By birth, not by finish: a clear shot is in the air for seconds, one into a wall for a tenth.
	var orbs := _lines("ORB ")
	orbs.sort_custom(func(a, b): return float(_field(a, "born")) < float(_field(b, "born")))
	check(orbs.size() == 6, "six shots, six orbs -- and not one of them from letting go: %d" % orbs.size())
	if orbs.size() < 6:
		for o in orbs: print("    ", o)
		for l in _lines("LOOK "): print("    LOOK ", l)
		_finish()
		return
	var tap: String = orbs[0]
	var mid: String = orbs[1]
	var full: String = orbs[2]
	var resumed: String = orbs[3]
	var walked: String = orbs[4]
	var wall: String = orbs[5]
	var look := {}
	for l in _lines("LOOK "):
		look[l.split(" ")[0]] = l

	var desc := _field(tap, "look").split("|")
	var turns := float(_field(tap, "turns"))
	var life := float(_field(tap, "life"))
	check(life > 0.0 and abs(turns / life - 3.0) < 0.4, "it spins as it flies, three turns a second: %.1f turns in %.2fs" % [turns, life])
	# The orb's right is his right, so the gradient's bands lie across it -- red low on his left --
	# and the spin, about that same axis, keeps them there.
	check(float(_field(tap, "right")) > 0.99, "and it is turned the way he faces, its right his right: %s" % _field(tap, "right"))
	check(desc.size() == 5 and desc[0] == "FileMesh" and desc[1].ends_with("orb.obj") and desc[2].ends_with("pulse-gradient.png") and abs(float(desc[3]) - 0.3) < 0.01,
		"one see-through ball, a FileMesh sphere painted with the bands (%s)" % _field(tap, "look"))
	var rel := desc[4].split(",") if desc.size() == 5 else PackedStringArray(["0", "0", "0"])
	check(float(rel[2]) < -1.5 and float(rel[1]) > 0.2 and float(rel[1]) < 0.9 and float(rel[0]) > 0.3,
		"it leaves the cane's tip: ahead of him, at shoulder height, on his right (%s)" % desc[4])

	check(float(_field(tap, "charge")) < 0.05 and _field(tap, "half") == "1" and abs(float(_field(tap, "scale")) - 1.6) < 0.05,
		"a click with nothing kept: an ordinary shot, half a heart, 1.6 across (%s)" % tap)
	check(float(_field(tap, "travel")) > 195.0 and float(_field(tap, "travel")) < 205.0 and abs(float(_field(tap, "life")) - 200.0 / 45.0) < 0.15,
		"and with nothing in the way it flies 200 studs, the map corner to corner, before it is gone: %s studs in %ss" % [_field(tap, "travel"), _field(tap, "life")])

	check(float(_field(look.get("raising", ""), "tip")) < 2.5 and _field(look.get("raising", ""), "sound") == "none",
		"a tenth of a second into a hold the arm is still going up, and nothing is charging yet: %s" % look.get("raising", "-"))
	check(float(_field(look.get("charging", ""), "tip")) > 2.5 and _field(look.get("charging", ""), "sound") == "playing" and _field(look.get("charging", ""), "orbs") == "1",
		"held, the arm is up with the charge sound playing: %s" % look.get("charging", "-"))
	check(_field(look.get("keptmid", ""), "orbs") == "1" and _field(look.get("keptmid", ""), "rest") == "true" and _field(look.get("keptmid", ""), "sound") == "none",
		"let go: nothing fires, the arm comes home, the charge sound stops: %s" % look.get("keptmid", "-"))
	check(abs(float(_field(mid, "charge")) - 3.0) < 0.3 and _field(mid, "half") == "2" and abs(float(_field(mid, "scale")) - 4.0) < 0.3,
		"and the next click throws what was kept -- three seconds of it, a heart, 2.5 times across (%s)" % mid)

	# The charge sound's room swells to its fullest at 5.5s; from 2s a high-pass sweeps up.
	var wet_early := float(_field(look.get("charging", ""), "wet"))
	check(wet_early > -16.0 and wet_early < -9.0 and float(_field(look.get("charging", ""), "hp")) < 25.0,
		"a second and a quarter into a charge the room is coming in -- a quarter of the way up -- and the high-pass has not begun: WetLevel %.1f dB, %s Hz" % [wet_early, _field(look.get("charging", ""), "hp")])
	var wet_again := float(_field(look.get("resumed", ""), "wet"))
	check(wet_again > wet_early + 2.0 and wet_again < -6.0,
		"carrying on from a kept charge, it is wetter -- as wet as that far into a charge: %.1f dB" % wet_again)
	# At 3.25s: the high-pass climbs octave-even from 20 Hz to 3000 over the four seconds after the
	# second, so 1.25s along is about 95 Hz; the room, 3.25 of 5.5 in amplitude, is about -4.6 dB.
	var hp_mid := float(_field(look.get("midfull", ""), "hp"))
	var wet_mid := float(_field(look.get("midfull", ""), "wet"))
	check(wet_mid > -6.0 and wet_mid < -3.0 and hp_mid > 70.0 and hp_mid < 130.0,
		"past two seconds the room is most of the way up and the high-pass is on its way: %.1f dB, %.0f Hz" % [wet_mid, hp_mid])
	check(abs(float(_field(look.get("fullheld", ""), "wet"))) < 0.05 and abs(float(_field(look.get("fullheld", ""), "hp")) - 3000.0) < 1.0,
		"and at the top of the charge the room is at its fullest and the high-pass at 3000 Hz: %s dB, %s Hz" % [_field(look.get("fullheld", ""), "wet"), _field(look.get("fullheld", ""), "hp")])
	check(_field(look.get("fullheld", ""), "strobe") == "true", "held full, the cane strobes: %s" % look.get("fullheld", "-"))
	check(_field(look.get("keptfull", ""), "strobe") == "true" and _field(look.get("keptfull", ""), "orbs") == "2" and _field(look.get("keptfull", ""), "rest") == "true",
		"let go full, it keeps strobing with the arm down, and nothing has fired: %s" % look.get("keptfull", "-"))
	check(abs(float(_field(full, "charge")) - 6.0) < 0.01 and _field(full, "half") == "4" and abs(float(_field(full, "scale")) - 6.4) < 0.05,
		"the click throws the full charge: two hearts, four times across (%s)" % full)
	check(_field(look.get("fullthrown", ""), "strobe") == "false", "and the strobe stops once it is thrown: %s" % look.get("fullthrown", "-"))

	var again: String = look.get("resumed", "")
	check(_field(again, "sound") == "playing" and float(_field(again, "at")) > 0.2 and float(_field(again, "at")) < 0.4 and _field(again, "orbs") == "3",
		"holding again with a charge kept carries on charging it, the sound picking up a sixth of the way in: %s" % again)
	check(abs(float(_field(resumed, "charge")) - 3.0) < 0.35 and _field(resumed, "half") == "2",
		"and the click throws both holds' charge together, three seconds of it (%s)" % resumed)
	check(_field(look.get("walking", ""), "rest") == "true" and _field(look.get("walking", ""), "sound") == "paused",
		"walking while holding: no pose -- the arm is home for the walk -- and the charge sound paused: %s" % look.get("walking", "-"))
	check(float(_field(walked, "charge")) > 4.0 and float(_field(walked, "charge")) < 5.0 and _field(walked, "half") == "3",
		"and only the time with the arm up and his feet still charged: about 4.5 of 7 seconds held, a heart and a half (%s)" % walked)

	check(float(_field(wall, "travel")) < 9.0 and float(_field(wall, "life")) < 0.4,
		"a wall ten studs out stops a shot: %s studs, %ss" % [_field(wall, "travel"), _field(wall, "life")])

	var sounds := _lines("SOUND ")
	var charges := sounds.filter(func(s): return s.begins_with("SfxCharge"))
	var shots := sounds.filter(func(s): return s.begins_with("SfxBuster"))
	check(charges.size() == 5 and charges.all(func(s): return abs(float(_field(s, "speed")) - 1.0 / 6.0) < 0.001),
		"one charge sound per hold that charged, VanishingBlocks six times slow -- none for a click: %s" % str(charges))
	check(shots.size() == 6, "every shot plays MegaBuster, and letting go plays nothing: %d" % shots.size())
	if shots.size() == 6:
		var speeds := shots.map(func(s): return float(_field(s, "speed")))
		check(abs(speeds[0] - 1.0) < 0.02 and abs(speeds[1] - 1.0 / 3.5) < 0.03 and abs(speeds[2] - 1.0 / 6.0) < 0.005,
			"pitched down with the charge: 1x for a click, 3.5x lower at three seconds, 6x at full (%s)" % str(speeds))
	_finish()

func _finish() -> void:
	print("%d passed, %d failed" % [ok, bad])
	quit(0 if bad == 0 else 1)
