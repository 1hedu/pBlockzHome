# The demo town, headless: Main.tscn with World.mode = Server, no camera and no local player.
#
#   godot --headless --path . -s res://Serve.gd -- [--port=8800] [--max=32]
#                                                  [--private[=id]] [--owner=<UserId>]
extends SceneTree

const DEFAULT_PORT := 8800
const DEFAULT_MAX := 32

var world: PulseBlockzWorld
var main: Node
var _said := {}          # id -> name, as of the last frame

func _flag(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return int(a.get_slice("=", 1))
	return fallback

func _text_flag(name: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a == "--%s" % name:
			return "yes"
		if a.begins_with("--%s=" % name):
			return a.get_slice("=", 1)
	return ""

## `game.PrivateServerId` and `game.PrivateServerOwnerId`, from `--private[=<id>]` and
## `--owner=<UserId>`; Roblox reserves the id, here the operator supplies it. As on Roblox the
## engine gates nothing on them: a place that wants a door reads them and builds one.
func _private() -> Dictionary:
	var id := _text_flag("private")
	if id == "":
		return {"id": "", "owner": 0}
	if id == "yes":
		# Made up here, so it lasts one run; --private=<id> is how one id outlives a restart.
		id = "%x%x" % [Time.get_unix_time_from_system(), randi()]
	return {"id": id, "owner": _flag("owner", 0)}

func _initialize() -> void:
	var port := _flag("port", DEFAULT_PORT)
	var max_players := _flag("max", DEFAULT_MAX)

	main = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	# The world's own _ready reads mode, then calls listen(listen_port, max_clients). All three
	# have to be set before add_child, or it comes up Play Solo with no socket.
	world.mode = 1                      # Server: the server half alone
	world.listen_port = port
	world.max_clients = max_players
	# --public=play.example.com[,other.name]: a sign-in names the server it is for, and one
	# naming a name this box does not answer to is refused. These names are additions -- it
	# already answers to localhost and to its own addresses.
	var names := _text_flag("public")
	if names != "" and names != "yes":
		world.public_names = PackedStringArray(Array(names.split(",", false)))
	# Nobody is sitting here: no camera, no input, and the host takes no player slot.
	world.default_camera = false
	world.default_controls = false
	world.auto_join = false
	# `-- --place pblockz://<hash>` runs a published game instead of this project's scripts, each
	# file checked against its hash. Nobody is here to answer the prompt; the command line did.
	main.confirm_place = false
	main.show_title = false
	root.add_child(main)

	var private := _private()
	if private.id != "":
		# id 0 is the DataModel. Both are ReadOnly to scripts and writable by the host, as on
		# Roblox: nothing in the sandbox can claim to be a private server.
		world.set_property(0, "PrivateServerId", private.id)
		world.set_property(0, "PrivateServerOwnerId", private.owner)
		print("[serve] private server %s, owned by %d" % [private.id, private.owner])

	# bundle.sh writes the commit and the .so's date here, so a stale process is visible in the log.
	if FileAccess.file_exists("res://BUILD_STAMP"):
		print("[serve] build: " + FileAccess.get_file_as_string("res://BUILD_STAMP").strip_edges().replace("\n", ", "))
	world.frame_finished.connect(func(s): _runtime_worst = maxf(_runtime_worst, float(s.get("millis", 0.0))))
	print("[serve] the town is up on %d, room for %d" % [port, max_players])
	print("[serve] ownership and assets are on the chain; this holds where people are, what they did")
	print("[serve] this frame, and the town's own game state in its DataStores -- and no keys")

## Player id -> name, read off the Players service in the world's mirror of the instance tree.
func _players() -> Dictionary:
	var out := {}
	if world == null or not is_instance_valid(world):
		return out
	for id in world.get_child_ids(0):
		if world.get_instance(id).class_name == "Players":
			for pid in world.get_child_ids(id):
				out[pid] = world.get_instance(pid).name
			break
	return out

var _frame_worst := 0.0
var _runtime_worst := 0.0
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
			if _frame_worst > 40.0:
				print("[serve] %d fps, longest frame %.0f ms, runtime up to %.1f ms" % [_frames, _frame_worst, _runtime_worst])
			_frames = 0; _since = 0.0; _frame_worst = 0.0; _runtime_worst = 0.0
	_last_usec = usec
	var now := _players()
	for id in now:
		if not _said.has(id):
			print("[serve] joined: %s" % now[id])
	for id in _said:
		if not now.has(id):
			print("[serve] left: %s" % _said[id])
	_said = now
	return false
