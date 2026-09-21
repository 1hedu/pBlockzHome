# The far end of familiar_heard_test: a real client that joins the town and writes out what a
# FamiliarVoice looked like on its own machine. IsLoaded and TimeLength are set by the host when
# a SoundId resolves, so TimeLength 0 is a clip that never opened, however right the path reads.
#
#   godot --headless --path . -s res://tests/familiar_peer.gd -- --name=Ear --out=<file>
extends SceneTree

var world: PulseBlockzWorld
var who := "Ear"
var out := ""
var joined := false

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	out = _flag("out", "user://familiar.txt")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8893"))
	world.player_name = who
	world.default_camera = true      # a sound in the world is mixed against a listener
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("[peer] LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(_heard)
	get_root().add_child(main)
	var blank := FileAccess.open(out, FileAccess.WRITE)
	if blank: blank.close()
	print("[peer] %s asking for the town" % who)

func _heard(_name: String, line: String) -> void:
	if not line.begins_with("EAR "):
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(line.substr(4))
		f.close()

func _process(_delta: float) -> bool:
	if not world.is_server_connected() or joined:
		return false
	joined = true
	print("[peer] %s is in" % who)
	world.run_chunk("ear", """
local RunService = game:GetService("RunService")

-- The best look this machine ever got at a Familiar's voice.
--
-- Kept as a high-water mark rather than a snapshot: the Sound is made, replicated, loaded and
-- destroyed six seconds later, so any single glance is likely to land either before the file
-- has opened or after the whole thing is gone.
local seen, id, loaded, length, played = false, "", false, 0, false

task.spawn(function()
	while true do
		RunService.Heartbeat:Wait()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("Sound") and d.Name == "FamiliarVoice" then
				seen = true
				if d.SoundId ~= "" then id = d.SoundId end
				if d.IsLoaded then loaded = true end
				if d.TimeLength > length then length = d.TimeLength end
				if d.IsPlaying then played = true end
			end
		end
	end
end)

while true do
	task.wait(0.5)
	print(("EAR seen=%s loaded=%s playing=%s length=%.3f id=%s"):format(
		tostring(seen), tostring(loaded), tostring(played), length,
		id == "" and "(none)" or id))
end
""")
	return false
