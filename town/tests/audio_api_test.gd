# The Audio API: players, effects and emitters joined by Wires.
#
#   godot --headless --path . -s res://tests/audio_api_test.gd
#
# The script side (which wires connect, pins, clock, GetGainAt, curves) and the host side on the
# AudioServer (the voice, its bus, the effect order). Whether it sounds right is tests/WINDOWED.md.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")

var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _line(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _bus_for(prefix: String) -> int:
	for i in AudioServer.bus_count:
		if String(AudioServer.get_bus_name(i)).begins_with(prefix): return i
	return -1

func _voices(w: Node) -> Array:
	var out := []
	var stack: Array[Node] = [w]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.name == "AudioVoice": out.append(n)
		for c in n.get_children(): stack.append(c)
	return out

func _initialize() -> void:
	print("the Audio API")
	StandIns.stage("audio")
	var w := PulseBlockzWorld.new()
	w.mode = 0
	get_root().add_child(w)
	w.script_error.connect(func(n, e): printerr("ERR ", n, ": ", e); said.append("ERROR " + e))
	w.script_print.connect(func(_n, t): said.append(t))
	_run(w)

func _run(w: PulseBlockzWorld) -> void:
	await create_timer(1.0).timeout
	w.run_chunk("build", """
local part = Instance.new("Part")
part.Name = "Speaker" part.Anchored = true part.Position = Vector3.new(0, 5, 0) part.Parent = workspace
local player = Instance.new("AudioPlayer")
player.Name = "Player" player.Asset = "user://preview/charge.wav" player.Parent = part
local filter = Instance.new("AudioFilter")
filter.Name = "Filter" filter.FilterType = Enum.AudioFilterType.Highpass12dB filter.Frequency = 200 filter.Parent = part
local reverb = Instance.new("AudioReverb")
reverb.Name = "Reverb" reverb.WetLevel = 0 reverb.Parent = part
local emitter = Instance.new("AudioEmitter")
emitter.Name = "Emitter" emitter.Parent = part
_G.changed = {}
for _, i in ipairs({ player, filter, reverb, emitter }) do
	i.WiringChanged:Connect(function(connected, pin, wire, other)
		table.insert(_G.changed, ("%s:%s:%s:%s"):format(i.Name, tostring(connected), pin, other and other.Name or "nil"))
	end)
end
local function wire(name, a, b)
	local x = Instance.new("Wire") x.Name = name x.SourceInstance = a x.TargetInstance = b x.Parent = part
	return x
end
wire("W1", player, filter) wire("W2", filter, reverb) wire("W3", reverb, emitter)
local bad = Instance.new("Wire") bad.Name = "BadPin" bad.SourceInstance = emitter bad.TargetInstance = player bad.Parent = part
local loop = wire("Loop", reverb, filter)
print("BUILT")
""")
	await create_timer(1.5).timeout

	w.run_chunk("wires", """
local part = workspace.Speaker
print("WIRES " .. tostring(part.W1.Connected) .. " " .. tostring(part.W2.Connected) .. " " .. tostring(part.W3.Connected)
	.. " bad=" .. tostring(part.BadPin.Connected) .. " loop=" .. tostring(part.Loop.Connected))
print("PINS " .. table.concat(part.Filter:GetInputPins(), ",") .. "|" .. table.concat(part.Filter:GetOutputPins(), ",")
	.. "|" .. table.concat(part.Player:GetInputPins(), ",") .. "|" .. table.concat(part.Emitter:GetOutputPins(), ","))
print("CONNECTED " .. #part.Filter:GetConnectedWires("Input") .. " " .. #part.Filter:GetConnectedWires("Output") .. " " .. #part.Player:GetConnectedWires("Output"))
table.sort(_G.changed)
print("CHANGED " .. table.concat(_G.changed, " "))
local f = part.Filter
print(("GAIN %.1f %.1f %.1f"):format(f:GetGainAt(20), f:GetGainAt(200), f:GetGainAt(5000)))
print("READY " .. tostring(part.Player.IsReady) .. " " .. string.format("%.2f", part.Player.TimeLength))
""")
	await create_timer(1.0).timeout
	check(_line("WIRES ") == "true true true bad=false loop=false",
		"a chain of wires connects; one from an Input-only emitter's non-existent Output does not, nor one that makes a loop: %s" % _line("WIRES "))
	check(_line("PINS ") == "Input|Output||", "an effect has Input and Output, a player no Input, an emitter no Output: %s" % _line("PINS "))
	check(_line("CONNECTED ") == "1 1 1", "GetConnectedWires lists the live wires on a pin: %s" % _line("CONNECTED "))
	check(_line("CHANGED ").contains("Emitter:true:Input:Reverb") and _line("CHANGED ").contains("Player:true:Output:Filter"),
		"both ends hear WiringChanged when a wire connects: %s" % _line("CHANGED "))
	var gains := _line("GAIN ").split(" ")
	check(gains.size() == 3 and float(gains[0]) < -30.0 and abs(float(gains[1]) + 3.0) < 0.5 and abs(float(gains[2])) < 0.5,
		"a 12 dB high-pass at 200 Hz: deep cut at 20, -3 dB at its frequency, flat far above: %s" % _line("GAIN "))
	var ready := _line("READY ").split(" ")
	check(ready.size() == 2 and ready[0] == "true" and float(ready[1]) > 0.5, "the engine loaded the asset and said how long it is: %s" % _line("READY "))

	var bus := _bus_for("pblockz_audio_")
	check(bus >= 0, "a wired player has a voice, on a bus of its own")
	if bus >= 0:
		check(AudioServer.get_bus_effect_count(bus) == 2 and AudioServer.get_bus_effect(bus, 0) is AudioEffectHighPassFilter
			and AudioServer.get_bus_effect(bus, 1) is AudioEffectReverb,
			"with the effects in the order the wires run: the high-pass, then the reverb")
	var voices := _voices(w)
	check(voices.size() == 1 and voices[0] is AudioStreamPlayer3D, "heard from the emitter: one 3D voice (%d)" % voices.size())

	# Slowed: the clip is a second long and the checks below want it still playing.
	w.run_chunk("play", "workspace.Speaker.Player.PlaybackSpeed = 0.2 workspace.Speaker.Player:Play()")
	await create_timer(1.0).timeout
	w.run_chunk("clock", """
local p = workspace.Speaker.Player
print(("CLOCK %s %.2f"):format(tostring(p.IsPlaying), p.TimePosition))
""")
	await create_timer(0.3).timeout
	var clock := _line("CLOCK ").split(" ")
	check(clock.size() == 2 and clock[0] == "true" and float(clock[1]) > 0.1, "Play plays, and TimePosition runs: %s" % _line("CLOCK "))
	check(voices.size() == 1 and (voices[0] as AudioStreamPlayer3D).playing, "and the voice is playing")

	var filter_before: Object = AudioServer.get_bus_effect(bus, 0) if bus >= 0 else null
	w.run_chunk("sweep", "workspace.Speaker.Filter.Frequency = 3000")
	await create_timer(0.5).timeout
	if bus >= 0:
		var filter_after: Object = AudioServer.get_bus_effect(bus, 0)
		check(filter_after == filter_before and abs((filter_after as AudioEffectHighPassFilter).cutoff_hz - 3000.0) < 1.0,
			"retuning Frequency keeps the very same filter, at 3000 Hz (%s)" % str((filter_after as AudioEffectHighPassFilter).cutoff_hz if filter_after is AudioEffectHighPassFilter else "?"))

	w.run_chunk("stop", """
local p = workspace.Speaker.Player
p:Stop()
task.wait(0.5)
print(("STOPPED %s %.2f"):format(tostring(p.IsPlaying), p.TimePosition))
""")
	await create_timer(1.0).timeout
	var stopped := _line("STOPPED ").split(" ")
	check(stopped.size() == 2 and stopped[0] == "false" and float(stopped[1]) > 0.1, "Stop stops and keeps TimePosition: %s" % _line("STOPPED "))
	check(voices.size() == 1 and not (voices[0] as AudioStreamPlayer3D).playing, "and the voice stops")

	w.run_chunk("end", """
local p = workspace.Speaker.Player
p.Ended:Connect(function() print(("ENDED %s %.2f"):format(tostring(p.IsPlaying), p.TimePosition)) end)
p.PlaybackSpeed = 1
p.TimePosition = p.TimeLength - 0.2
p:Play()
""")
	await create_timer(1.0).timeout
	check(_line("ENDED ") == "false 0.00", "played to the end it stops, fires Ended and goes back to the start: %s" % _line("ENDED "))

	w.run_chunk("unwire", "workspace.Speaker.W3:Destroy()")
	await create_timer(0.5).timeout
	check(_voices(w).size() == 0 and _bus_for("pblockz_audio_") < 0, "take a wire out and the voice and its bus go with it")

	w.run_chunk("curves", """
local part = workspace.Speaker
local e = part.Emitter
local cam = Instance.new("Part") cam.Anchored = true cam.Position = Vector3.new(0, 5, 20) cam.Parent = workspace
local l = Instance.new("AudioListener") l.Parent = cam
print(("AUD %.4f"):format(e:GetAudibilityFor(l)))
e.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Linear
e.DistanceAttenuationBounds = NumberRange.new(10, 30)
print(("LIN %.3f"):format(e:GetAudibilityFor(l)))
e.DistanceAttenuationMode = Enum.DistanceAttenuationMode.Custom
e:SetDistanceAttenuation({ [0] = 1, [40] = 0 })
local c = e:GetDistanceAttenuation()
print(("CUR %.3f %d"):format(e:GetAudibilityFor(l), (c[0] and c[40]) and 2 or 0))
l.AudioInteractionGroup = "elsewhere"
print(("GROUP %.3f %d"):format(e:GetAudibilityFor(l), #e:GetInteractingListeners()))
""")
	await create_timer(0.5).timeout
	check(abs(float(_line("AUD ")) - 16.0 / 400.0) < 0.002, "no curve: the inverse-square law from the near bound -- 4 studs over 20, squared: %s" % _line("AUD "))
	check(abs(float(_line("LIN ")) - 0.5) < 0.01, "Linear between 10 and 30 is half way at 20: %s" % _line("LIN "))
	check(_line("CUR ") == "0.500 2", "a custom curve of 1 at 0 to 0 at 40 is half at 20, and reads back: %s" % _line("CUR "))
	check(_line("GROUP ") == "0.000 0", "in another interaction group nothing is heard: %s" % _line("GROUP "))

	check(not said.any(func(s): return s.begins_with("ERROR")), "no script errors: %s" % str(said.filter(func(s): return s.begins_with("ERROR"))))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
