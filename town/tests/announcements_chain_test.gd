# Announcements against a real chain: the local one from scripts/dev-chain.js, nothing stood in.
#
#   node scripts/dev-chain.js --block-time 2        (in another shell, and leave it running)
#   PBLOCKZ_RPC_URL=http://127.0.0.1:8545 godot --headless --path . -s res://tests/announcements_chain_test.gd
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var run := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _announce(text: String) -> void:
	_dev(["announce", text])

func _dev(args: Array) -> void:
	var out := []
	OS.execute("node", [ProjectSettings.globalize_path("res://../../../scripts/dev-chain.js")] + args, out, true)
	print("    ", "".join(out).strip_edges())

## The chat's pinned and newest lines: "count|pinned@LayoutOrder|newest@LayoutOrder".
func _pinned() -> String:
	said = said.filter(func(l): return not l.begins_with("PINS "))
	world.run_client_chunk("pins", """
local screen = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("TownChat")
local pinned, newest, pins = "none", "none", 0
for _, d in ipairs(screen and screen:GetDescendants() or {}) do
	if d:IsA("TextLabel") and d.Name == "PinnedAnnouncement" then pinned = d.Text .. "@" .. d.LayoutOrder; pins += 1 end
	if d:IsA("TextLabel") and d.Name == "Announcement" then newest = d.Text .. "@" .. d.LayoutOrder end
end
print("PINS " .. pins .. "|" .. pinned .. "|" .. newest)
""")
	await create_timer(0.5).timeout
	return _last("PINS ")

## Polls until `done` accepts the pins; the client itself only looks once a minute.
func _wait_pins(done: Callable) -> String:
	var t := 0.0
	var got := ""
	while t < 80.0:
		got = await _pinned()
		if done.call(got): return got
		await create_timer(4.0).timeout
		t += 4.5
	return got

func _order(entry: String) -> int:
	return int(entry.get_slice("@", entry.get_slice_count("@") - 1))

func _initialize() -> void:
	print("announcements on the dev chain")
	if OS.get_environment("PBLOCKZ_RPC_URL") == "":
		printerr("  FAIL set PBLOCKZ_RPC_URL to the dev chain (node scripts/dev-chain.js prints it)")
		quit(1)
		return
	run = str(randi() % 100000)
	_announce("First announcement %s" % run)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _last(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _chat() -> String:
	said = said.filter(func(l): return not l.begins_with("CHAT "))
	world.run_client_chunk("chat", """
local screen = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("TownChat")
local found = {}
for _, d in ipairs(screen and screen:GetDescendants() or {}) do
	if d:IsA("TextLabel") and d.Name == "Announcement" then
		table.insert(found, d.Text .. "@" .. string.format("%d,%d,%d", d.TextColor3.R * 255, d.TextColor3.G * 255, d.TextColor3.B * 255))
	end
end
print("CHAT " .. #found .. "|" .. table.concat(found, "|"))
""")
	await create_timer(0.5).timeout
	return _last("CHAT ")

func _run() -> void:
	await create_timer(25.0).timeout
	var first := await _chat()
	check(first.begins_with("1|First announcement %s@255,200,60" % run), "arriving, the newest announcement is in chat, in gold (%s)" % first)

	_announce("Second announcement %s" % run)
	var t := 0.0
	var second := ""
	while t < 80.0:
		second = await _chat()
		if second.contains("Second announcement"): break
		await create_timer(4.0).timeout
		t += 4.5
	check(second.begins_with("1|Second announcement %s" % run), "a newer one takes its place, one at a time (%s)" % second)

	world.run_client_chunk("records", "game:GetService('ReplicatedStorage'):WaitForChild('RecordsRemote'):FireServer('announcements')")
	await create_timer(8.0).timeout
	said = said.filter(func(l): return not l.begins_with("HISTORY "))
	world.run_client_chunk("history", """
local screen = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("AnnouncementHistory")
local list = screen and screen:FindFirstChild("List", true)
local rows = {}
for _, d in ipairs(list and list:GetChildren() or {}) do
	if d:IsA("TextLabel") then rows[d.LayoutOrder] = d.Text end
end
print("HISTORY " .. tostring(screen and screen.Enabled) .. "|" .. tostring(rows[1]) .. "|" .. tostring(rows[2]) .. "|" .. #rows)
""")
	await create_timer(0.5).timeout
	var history := _last("HISTORY ").split("|")
	check(history.size() == 4 and history[0] == "true" and history[1].contains("Second announcement %s" % run)
		and history[2].contains("First announcement %s" % run), "the Hall of Records lists them all, newest first (%s)" % _last("HISTORY "))
	world.run_client_chunk("close", "game:GetService('Players').LocalPlayer.PlayerGui.AnnouncementHistory.Enabled = false")

	# The first of this run is second newest.
	var first_index := int(history[3]) - 2 if history.size() == 4 else 0
	_dev(["pin", str(first_index)])
	var pins := await _wait_pins(func(g): return g.contains("First announcement %s" % run))
	var parts := pins.split("|")
	check(parts.size() == 3 and parts[0] == "1" and parts[1].begins_with("First announcement %s" % run)
		and parts[2].begins_with("Second announcement %s" % run) and _order(parts[2]) == _order(parts[1]) + 1,
		"a pinned one sits directly above the newest (%s)" % pins)

	_announce("Third announcement %s" % run)
	pins = await _wait_pins(func(g): return g.contains("Third announcement %s" % run))
	parts = pins.split("|")
	check(parts.size() == 3 and parts[0] == "1" and parts[1].begins_with("First announcement %s" % run)
		and parts[2].begins_with("Third announcement %s" % run) and _order(parts[2]) == _order(parts[1]) + 1,
		"it stays above a newer one (%s)" % pins)

	_dev(["unpin"])
	pins = await _wait_pins(func(g): return g.begins_with("0|"))
	check(pins.begins_with("0|none|Third announcement %s" % run), "unpinned, it goes and the newest stays (%s)" % pins)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
