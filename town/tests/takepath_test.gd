# Taking an Engram: a badge lands in your bag, and the wallet is never asked anything.
#
#   godot --headless --path . -s res://tests/takepath_test.gd
#
# An Engram is a view plus an id, carried as a badge. The request counter must not move across
# a take -- not for a signature, not for a read: any traffic there is a chain dependency.
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var wallet: Node
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the take path")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	# No refresh loop of the wallet's own, so the only chain traffic is what the place asks for.
	wallet.auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, t): said.append(t))
	get_root().add_child(main)
	_run()

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

## Requests the place has made of the wallet so far: the Chain node counts them in Seq.
func _asked() -> int:
	if _chain() == 0:
		return 0
	return int(world.get_attributes(_chain()).get("Seq", 0))

## Fires the Explorer's "keep" from the client; returns the note that comes back, or "".
func _press(view: String, id: String, wait := 3.0) -> String:
	said.clear()
	world.run_client_chunk("take_probe", '''
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("ExplorerRemote")
local conn
conn = remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "note" then print("NOTE " .. tostring(payload)) end
end)
remote:FireServer("keep", "%s", "%s")
task.delay(%d, function() conn:Disconnect() end)
''' % [view, id, int(wait)])
	await create_timer(wait).timeout
	for line in said:
		if line.begins_with("NOTE "): return line.substr(5)
	return ""

## The wardrobe's list of what you hold, one "name|model" per item.
func _bag() -> PackedStringArray:
	said.clear()
	world.run_client_chunk("bag_probe", '''
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("WardrobeRemote")
local conn
conn = remote.OnClientEvent:Connect(function(kind, items)
	if type(items) ~= "table" then return end
	local parts = {}
	for _, item in ipairs(items) do
		table.insert(parts, ("%s|%s"):format(tostring(item.name), tostring(item.model)))
	end
	print("BAG " .. table.concat(parts, "@@"))
end)
remote:FireServer("list")
task.delay(3, function() conn:Disconnect() end)
''')
	await create_timer(2.5).timeout
	for line in said:
		if line.begins_with("BAG "):
			return line.substr(4).split("@@", false)
	return PackedStringArray()

func _run() -> void:
	await create_timer(8.0).timeout
	# The town's startup read of its catalogue and the player's holdings has to land before
	# wallet traffic is counted.
	var settle := 0.0
	while settle < 90.0 and not said.any(func(l): return String(l).begins_with("Chain: ") and String(l).contains("item(s) for")):
		await create_timer(1.0).timeout
		settle += 1.0
	await create_timer(1.0).timeout

	# ---- a page that is not one thing --------------------------------------------------
	# The front page lists the latest blocks, and the chain makes one about every ten seconds, so
	# there is nothing there to pin. The refusal has to come back as a note, not as silence.
	var home := await _press("home", "")
	check(home != "", "the front page is refused out loud, not with a silence: %s"
		% [home if home != "" else "nothing came back"])

	# ---- and a page name that is not a name ----------------------------------------------
	var junk := await _press("block", "not a block!")
	check(junk != "", "and so is a page name that could not be one: %s"
		% [junk if junk != "" else "nothing came back"])

	# ---- a real page ---------------------------------------------------------------------
	# Block 1 exists on every chain. The counter is read either side of the press, and the note
	# arrives inside the three-second wait -- no signature and no block would.
	var before := _asked()
	var real := await _press("block", "1")
	check(real != "", "a real page gives you one: %s"
		% [real if real != "" else "nothing came back"])
	check(real.find("yours") != -1, "and says so in the words Bex uses for it")
	check(_asked() == before,
		"and it asked the wallet for NOTHING: %d requests before, %d after" % [before, _asked()])

	# ---- it is in your bag -----------------------------------------------------------------
	var bag := await _bag()
	var found := ""
	for one in bag:
		if one.begins_with("Engram block 1|"): found = one
	check(found != "", "it is in your bag like anything else: %s" % [str(bag)])
	check(found.find("|Engram#") != -1,
		"wearing the badge the town built, under a name of its own so two are two: %s" % found)

	# ---- and taking it twice is still one ---------------------------------------------------
	var again := await _press("block", "1")
	check(again.find("already") != -1, "taking the same page twice gives back the one you have: %s"
		% [again if again != "" else "nothing came back"])
	var bag2 := await _bag()
	var count := 0
	for one in bag2:
		if one.begins_with("Engram block 1|"): count += 1
	check(count == 1, "and does not put a second identical badge in your bag: %d" % count)

	# ---- a second page is a second Engram ---------------------------------------------------
	await _press("block", "2")
	var bag3 := await _bag()
	var engrams := 0
	for one in bag3:
		if one.find("|Engram#") != -1: engrams += 1
	check(engrams == 2, "a different page is a different one: %d in the bag" % engrams)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
