# A shown Engram's "Open the page" opens that page in this player's own explorer, driven by the
# Showcase's own Go binding rather than a server remote.
#
#   godot --headless --path . -s res://tests/engram_open_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("engram open")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _run() -> void:
	await create_timer(12.0).timeout
	world.run_client_chunk("press", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
local explorer = gui:FindFirstChild("Explorer")
print("ENGRAM before " .. tostring(explorer and explorer.Enabled))
-- What the Showcase's button does with a transaction on the card.
local goTo = explorer and explorer:FindFirstChild("Go")
if goTo then goTo:Fire("tx", "0x" .. string.rep("ab", 32)) end
task.wait(0.3)
local status
for _, d in ipairs(explorer:GetDescendants()) do
	if d:IsA("TextLabel") and (d.Text == "Loading..." or d.Text:find("explorer")) then status = d.Text end
end
print("ENGRAM after " .. tostring(explorer.Enabled) .. "|" .. tostring(status))
""")
	await create_timer(2.0).timeout
	check(_last("ENGRAM before ") == "false", "the explorer is shut to begin with: %s" % _last("ENGRAM before "))
	check(_last("ENGRAM after ").begins_with("true|"), "and the button opens it: %s" % _last("ENGRAM after "))
	check(_last("ENGRAM after ").ends_with("|Loading...") or _last("ENGRAM after ").contains("explorer"),
		"asking for that page: %s" % _last("ENGRAM after "))
	var src := FileAccess.get_file_as_string("res://scripts/src/client/Showcase.client.luau")
	check(src.contains("goTo:Fire(openView, openPage)") and not src.contains("FireServer(\"go\""),
		"and the Showcase's button is what fires it, not a server remote with no such case")
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
