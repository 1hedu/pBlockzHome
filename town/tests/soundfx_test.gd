# SoundEffect wiring, not sound: Roblox mixes effects per voice and Godot attaches them to
# buses, so a Sound with effects gets a bus of its own and a Sound with none is never touched.
# Whether a reverb sounds like a reverb needs ears and is on tests/WINDOWED.md.
#
#   godot --headless --path . -s res://tests/soundfx_test.gd
extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func bus_named(want: String) -> int:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == want: return i
	return -1

func our_buses() -> int:
	var n := 0
	for i in AudioServer.bus_count:
		if String(AudioServer.get_bus_name(i)).begins_with("pblockz_sfx_"): n += 1
	return n

func _initialize() -> void:
	print("sound effects")
	var w := PulseBlockzWorld.new()
	w.mode = 0
	get_root().add_child(w)
	w.script_error.connect(func(n, e): printerr("ERR ", n, ": ", e))
	_run(w)

func _run(w: PulseBlockzWorld) -> void:
	var before := our_buses()
	check(before == 0, "no effect buses before anything asks for one")

	w.run_chunk("plain", """
local s = Instance.new("Sound")
s.Name = "Plain" s.SoundId = "rbxasset://x.wav" s.Parent = workspace
""")
	await create_timer(1.5).timeout
	check(our_buses() == 0, "a Sound with no effects still gets none")

	w.run_chunk("fx", """
local s = Instance.new("Sound")
s.Name = "Fancy" s.SoundId = "rbxasset://x.wav" s.Parent = workspace
local r = Instance.new("ReverbSoundEffect") r.DecayTime = 3 r.Parent = s
local e = Instance.new("EqualizerSoundEffect") e.HighGain = -6 e.Parent = s
local d = Instance.new("DistortionSoundEffect") d.Level = 0.5 d.Parent = s
""")
	await create_timer(2.0).timeout
	check(our_buses() == 1, "a Sound with effects gets exactly one bus")
	var at := -1
	for i in AudioServer.bus_count:
		if String(AudioServer.get_bus_name(i)).begins_with("pblockz_sfx_"): at = i
	if at >= 0:
		check(AudioServer.get_bus_effect_count(at) == 3, "with one effect per SoundEffect")
		check(AudioServer.get_bus_effect(at, 0) is AudioEffectReverb, "reverb first, in the order they were parented")
		check(AudioServer.get_bus_effect(at, 1) is AudioEffectEQ6, "then the equalizer")
		check(AudioServer.get_bus_effect(at, 2) is AudioEffectDistortion, "then the distortion")
		check(AudioServer.get_bus_send(at) == &"Master", "and it feeds the master bus")

	# A property change retunes the effect in place; rebuilding it would cut the reverb's tail.
	var reverb_before: Object = AudioServer.get_bus_effect(at, 0) if at >= 0 else null
	w.run_chunk("retune", """
for _, d in ipairs(workspace:GetChildren()) do
	if d.Name == "Fancy" then d:FindFirstChildOfClass("ReverbSoundEffect").WetLevel = -20 end
end
""")
	await create_timer(1.5).timeout
	if at >= 0:
		var reverb_after: Object = AudioServer.get_bus_effect(at, 0)
		check(reverb_after == reverb_before, "retuning an effect keeps the very same effect on the bus")
		check(reverb_after is AudioEffectReverb and absf((reverb_after as AudioEffectReverb).wet - 0.1) < 0.005,
			"with the new level in it: -20 dB is a wet of 0.1 (%s)" % str((reverb_after as AudioEffectReverb).wet if reverb_after is AudioEffectReverb else "?"))

	# Roblox drops a disabled effect out of the chain rather than leaving it in silently.
	w.run_chunk("off", """
for _, d in ipairs(workspace:GetChildren()) do
	if d.Name == "Fancy" then
		for _, fx in ipairs(d:GetChildren()) do
			if fx:IsA("EqualizerSoundEffect") then fx.Enabled = false end
		end
	end
end
""")
	await create_timer(2.0).timeout
	if at >= 0:
		check(AudioServer.get_bus_effect_count(bus_named(AudioServer.get_bus_name(at))) == 2,
			"switching one off takes it out of the chain")

	w.run_chunk("gone", """
for _, d in ipairs(workspace:GetChildren()) do
	if d.Name == "Fancy" then
		for _, fx in ipairs(d:GetChildren()) do fx:Destroy() end
	end
end
""")
	await create_timer(2.0).timeout
	check(our_buses() == 0, "and the bus goes when the last effect does")

	# Godot ships no tremolo: PulseBlockzTremolo is this engine's own effect.
	w.run_chunk("trem", """
local s = Instance.new("Sound")
s.Name = "Wobble" s.SoundId = "rbxasset://x.wav" s.Parent = workspace
local t = Instance.new("TremoloSoundEffect")
t.Depth = 0.8 t.Frequency = 6 t.Duty = 0.4 t.Parent = s
""")
	await create_timer(2.0).timeout
	var made := false
	for i in AudioServer.bus_count:
		if not String(AudioServer.get_bus_name(i)).begins_with("pblockz_sfx_"): continue
		for k in AudioServer.get_bus_effect_count(i):
			if AudioServer.get_bus_effect(i, k) is PulseBlockzTremolo: made = true
	check(made, "TremoloSoundEffect builds a tremolo -- the ninth of nine")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
