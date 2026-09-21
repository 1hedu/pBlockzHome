# The town joined rather than run: Main.tscn with its World in Client mode, fed by a server
# over ENet. The client runs its own LocalScripts, simulates its own character as Roblox does,
# and reads the wallet's items off the chain itself -- the server is told only a position.
#
#   godot --path . -s res://Join.gd -- [--host=play.safewrap.xyz] [--port=8800]
extends SceneTree

const DEFAULT_HOST := "127.0.0.1"
const DEFAULT_PORT := 8800

var world: PulseBlockzWorld
var _was := false
var _log: FileAccess = null

## Console and log, flushed at once: a crash loses whatever is still buffered.
func _say(line: String) -> void:
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()

func _note(line: String) -> void:
	if _log:
		_log.store_line(line)
		_log.flush()

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return fallback

func _initialize() -> void:
	var host := _flag("host", DEFAULT_HOST)
	var port := int(_flag("port", str(DEFAULT_PORT)))

	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2                      # Client; set before add_child, World reads it in _ready
	world.server_address = host
	world.server_port = port

	# Joins the server.log and bot-*.log that tests/bots.ps1 writes into tests/logs/. An exported
	# build has no writable res://, so its own log goes to the user data folder instead.
	var where := "res://tests/logs" if not OS.has_feature("template") else "user://logs"
	DirAccess.make_dir_recursive_absolute(where)
	_log = FileAccess.open(where.path_join("client.log"), FileAccess.WRITE)
	# File only: Main.gd already prints every script line to the console.
	world.script_print.connect(func(n, line): _note("[%s] %s" % [n, line]))
	world.script_error.connect(func(n, e): _note("ERROR [%s] %s" % [n, e]))
	# Worsts since the last line; _process prints and clears them once a second.
	world.frame_finished.connect(func(s):
		_runtime_worst = maxf(_runtime_worst, float(s.get("client_millis", 0.0)))
		_apply_worst = maxf(_apply_worst, float(s.get("host_apply_ms", 0.0)))
		_submit_worst = maxf(_submit_worst, float(s.get("host_submit_ms", 0.0)))
		_changes_most = maxi(_changes_most, int(s.get("changes", 0))))

	root.add_child(main)
	print("[join] asking %s:%d for the town" % [host, port])

var _frame_worst := 0.0
var _runtime_worst := 0.0
var _apply_worst := 0.0      # host applying a frame's changes: meshes, GUI, sounds
var _submit_worst := 0.0     # host taking its snapshot and handing the frame over
var _changes_most := 0
var _frames := 0
var _since := 0.0
var _last_usec := 0

func _process(_delta: float) -> bool:
	if world == null or not is_instance_valid(world):
		return true
	var usec := Time.get_ticks_usec()
	if _last_usec > 0:
		var ms := (usec - _last_usec) / 1000.0
		_frame_worst = maxf(_frame_worst, ms)
		_since += ms
		_frames += 1
		if _since >= 1000.0:
			var n: Dictionary = world.net_stats() if world.has_method("net_stats") else {}
			# net_stats() pops the byte and packet counts, so reading it once a second gives per-second rates.
			print("[client] %d fps, longest frame %.0f ms, runtime up to %.1f ms | rtt %.0f ms (last %.0f), loss %.1f%%, up %d B/s in %d, down %d B/s in %d" % [
				_frames, _frame_worst, _runtime_worst, float(n.get("rtt_ms", 0)), float(n.get("rtt_last_ms", 0)), float(n.get("loss", 0)) * 100.0,
				int(n.get("sent_bytes", 0)), int(n.get("sent_packets", 0)), int(n.get("recv_bytes", 0)), int(n.get("recv_packets", 0))])
			# Engine-wide counters to lay against a frame that grew; orphan nodes mean a leak.
			print("[client] yardstick %.1f ms | nodes %d (orphans %d), objects %d, draws %d, textures %.0f MB, video %.0f MB, process %.0f ms, physics %.0f ms | host apply up to %.1f ms, submit up to %.1f ms, most changes in a frame %d" % [
				_yardstick(),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
				Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
				_apply_worst, _submit_worst, _changes_most])
			_frames = 0; _since = 0.0; _frame_worst = 0.0; _runtime_worst = 0.0; _apply_worst = 0.0; _submit_worst = 0.0; _changes_most = 0
			_texture_census()
	_last_usec = usec
	var now: bool = world.is_server_connected()
	if now != _was:
		_was = now
		print("[join] %s" % ("in" if now else "not connected"))
	return false

