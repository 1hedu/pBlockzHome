# The client half of solid_net_test.gd: joins the server, reads NetRing out of its own
# Workspace and writes that line to --out.
#
#   godot --headless --path . -s res://tests/solid_peer.gd -- --port=8898 --out=<file>
extends SceneTree

var world: PulseBlockzWorld
var out := ""
var joined := false

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	out = _flag("out", "user://solid_peer.txt")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = "127.0.0.1"
	world.server_port = int(_flag("port", "8898"))
	world.player_name = "Looker"
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_print.connect(_heard)
	get_root().add_child(main)
	var blank := FileAccess.open(out, FileAccess.WRITE)
	if blank: blank.close()

func _heard(_name: String, line: String) -> void:
	if not line.begins_with("SEEN "):
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(line.substr(5))
		f.close()

func _process(_delta: float) -> bool:
	if not world.is_server_connected() or joined:
		return false
	joined = true
	world.run_client_chunk("look", """
while true do
	task.wait(0.5)
	local ring = workspace:FindFirstChild("NetRing")
	if ring then
		print(("SEEN class=%s len=%d head=%s size=%.3f,%.3f,%.3f"):format(ring.ClassName, #ring.MeshData,
			ring.MeshData:sub(1, 40), ring.Size.X, ring.Size.Y, ring.Size.Z))
	end
end
""")
	return false
