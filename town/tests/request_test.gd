# A place cannot reach the network: what it wants from the chain it writes as a Request
# attribute on the Chain node it shares with the host, and waits to be answered. Proves that
# channel is a queue: a burst of asks written in one frame all survive, and every one comes
# back answered. `who` is the verb because it needs no key, no RPC and no chain.
#
#   godot --headless --path . -s res://tests/request_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the request channel")
	var main: Node = load("res://Main.tscn").instantiate()
	# Headless: nothing here would press Start
	main.show_title = false
	world = main.get_node("World")
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	_run(main)

## The server's Chain, shared with the place: in ServerStorage, so it does not replicate.
## Each client machine has a second Chain of its own, under ReplicatedStorage.
func _chain() -> int:
	var id := 0
	for want in ["ServerStorage", "Chain"]:
		var found := 0
		for cid in world.get_child_ids(id):
			if String((world.get_instance(cid) as Dictionary).get("name", "")) == want:
				found = cid
				break
		if found == 0:
			return 0
		id = found
	return id

## Runs a chunk on the server and returns the lines it printed.
func _server(body: String, wait := 1.0) -> Array[String]:
	said.clear()
	world.run_chunk("request_probe", body)
	await create_timer(wait).timeout
	return said.duplicate()

func _run(_main: Node) -> void:
	var waited := 0.0
	while waited < 40.0 and _chain() == 0:
		await create_timer(1.0).timeout
		waited += 1.0
	check(_chain() != 0, "the place put up a Chain node to be asked through")
	if _chain() == 0:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# ---- a burst survives being written ---------------------------------------------------
	# No yield between the three asks, so all three are written inside one host poll interval.
	await _server('''
local Ledger = require(game:GetService("ServerScriptService"):WaitForChild("Ledger"))
local a = Ledger.ask({ action = "who" })
local b = Ledger.ask({ action = "who" })
local c = Ledger.ask({ action = "who" })
print("ASKED " .. a .. " " .. b .. " " .. c)
''', 0.2)
	var asked := PackedStringArray()
	for line in said:
		if line.begins_with("ASKED "): asked = line.substr(6).split(" ")
	check(asked.size() == 3, "three asks got three numbers")

	# Sampled after 0.2s, before the host has drained anything: all three must still be there.
	var attrs: Dictionary = world.get_attributes(_chain())
	var parsed = JSON.parse_string(String(attrs.get("Request", "")))
	check(typeof(parsed) == TYPE_ARRAY,
		"the channel carries a list, not the last thing somebody said")
	var queued: Array = parsed if typeof(parsed) == TYPE_ARRAY else []
	var ns := PackedStringArray()
	for r in queued:
		if typeof(r) == TYPE_DICTIONARY: ns.append(str(r.get("n", -1)))
	check(ns.size() >= 3,
		"all three are still there and none was written over: %s" % [str(ns)])
	if asked.size() == 3:
		check(ns.has(asked[0]) and ns.has(asked[1]) and ns.has(asked[2]),
			"and they are the three that were asked")
		# The host drains front to back, so queue order is answer order
		check(ns.find(asked[0]) < ns.find(asked[2]),
			"oldest first, so nobody is starved by a busier desk")

	# ---- and every one of them comes back -------------------------------------------------
	var got := await _server('''
local Ledger = require(game:GetService("ServerScriptService"):WaitForChild("Ledger"))
local seen = {}
Ledger.onResult(function(n) seen[n] = true end)
local want = {}
for _ = 1, 3 do table.insert(want, Ledger.ask({ action = "who" })) end
-- Generous, because the host drains in the order it was asked and this town's own
-- publisher is in the queue too: a batched read of the whole shelf is ahead of you and
-- takes as long as it takes. Waiting behind somebody is fine. Being dropped is not, and
-- that is what this measures.
task.wait(30)
local n = 0
for _, w in ipairs(want) do if seen[w] then n += 1 end end
print("ANSWERED " .. n .. " of " .. #want)
''', 34.0)
	var answered := ""
	for line in got:
		if line.begins_with("ANSWERED "): answered = line.substr(9)
	check(answered.begins_with("3 of 3"),
		"a burst of three all get answered: %s" % [answered if answered != "" else "nothing came back"])

	# ---- and an answered one stops being outstanding ---------------------------------------
	# A reply must remove its request, or every poll re-encodes a longer list. Checked against
	# the three just asked, not an empty queue: the Chain publisher asks on a loop.
	await create_timer(1.0).timeout
	attrs = world.get_attributes(_chain())
	parsed = JSON.parse_string(String(attrs.get("Request", "")))
	var still := PackedStringArray()
	if typeof(parsed) == TYPE_ARRAY:
		for r in (parsed as Array):
			if typeof(r) == TYPE_DICTIONARY: still.append(str(r.get("n", -1)))
	var lingering := 0
	for n in ns:
		if still.has(n): lingering += 1
	check(lingering == 0,
		"and an answered request stops being outstanding: %d of the first burst still queued"
		% lingering)

	# Scans are not on this channel and there is nothing to add here for them: an explorer page
	# is scanned by the client reading it, via shared/Scan.luau on that machine's own
	# ReplicatedStorage.Chain.
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
