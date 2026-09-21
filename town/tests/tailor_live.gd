# Draws a cape and publishes it on PulseChain testnet v4 for real: the request Tailor writes,
# four transactions, then a fresh read that the item comes back wearable and owned with no token
# minted. Outside the offline suite -- it needs a funded key and spends testnet gas.
#
#   godot --headless --path . -s res://tests/tailor_live.gd
extends SceneTree

const Picture = preload("res://tests/Picture.gd")

var world: PulseBlockzWorld
var wallet: Node
var t := 0.0
var phase := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if not ok: failed += 1
	print(("  PASS " if ok else "  FAIL ") + what)

## A 20 x 26 heart, recognisable enough to eyeball against whatever comes back off the chain.
func drawing() -> String:
	var w := 20
	var rows := PackedStringArray()
	for y in 26:
		var row := ""
		for x in w:
			var dx := (x - 9.5) / 8.0
			var dy := (y - 11.0) / 8.0
			# Implicit heart: inside is (x^2 + y^2 - 1)^3 - x^2 y^3 <= 0.
			var v: float = pow(dx * dx + dy * dy - 1.0, 3.0) - dx * dx * dy * dy * dy
			row += "4" if v <= 0.0 else "0"
		rows.append(row)
	return "".join(rows)

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	wallet.confirm_purchases = false   # nobody here can click the prompt
	root.add_child(main)
	world.script_print.connect(func(n, txt):
		said.append(txt)
		print("    [%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): printerr("    ERROR [%s] %s" % [n, e]))
	print("== drawing a cape and publishing it, live")

func _process(delta: float) -> bool:
	t += delta
	# Asked once a second: the answer lands a frame or two later.
	if int(t) != int(t - delta) and world != null:
		Picture.of(world)
	if phase == 0 and t > 20.0:
		phase = 1
		if not wallet.can_buy():
			print("  no key loaded; set PBLOCKZ_PLAYER_KEY or put PLAYER_KEY in .env.testnet")
			quit(1)
			return true
		var pixels := drawing()
		check(pixels.length() == 520, "the drawing is 20 x 26 cells")
		# Exactly what Tailor.server.luau writes when Publish is pressed.
		world.run_chunk("ask", """
local rs = game:GetService("ReplicatedStorage")
local c = rs:WaitForChild("Chain", 5)
c:SetAttribute("Request", '{"n":902,"action":"tailor","name":"Heart Cape (drawn)","pixels":"%s"}')
c:GetAttributeChangedSignal("Result"):Connect(function()
    print("RESULT " .. tostring(c:GetAttribute("Result")))
end)
""" % pixels)
		print("  asked; four transactions to go")
	elif phase == 1 and t > 300.0:
		phase = 2
		check(said.any(func(s): return s.contains("RESULT") and s.contains("\"ok\":true")),
			"the chain took the picture, the cape, its description and the record")
		var mine := []
		for item in _payload(wallet).get("items", []):
			if String(item.get("source", "")) == "inventory":
				mine.append(item)
		check(mine.size() > 0, "the inventory contract reports it without any token existing")
		var wearable := false
		for item in mine:
			if String(item.get("model", "")) != "":
				wearable = true
				print("  got back: %s  (%s)" % [item.get("name", "?"), String(item.get("id", "")).substr(0, 18)])
		check(wearable, "and its model came down with it, so it can be worn")
		check(said.any(func(s): return s.contains("put on")), "which the wardrobe did")
		print(("%d failed" % failed) if failed else "all passed")
		quit(1 if failed else 0)
	return false

## The player's picture as the desks see it -- Ledger.data(player), see Picture.gd.
func _payload(wallet) -> Dictionary:
	if wallet.world == null:
		return {}
	return Picture.of(wallet.world)
