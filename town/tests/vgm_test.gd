# The VGM player is making notes, not just parsing: all four 2A03 Sounds exist, at least three
# of them audible and two moving in pitch. Not headless -- it samples the live Sounds.
#
#   godot --path . -s res://tests/vgm_test.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var said: Array[String] = []
var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	root.add_child(main)
	world.script_print.connect(func(_n, x): said.append(str(x)))
	print("== vgm")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 22.0:
		phase = 1
		world.run_client_chunk("watch", """
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")
local ids = { "Nes_p1", "Nes_p2", "Nes_tri", "Nes_noise" }
local seen, pitches, loudest = {}, {}, {}
for _, n in ipairs(ids) do seen[n] = 0; pitches[n] = {}; loudest[n] = 0 end
local t0 = os.clock()
local conn
conn = RunService.Heartbeat:Connect(function()
    if os.clock() - t0 > 2.0 then
        conn:Disconnect()
        for _, n in ipairs(ids) do
            local distinct = 0
            for _ in pairs(pitches[n]) do distinct += 1 end
            print(("VGM %s heard=%d pitches=%d peak=%.3f"):format(n, seen[n], distinct, loudest[n]))
        end
        return
    end
    for _, n in ipairs(ids) do
        local s = SoundService:FindFirstChild(n)
        if s then
            if s.Volume > 0.001 then
                seen[n] += 1
                pitches[n][math.floor(s.PlaybackSpeed * 200)] = true
                if s.Volume > loudest[n] then loudest[n] = s.Volume end
            end
        end
    end
end)
""")
		t = 0.0
	elif phase == 1 and t > 3.0:
		var heard := {}
		for line in said:
			if line.begins_with("VGM "):
				print("  ", line)
				var b := line.split(" ")
				heard[b[1]] = [int(b[2].split("=")[1]), int(b[3].split("=")[1]), float(b[4].split("=")[1])]
		check(heard.size() == 4, "all four 2A03 channels exist")
		var voiced := 0
		var moving := 0
		for k in heard:
			if heard[k][0] > 0: voiced += 1
			if heard[k][1] > 3: moving += 1
		check(voiced >= 3, "at least three channels are audible (%d were)" % voiced)
		check(moving >= 2, "at least two are changing pitch, so it is a tune not a drone (%d were)" % moving)
		var anyLog := false
		for line in said:
			if line.find("52619 bytes") >= 0: anyLog = true
		check(anyLog, "the log decoded to its full 52,619 bytes")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
		return true
	return false