## Fixed arithmetic that never touches the game: when every number above grows together, this
## one grows only if the machine itself slowed down or is being shared.
func _yardstick() -> float:
	var t0 := Time.get_ticks_usec()
	var x := 0
	for i in 20000:
		x = (x * 31 + i) & 0xFFFF
	return (Time.get_ticks_usec() - t0) / 1000.0

## What texture memory is made of, whenever it has moved 30 MB since the last look. Godot 4.3
## will not list its textures, so this counts the two kinds this program makes: font atlas pages
## per face and size, through the TextServer, and every render target in the tree.
var _census_at_mb := 0.0
func _texture_census() -> void:
	var now_mb: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	if absf(now_mb - _census_at_mb) < 30.0:
		return
	_census_at_mb = now_mb
	var ts := TextServerManager.get_primary_interface()
	var seen := {}
	var faces := 0
	var sizes := 0
	var pages := 0
	var font_bytes := 0
	var per_size := {}
	for n in get_root().find_children("*", "Control", true, false):
		var f: Font = null
		if n.has_method("get_theme_font"):
			f = n.get_theme_font("font")
		if f == null:
			continue
		for rid in f.get_rids():
			if seen.has(rid):
				continue
			seen[rid] = true
			faces += 1
			for sz in ts.font_get_size_cache_list(rid):
				sizes += 1
				var count: int = ts.font_get_texture_count(rid, sz)
				for i in count:
					var img: Image = ts.font_get_texture_image(rid, sz, i)
					if img == null:
						continue
					var b: int = img.get_data_size()
					pages += 1
					font_bytes += b
					var key := "%dpx/%d" % [sz.x, sz.y]
					per_size[key] = float(per_size.get(key, 0.0)) + b / 1048576.0
	print("[client] textures %.0f MB: fonts %d face(s), %d size(s), %d atlas page(s), %.1f MB" % [now_mb, faces, sizes, pages, font_bytes / 1048576.0])
	var keys := per_size.keys()
	keys.sort_custom(func(a, b): return per_size[a] > per_size[b])
	for k in keys.slice(0, 8):
		print("[client]   font size %s: %.1f MB" % [k, per_size[k]])
	var vps := get_root().find_children("*", "SubViewport", true, false)
	var vp_bytes := 0.0
	for vp in vps:
		var sz: Vector2i = vp.get_size()
		vp_bytes += sz.x * sz.y * (4.0 if vp.is_3d_disabled() else 12.0)
	print("[client]   %d render target(s), about %.1f MB" % [vps.size(), vp_bytes / 1048576.0])
	# This program's own textures, grouped by the site that made them.
	if world.has_method("texture_tally"):
		var tally: Dictionary = world.texture_tally()
		var sites := tally.keys()
		sites.sort_custom(func(a, b): return float(tally[a].get("mb", 0)) > float(tally[b].get("mb", 0)))
		for site in sites:
			print("[client]   %6.1f MB in %d %s" % [float(tally[site].get("mb", 0)), int(tally[site].get("count", 0)), site])
	# The renderer's own buffers scale with the window, and they are most of the rest.
	print("[client]   window %s, 3D scale %.2f, MSAA %d, glow %s" % [str(DisplayServer.window_get_size()), get_root().scaling_3d_scale, get_root().msaa_3d,
		str(world.get_viewport().world_3d.environment.glow_enabled if world.get_viewport() and world.get_viewport().world_3d and world.get_viewport().world_3d.environment else "?")])
	for vp in vps.slice(0, 6):
		print("[client]     %s %s 3d=%s" % [vp.get_path(), str(vp.get_size()), str(not vp.is_3d_disabled())])
