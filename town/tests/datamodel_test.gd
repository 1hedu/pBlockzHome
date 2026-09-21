# The DataModel's identity: JobId, PlaceVersion, PrivateServerId, PrivateServerOwnerId, as a
# script reads them. The second half starts a real server in another process and joins it,
# because a client has to report the SERVER's answers rather than make up its own.
#
#   godot --headless --path . -s res://tests/datamodel_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var server := -1

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the DataModel's identity")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	get_root().add_child(main)
	world.script_print.connect(func(_n, t): said.append(t))
	_run()

## Returns a chunk's first print, so the checks are against what a script sees rather than
## against the host's own copy of the tree.
func _ask(name: String, body: String) -> String:
	said.clear()
	world.run_chunk(name, body)
	await create_timer(0.3).timeout
	return said[0] if said.size() > 0 else ""

func _run() -> void:
	await create_timer(2.0).timeout

	# Play Solo is a server, so it has a JobId of its own.
	var job := await _ask("dm_job", 'print(game.JobId)')
	check(job != "", "a server has a JobId")
	# The shape is the property: places log it and compare two of them, so it must be a
	# version-4 GUID and not a counter.
	var parts := job.split("-")
	check(parts.size() == 5 and parts[0].length() == 8 and parts[1].length() == 4
		and parts[2].length() == 4 and parts[3].length() == 4 and parts[4].length() == 12,
		"shaped like a GUID: %s" % job)
	check(parts.size() == 5 and parts[2].begins_with("4"), "and says which kind of GUID it is")
	var hexish := true
	for ch in job:
		if ch != "-" and not ("0123456789abcdef".find(ch) >= 0): hexish = false
	check(hexish, "hex the whole way through")

	# ReadOnly means a script cannot claim to be another server.
	var refused := await _ask("dm_write", '''
local ok, err = pcall(function() game.JobId = "pretend" end)
print(tostring(ok) .. "|" .. tostring(game.JobId))
''')
	check(refused.begins_with("false|"), "a script cannot assign it")
	check(refused.ends_with("|" + job), "and it is unchanged after trying")

	var priv := await _ask("dm_priv", 'print("[" .. game.PrivateServerId .. "]" .. tostring(game.PrivateServerOwnerId))')
	check(priv == "[]0", "a public server has no PrivateServerId and no owner")

	# Settable by the host only, as on Roblox: nothing inside the sandbox can claim to be a
	# private server it is not.
	world.set_property(0, "PrivateServerId", "reserved-1")
	world.set_property(0, "PrivateServerOwnerId", 4242)
	world.set_property(0, "PlaceVersion", 1770000000)
	await create_timer(0.3).timeout
	var stated := await _ask("dm_stated", 'print(game.PrivateServerId .. "|" .. tostring(game.PrivateServerOwnerId) .. "|" .. tostring(game.PlaceVersion))')
	check(stated == "reserved-1|4242|1770000000", "the host states them and a script reads them: %s" % stated)

	# ---- the other process -------------------------------------------------------------
	var exe := OS.get_executable_path()
	server = OS.create_process(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://Serve.gd", "--", "--port=8811", "--private=reserved-7", "--owner=99"])
	check(server > 0, "a real server started in another process")
	if server > 0:
		await create_timer(6.0).timeout
		var joined: Node = load("res://Main.tscn").instantiate()
		var cw: PulseBlockzWorld = joined.get_node("World")
		cw.mode = 2                      # Client: fed by the server
		cw.server_address = "127.0.0.1"
		cw.server_port = 8811
		cw.auto_join = true
		var heard: Array[String] = []
		cw.script_print.connect(func(_n, t): heard.append(t))
		get_root().add_child(joined)
		await create_timer(8.0).timeout
		heard.clear()
		cw.run_chunk("dm_client", 'print(game.JobId .. "|" .. game.PrivateServerId .. "|" .. tostring(game.PrivateServerOwnerId))')
		await create_timer(1.0).timeout
		var got := heard[0] if heard.size() > 0 else ""
		var bits := got.split("|")
		check(bits.size() == 3 and bits[0] != "" and bits[0] != job,
			"the client reads the SERVER's JobId, not its own or an empty one: %s" % got)
		check(bits.size() == 3 and bits[1] == "reserved-7" and bits[2] == "99",
			"and the private server the operator declared")
		OS.kill(server)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
