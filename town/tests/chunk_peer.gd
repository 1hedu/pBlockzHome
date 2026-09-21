# A real client that runs a LocalScript chunk and writes down what it says.
#
#   godot --headless --path . -s res://tests/chunk_peer.gd -- --port=<port> --chunk=<file> --out=<file> [--parts=A,B] [--name=Peer]
#
# Printed lines starting "SEEN " are appended to --out without the prefix, so a test in the server
# process reads off this machine's own copy what crossed the wire. Also written, once a second:
#   --parts   "TEX <name> <w>x<h> <r>,<g>,<b>" -- that Workspace part's albedo texture as this
#             renderer built it, its size and its top-left pixel
#   --voices  "VOICES <made> <playing> <buses>", and "HEARD <frames any voice played>
#             <name=count,...>" -- Sounds counted once per node, sampled every frame so a clip
#             shorter than a second is not missed
# --reads: the wallet reads balances and history off the chain; off by default, most tests want no
# network.
extends SceneTree

var world: PulseBlockzWorld
var out := ""
var chunk := ""
var joined := false
var parts: PackedStringArray = []
var voices := false
# --sound=<name>: "SOUNDPLAYS <count> <secs>@<start in clip>/<volume_db>dB/peak<bus dB>/far<studs>,
# ...", one entry per stretch it played. Sampled every frame: a play starting at the end of its
# clip lasts milliseconds, which is the difference between heard and not.
var sound_name := ""
var sound_on := false
var sound_since := 0
var sound_plays: PackedFloat32Array = []
var sound_starts: PackedFloat32Array = []   # where in the clip each play began, in seconds
var sound_dbs: PackedFloat32Array = []      # the player's volume_db when each play began
var sound_peaks: PackedFloat32Array = []    # the loudest the master bus got during each play, dB
var sound_peak := -200.0
var sound_fars: PackedFloat32Array = []    # the furthest the sound got from the ear during each play, studs
var sound_far := 0.0
var sound_told := 0
var voice_frames := 0
var heard_nodes := {}   # instance id of a playing Sound's node -> its name
var since := 0.0

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	out = _flag("out", "user://chunk_peer.txt")
	parts = _flag("parts", "").split(",", false)
	voices = _flag("voices", "") != ""
	sound_name = _flag("sound", "")
	chunk = FileAccess.get_file_as_string(_flag("chunk", ""))
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")   # --host=: a server elsewhere, the live town included
	world.server_port = int(_flag("port", "8899"))
	world.player_name = _flag("name", "Peer")
	# --camera=1: with no camera there is no listener, so the engine skips its distance roll-off
	# and every Sound plays at full volume wherever the peer stands.
	world.default_camera = _flag("camera", "") != ""
	world.default_controls = false
	main.get_node("Wallet").auto_start = _flag("reads", "") != ""
	# --noconfirm: a headless player has nobody to click its wallet's prompt, so it says yes itself.
	if _flag("noconfirm", "") != "": main.get_node("Wallet").confirm_purchases = false
	world.script_print.connect(_heard)
	world.script_error.connect(func(_n, e): _write("ERROR " + e))
	get_root().add_child(main)
	var blank := FileAccess.open(out, FileAccess.WRITE)
	if blank: blank.close()

func _write(line: String) -> void:
	var f := FileAccess.open(out, FileAccess.READ_WRITE)
	if not f: return
	f.seek_end()
	f.store_line(line)
	f.close()

func _heard(_name: String, line: String) -> void:
	if line.begins_with("SEEN "):
		_write(line.substr(5))

func _texture_of(name: String) -> String:
	var ws := 0
	for id in world.get_child_ids(0):
		if world.get_instance(id).get("name", "") == "Workspace": ws = id
	for id in world.get_child_ids(ws):
		if world.get_instance(id).get("name", "") != name: continue
		var mesh = world.get_part_mesh(id)
		if not (mesh is MeshInstance3D): return ""
		var mat = mesh.material_override
		if mat == null and mesh.mesh != null and mesh.mesh.get_surface_count() > 0: mat = mesh.get_active_material(0)
		if not (mat is BaseMaterial3D) or mat.albedo_texture == null: return ""
		var img: Image = mat.albedo_texture.get_image()
		if img == null or img.is_empty(): return ""
		if img.is_compressed(): img.decompress()
		var c := img.get_pixel(0, 0)
		return "TEX %s %dx%d %d,%d,%d" % [name, img.get_width(), img.get_height(), roundi(c.r * 255), roundi(c.g * 255), roundi(c.b * 255)]
	return ""

