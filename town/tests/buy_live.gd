# Buys something, for real, on PulseChain testnet v4.
#
#   godot --headless --path . -s res://tests/buy_live.gd -- 16
#
# Not part of the offline suite and not run by default: it needs a funded key and spends
# testnet mUSD. It asks the player's own wallet through Ledger.askFor exactly as
# Shop.server.luau does, so the channel exercised is the one a creator's script has. Taking a
# thing off the shelf is one write to the Inventory contract, gated on what you hold; the item
# then comes back wearable, with its textures resolved to local files.
extends SceneTree

const Picture = preload("res://tests/Picture.gd")

var world: PulseBlockzWorld
var wallet: Node
var t := 0.0
var phase := 0
var failed := 0
var want_id := 16          # the Pulse Cape: cheap, and the only item on a shared texture
var said: Array[String] = []
# The listing's content hash: what comes back is named by its bytes, not by the id asked for.
var hash := ""

func check(ok: bool, what: String) -> void:
	if not ok: failed += 1
	print(("  PASS " if ok else "  FAIL ") + what)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			want_id = a.to_int()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	# Nobody here to click the wallet prompt; what it shows is covered elsewhere.
	wallet.confirm_purchases = false
	root.add_child(main)
	world.script_print.connect(func(n, txt):
		said.append(txt)
		print("    [%s] %s" % [n, txt]))
	world.script_error.connect(func(n, e): print("    ERROR [%s] %s" % [n, e]))
	print("== buying #%d, live" % want_id)

func _process(delta: float) -> bool:
	t += delta
	# Asked once a second: Picture.of answers a frame or two later.
	if int(t) != int(t - delta) and world != null:
		Picture.of(world)
	if phase == 0 and t > 6.0:
		phase = 1
		if not wallet.can_buy():
			print("  no key loaded; set PBLOCKZ_PLAYER_KEY or put PLAYER_KEY in .env.testnet")
			quit(1)
			return true
		# What Shop.server.luau writes when a Take button is pressed. The content hash the
		# contract takes is already in the listing's pblockz:// uri, so nothing is looked up.
		var listing := {}
		for l in _payload(wallet).get("listings", []):
			if int(l.get("id", -1)) == want_id:
				listing = l
		if listing.is_empty():
			print("  #%d is not on the shelf; nothing to take" % want_id)
			quit(1)
			return true
		var uri := String(listing.get("uri", ""))
		if uri.begins_with("pblockz://"):
			hash = uri.substr(8).split("?")[0]
		if hash == "":
			print("  #%d does not say what it is made of" % want_id)
			quit(1)
			return true
		world.run_chunk("ask", """
local http = game:GetService("HttpService")
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local player = game:GetService("Players"):GetPlayers()[1]
local want = Ledger.askFor(player, {
    action = "write", to = "%s", fn = "add(bytes32,uint8)",
    args = { "0x%s", %d }, note = "Take #%d off the shelf",
})
Ledger.onResult(function(n, res)
    if n == want then print("RESULT " .. http:JSONEncode(res)) end
end)
""" % [String((_payload(wallet).get("chain", {}) as Dictionary).get("inventory", "")), hash, int(listing.get("tier", 0)), want_id])
		print("  asked; waiting for it to confirm")
	elif phase == 1 and t > 280.0:
		phase = 2
		# It lands in the inventory half, matched by content hash rather than by registry id.
		var owned := false
		var model := ""
		for item in _payload(wallet).get("items", []):
			if String(item.get("source", "")) == "inventory" and String(item.get("uri", "")).find(hash) >= 0:
				owned = true
				model = String(item.get("model", ""))
		check(owned, "the item is in the wallet the chain reports")
		check(model != "", "and its model came down with it")
		check(said.any(func(s): return s.contains("RESULT") and s.contains("\"ok\":true")),
			"the host reported the purchase back into the world")
		check(said.any(func(s): return s.contains("put on")), "and the wardrobe put it on")
		# An unresolved pblockz:// inside the model shows up only as a missing-image warning.
		var files := PackedStringArray()
		var folder := DirAccess.open("user://media")
		if folder:
			files = folder.get_files()
		check(files.size() > 0, "with its pictures and textures cached as local files (%d)" % files.size())
		var big := 0
		for f in files:
			if FileAccess.get_file_as_bytes("user://media/".path_join(f)).size() > 4000:
				big += 1
		check(big > 0, "including the shared gradient the model points at, not just thumbnails")
		print(("%d failed" % failed) if failed else "all passed")
		quit(1 if failed else 0)
	return false

## The player's picture as Ledger.data(player) gives it; see tests/Picture.gd.
func _payload(wallet) -> Dictionary:
	if wallet.world == null:
		return {}
	return Picture.of(wallet.world)
