# The scan, asked from a joined client: that client's own machine fetches the page.
#
#   godot --headless --path . -s res://tests/scan_net_test.gd
#
# A server, and a real client in its own process (chunk_peer.gd) that opens two pages through
# shared/Scan.luau: the home page, and one that is not a page at all. Needs the live testnet
# explorer.
extends SceneTree

const PORT := 8818

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var errors: Array[String] = []
var kids: Array[int] = []
var t := 0.0
var phase := 0
var report := ""

const PEER := """
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Scan = require(ReplicatedStorage:WaitForChild("Scan"))
Scan.page("home", "", function(page)
	print("SEEN HOME " .. tostring(page.ok) .. " " .. tostring(page.title) .. " " .. tostring(page.tables and #page.tables))
end)
Scan.page("block", "not-a-block!!", function(page)
	print("SEEN BAD " .. tostring(page.ok) .. " " .. tostring(page.message))
end)
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _seen() -> PackedStringArray:
	if not FileAccess.file_exists(report): return PackedStringArray()
	return FileAccess.get_file_as_string(report).split("\n", false)

func _line(prefix: String) -> String:
	var lines := _seen()
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("The scan from a joined client")
	report = OS.get_user_data_dir().path_join("scan_peer.txt")
	var chunk_file := OS.get_user_data_dir().path_join("scan_peer.luau")
	DirAccess.remove_absolute(report)
	var f := FileAccess.open(chunk_file, FileAccess.WRITE)
	f.store_string(PEER)
	f.close()
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	var pid := OS.create_process(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "-s", "res://tests/chunk_peer.gd", "--",
		"--port=%d" % PORT, "--chunk=%s" % chunk_file, "--out=%s" % report])
	if pid > 0: kids.append(pid)

func _finish() -> void:
	for pid in kids: OS.kill(pid)
	print("    client said: ", " | ".join(_seen()))
	check(_line("HOME ") == "true PulseChain Testnet v4 2", "the client's own machine fetched the home page, both tables: %s" % _line("HOME "))
	check(_line("BAD ") == "false That is not a page on the scan.", "and refused a page that is not one: %s" % _line("BAD "))
	check(" ".join(_seen()).find("ERROR") < 0, "the client threw nothing")
	check(errors.is_empty(), "the server threw nothing: %s" % str(errors.slice(0, 3)))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and (t > 60.0 or (_line("HOME ") != "" and _line("BAD ") != "")):
		phase = 1
		_finish()
	return false
