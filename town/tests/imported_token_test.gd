# A token pasted in by address travels with the eight the wallet ships with.
#
#   godot --headless --path . -s res://tests/imported_token_test.gd
extends SceneTree

const MADE_UP := "0x70499adEBB11Efd915E3b69E700c331778628707"   # WPLS: real, and not one of the eight
var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("IMPORT %-54s %-8s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	var host := Node.new()
	root.add_child(host)
	var wallet = preload("res://host/Wallet.gd").new()
	wallet.name = "Wallet"
	wallet.auto_start = false
	wallet.dev_key_from_repo = false
	wallet.wallet_address = "0xC8CD89650f12b8b565ba89307e072C10579F6AA6"
	host.add_child(wallet)
	_run.call_deferred(wallet)

func _run(wallet) -> void:
	# In memory only: the file add_token writes beside the wallet is the player's own.
	wallet._pulsex._custom_tokens = [{
		"symbol": "MINE", "address": MADE_UP, "decimals": 18, "name": "Something I pasted in",
	}]
	var listed: Array = wallet._pulsex._pulsex_tokens()
	var found := false
	for t in listed:
		if String(t.get("symbol", "")) == "MINE":
			found = t.get("custom", false) == true
	check("the wallet's own list carries it", found, true)

	var out := {"gas_wei": "1000000000000000000"}
	await wallet._collect_pulsex(out)
	var px: Dictionary = out.get("pulsex", {})
	var sent := {}
	for t in px.get("tokens", []):
		sent[String(t.get("symbol", ""))] = t
	check("it reaches the list a place is handed", sent.has("MINE"), true)
	check("with a balance read for it", String(sent.get("MINE", {}).get("balance_units", "")) != "", true)
	check("marked as one of this player's own", sent.get("MINE", {}).get("custom", false), true)
	check("and the ones it ships with are still there", sent.has("PLS") and sent.has("PLSX"), true)
	check("PLS carries the wallet's own balance", String(sent.get("PLS", {}).get("balance_units", "")), "1000000000000000000")
	print("IMPORT %d passed, %d failed" % [ok, bad])
	print("imported token: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