func _process(delta: float) -> bool:
	since += delta
	if sound_name != "":
		var on := false
		var playing3d: Node3D = null
		var ear: Node3D = null
		var stack: Array[Node] = [world]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.name == sound_name and ((n is AudioStreamPlayer3D and n.playing) or (n is AudioStreamPlayer and n.playing)):
				if n is AudioStreamPlayer3D: playing3d = n
				if not sound_on:
					sound_starts.append(n.get_playback_position())
					sound_dbs.append(n.volume_db)
				on = true
			for c in n.get_children(): stack.append(c)
			if n is AudioListener3D and n.is_current(): ear = n
		if playing3d != null:
			if ear == null: ear = get_root().get_camera_3d()
			if ear != null: sound_far = max(sound_far, playing3d.global_position.distance_to(ear.global_position))
		if on: sound_peak = max(sound_peak, AudioServer.get_bus_peak_volume_left_db(0, 0))
		if on and not sound_on: sound_since = Time.get_ticks_msec(); sound_peak = -200.0; sound_far = 0.0
		if not on and sound_on:
			sound_plays.append((Time.get_ticks_msec() - sound_since) / 1000.0)
			sound_peaks.append(sound_peak)
			sound_fars.append(sound_far)
		sound_on = on
		if sound_plays.size() != sound_told:
			sound_told = sound_plays.size()
			var parts_played := PackedStringArray()
			for i in sound_plays.size(): parts_played.append("%.2f@%.2f/%.0fdB/peak%.0f/far%.0f" % [sound_plays[i], sound_starts[i] if i < sound_starts.size() else -1.0, sound_dbs[i] if i < sound_dbs.size() else 99.0, sound_peaks[i] if i < sound_peaks.size() else 99.0, sound_fars[i] if i < sound_fars.size() else -1.0])
			_write("SOUNDPLAYS %d %s" % [sound_plays.size(), ",".join(parts_played)])
	if voices:
		var any_voice := false
		var watch: Array[Node] = [world]
		while not watch.is_empty():
			var n: Node = watch.pop_back()
			var is_playing: bool = (n is AudioStreamPlayer3D and n.playing) or (n is AudioStreamPlayer and n.playing)
			if is_playing:
				if n.name == "AudioVoice": any_voice = true
				else: heard_nodes[n.get_instance_id()] = String(n.name)
			for c in n.get_children(): watch.append(c)
		if any_voice: voice_frames += 1
	if voices and since > 1.0:
		var by_name := {}
		for id in heard_nodes: by_name[heard_nodes[id]] = int(by_name.get(heard_nodes[id], 0)) + 1
		var parts_heard := PackedStringArray()
		for k in by_name: parts_heard.append("%s=%d" % [k, by_name[k]])
		_write("HEARD %d %s" % [voice_frames, ",".join(parts_heard)])
		var made := 0
		var playing := 0
		var stack: Array[Node] = [world]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.name == "AudioVoice":
				made += 1
				if (n is AudioStreamPlayer3D and n.playing) or (n is AudioStreamPlayer and n.playing): playing += 1
			for c in n.get_children(): stack.append(c)
		var buses := 0
		for i in AudioServer.bus_count:
			if String(AudioServer.get_bus_name(i)).begins_with("pblockz_audio_"): buses += 1
		_write("VOICES %d %d %d" % [made, playing, buses])
		if parts.is_empty(): since = 0.0
	if not parts.is_empty() and since > 1.0:
		since = 0.0
		for p in parts:
			var line := _texture_of(p)
			if line != "": _write(line)
	if not world.is_server_connected() or joined:
		return false
	joined = true
	world.run_client_chunk("peer", chunk)
	return false
