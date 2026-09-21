# A client that signs the server's nonce with --key but claims to be --claim, for a server
# that has to notice the signer is not the address claimed.
#
#   godot --headless --path . -s res://tests/identity_forger.gd -- --port=<port> --claim=<address> --key=<hex> --out=<file> [--for=<host:port>]
#
# With --for, the signature is honest and for its own address but bound to another server's
# name: the replay a server you joined can mount elsewhere. Writes JOINED, DISCONNECTED and
# FORGED <address> to --out.
extends SceneTree

var world: PulseBlockzWorld
var out := ""

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _write(line: String) -> void:
	var f := FileAccess.open(out, FileAccess.READ_WRITE) if FileAccess.file_exists(out) else FileAccess.open(out, FileAccess.WRITE)
	if not f: return
	f.seek_end()
	f.store_line(line)
	f.close()

func _initialize() -> void:
	out = _flag("out", "user://forger.txt")
	var claim := _flag("claim", "")
	var key := _flag("key", "")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = int(_flag("port", "8822"))
	world.player_name = _flag("name", "Forger")
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.server_connected.connect(func(_id): _write("JOINED"))
	world.server_disconnected.connect(func(): _write("DISCONNECTED"))
	var relay_for := _flag("for", "")
	if relay_for != "":
		claim = PulseBlockzCrypto.address_from_key(key)
	world.sign_in_requested.connect(func(nonce: String):
		var message: String = world.sign_in_message(nonce)
		if relay_for != "":
			message = "PulseBlockz sign-in\nServer: %s\nNonce: %s" % [relay_for, nonce]
		var prefixed := String.chr(0x19) + "Ethereum Signed Message:\n%d" % message.to_utf8_buffer().size() + message
		var sig := PulseBlockzCrypto.sign_digest(PulseBlockzCrypto.keccak256(prefixed.to_utf8_buffer()), key)
		_write("FORGED " + claim)
		world.answer_sign_in(claim, sig, relay_for))
	get_root().add_child(main)
