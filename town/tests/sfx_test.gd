# Every combat clip is played and probed, not merely loaded: a format the engine cannot decode
# loads without error and yields silence, which is why scripts/prep-sfx.js re-encodes the clips
# under scripts/sfx to plain PCM.
#
#   godot --path . -s res://tests/sfx_test.gd -- <stage dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0
var lines: Array[String] = []

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	for f in ["sword1.wav", "sword2.wav", "master.wav", "enemyhit.wav", "enemydies.wav",
			"hurt.wav", "dies.wav", "lowhp.wav", "fall.wav", "heart.png"]:
		var src := "res://../../../scripts/sfx/".path_join(f)
		if f.ends_with(".png"):
			src = "res://../../../scripts/models/".path_join(f)
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(src))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(func(_n, line): lines.append(String(line)))
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("assets", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
for name, file in pairs({
	SfxSword1 = "sword1.wav", SfxSword2 = "sword2.wav", SfxMaster = "master.wav",
	SfxEnemyHit = "enemyhit.wav", SfxEnemyDies = "enemydies.wav",
	SfxHurt = "hurt.wav", SfxDies = "dies.wav",
	SfxLowHp = "lowhp.wav", SfxFall = "fall.wav", HeartIcon = "heart.png",
}) do
	if not place:FindFirstChild(name) then
		local v = Instance.new("StringValue")
		v.Name = name
		v.Value = "user://preview/" .. file
		v.Parent = place
	end
end
""")
		t = 0.0
	elif phase == 1 and t > 4.0:
		phase = 2
		t = 0.0
		world.run_client_chunk("sfx", """
local SoundService = game:GetService("SoundService")
local ROLES = { "sword1", "sword2", "master", "enemyhit", "enemydies", "hurt", "dies", "lowhp", "fall" }
local ok, bad = 0, 0
task.spawn(function()
	for _, role in ipairs(ROLES) do
		local s = SoundService:FindFirstChild("Sfx" .. role)
		if not s then
			bad += 1
			print(("SFX %-10s NOT LOADED"):format(role))
		else
			s.TimePosition = 0
			s:Play()
			task.wait(0.12)
			-- A clip shorter than the wait will have finished already, so length is the
			-- other half of the answer: a file that failed to decode has neither.
			local live = s.IsPlaying or s.TimeLength > 0
			if live then ok += 1 else bad += 1 end
			print(("SFX %-10s %5.3fs  %s"):format(role, s.TimeLength, live and "plays" or "SILENT"))
			s:Stop()
		end
	end
	print(("SFX done: %d play, %d silent"):format(ok, bad))
end)
""")
	elif phase == 2 and t > 6.0:
		var passed := 0
		var failed := 0
		for l in lines:
			if l.begins_with("SFX done:"):
				var play := int(l.get_slice("done: ", 1).get_slice(" ", 0))
				var silent := int(l.get_slice(", ", 1).get_slice(" ", 0))
				passed += play
				failed += silent
				if play != 9: failed += 1; printerr("  FAIL only %d of 9 clips were loaded" % play)
		if passed + failed == 0: failed = 1; printerr("  FAIL the clips were never played")
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
