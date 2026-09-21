# Typing a word into the screener's filter, and the rows that come back.
#
#   godot --path . -s res://tests/screener_search_test.gd -- [word]
#
# A live read, so this checks the SHAPE of a searched row, not its numbers: a search row comes
# back with the board's full twelve fields, and a cell with no field draws "-" instead of
# handing Text a nil.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []
var errors: Array[String] = []
var lit := false
var word := "HEX"

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0: word = args[0]
	print("searching the screener for ", word)
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e):
		errors.append("%s: %s" % [n, e])
		printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line):
		said.append(line)
		if line.begins_with("intro:"): lit = true)
	get_root().add_child(main)
	_run()

func _lines(prefix: String) -> Array:
	var out := []
	for line in said:
		var at := line.find(prefix)
		if at >= 0:
			out.append(line.substr(at + prefix.length()).strip_edges())
	return out

func _run() -> void:
	while not lit:
		await create_timer(0.5).timeout
	# The board reads the chain and the pools on its own first; let that finish before searching.
	await create_timer(26.0).timeout

	world.run_client_chunk("open", """
local Players = game:GetService("Players")
Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("Screener").Enabled = true
""")
	await create_timer(2.0).timeout

	errors.clear()
	said.clear()
	world.run_client_chunk("type", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("Screener")
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("TextBox") then d.Text = "%s" break end
end
""" % word)
	# Covers the box's debounce after the last keystroke plus a real request over the network.
	await create_timer(18.0).timeout

	var threw := []
	for e in errors:
		if String(e).find("Screener") >= 0: threw.append(e)
	check(threw.is_empty(), "the search drew without throwing: %s" % str(threw))

	said.clear()
	world.run_client_chunk("rows", """
local Players = game:GetService("Players")
local screen = Players.LocalPlayer.PlayerGui:FindFirstChild("Screener")
local list
for _, d in ipairs(screen:GetDescendants()) do
	if d:IsA("ScrollingFrame") then list = d break end
end
local rows, blank = 0, 0
for _, r in ipairs(list:GetChildren()) do
	if r:IsA("Frame") then
		rows += 1
		local filled = 0
		for _, c in ipairs(r:GetChildren()) do
			if c:IsA("TextLabel") and c.Text ~= "" then filled += 1 end
		end
		-- A row the host gave four fields for drew four cells and eight dashes; one it gave
		-- nothing for draws nothing at all, which is the shape to catch.
		if filled == 0 then blank += 1 end
		if rows == 1 then print(("FIRST cells=%d"):format(filled)) end
	end
end
print(("ROWS %d blank=%d"):format(rows, blank))
""")
	await create_timer(1.5).timeout

	var rows := _lines("ROWS ")
	var first := _lines("FIRST cells=")
	check(rows.size() > 0, "the list answered: %s" % str(rows))
	if rows.size() == 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var line := String(rows[rows.size() - 1])
	var count := int(line.split(" ")[0])
	check(count > 0, "the search found pools to show: %s" % line)
	check(line.find("blank=0") >= 0, "and every row it drew has something in it: %s" % line)
	check(first.size() > 0 and int(String(first[0])) >= 8,
		"with a full set of columns, not the four the search names: %s" % str(first))

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
