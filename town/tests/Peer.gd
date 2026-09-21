# A child process standing in for somebody else's machine: its own user:// under this
# process's user dir, its own key or none, and the camera and wallet half a real client has.
#
# opts:
#   key       "" for a guest with no key; absent for a fresh random key of its own
#   camera    default true; with no camera the engine skips its roll-off and every sound
#             plays at full volume
#   reads     default true: the wallet reads its own balances off the chain
#   noconfirm default false: the wallet sends without its confirm prompt
#   name, host, env, and n, the user folder's number -- default this process's id and the
#             count spawned so far, so two tests running at once never share a folder
extends RefCounted

static var spawned := 0

static func spawn(script: String, args: PackedStringArray, opts: Dictionary = {}) -> Dictionary:
	spawned += 1
	var n := int(opts.get("n", OS.get_process_id() * 100 + spawned))
	var user_dir := OS.get_user_data_dir().path_join("peers").path_join("peer-%d" % n)
	DirAccess.make_dir_recursive_absolute(user_dir)
	# Godot puts user:// under %APPDATA%/Godot/app_userdata/<name> on Windows and
	# $XDG_DATA_HOME/godot/app_userdata/<name> elsewhere, so these two decide the child's user://.
	# Share the parent's folder and the peer can open whatever the server already fetched, so a
	# server handing out its own local paths as asset ids still passes a test a real client fails.
	var env := {
		"APPDATA": user_dir, "XDG_DATA_HOME": user_dir,
		"PBLOCKZ_NO_DEV_KEY": "1",  # without it the peer picks up the dev key and signs as the founder
		"PBLOCKZ_PLAYER_KEY": String(opts.key) if opts.has("key") else _fresh_key(),
	}
	for k in opts.get("env", {}): env[k] = String(opts.env[k])
	var saved := {}
	for k in env:
		saved[k] = OS.get_environment(k) if OS.has_environment(k) else null
		OS.set_environment(k, env[k])
	var all := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", script, "--"])
	all.append_array(args)
	if bool(opts.get("camera", true)): all.append("--camera=1")
	if bool(opts.get("reads", true)): all.append("--reads=1")
	if bool(opts.get("noconfirm", false)): all.append("--noconfirm=1")
	if opts.has("name"): all.append("--name=%s" % String(opts.name))
	if opts.has("host"): all.append("--host=%s" % String(opts.host))
	var pid := OS.create_process(OS.get_executable_path(), all)
	for k in saved:
		if saved[k] == null: OS.unset_environment(k)
		else: OS.set_environment(k, saved[k])
	return { "pid": pid, "user_dir": user_dir, "n": n }

static func stop(p: Dictionary) -> void:
	if int(p.get("pid", 0)) > 0: OS.kill(int(p.pid))

## Random bytes: a key valid for signing that holds nothing and belongs to nobody.
static func _fresh_key() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var hex := ""
	for i in 32: hex += "%02x" % rng.randi_range(0, 255)
	return "0x" + hex
