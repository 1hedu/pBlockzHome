# gas_for() asks the node what a PulseX write costs instead of sending a fixed limit, and a
# call the chain refuses comes back refused rather than as a number to spend. Removing
# liquidity needs about 480,000 gas on this chain. Estimates only: nothing here is signed.
#
#   godot --headless --path . -s res://tests/pulsex_gas_test.gd
extends SceneTree

# Real calldata: removeLiquidity of 2.2909 LP from the PLSX/WPLS pair, deadline appended.
const REMOVE_CALL := "0xaf2979eb0000000000000000000000008a810ea8b121d08342e9e7696f4a9915cbe494b70000000000000000000000000000000000000000000000001fcaf1a37b820692000000000000000000000000000000000000000000000000473027bb45f7b4220000000000000000000000000000000000000000000000000e0e9c59379a3bb1000000000000000000000000c8cd89650f12b8b565ba89307e072c10579f6aa6%s"
const ROUTER := "0xDaE9dd3d1A52CfCe9d5F2fAC7fDe164D500E50f7"
const WHO := "0xC8CD89650f12b8b565ba89307e072C10579F6AA6"
## The fixed limit an estimate has to come out above, and the fallback when the node refuses.
const WAS_SENT_WITH := 400000

var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("PULSEXGAS %-52s %-12s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	var host := Node.new()
	root.add_child(host)
	var wallet = preload("res://host/Wallet.gd").new()
	wallet.name = "Wallet"
	wallet.auto_start = false
	wallet.dev_key_from_repo = false
	wallet.wallet_address = WHO
	host.add_child(wallet)
	_run.call_deferred(wallet)

func _run(wallet) -> void:
	# A live deadline, so the router's expiry check is not what the estimate reports.
	var deadline := "%064x" % (int(Time.get_unix_time_from_system()) + 1200)
	var live: Dictionary = await wallet.gas_for(ROUTER, REMOVE_CALL % deadline, "0x0", WAS_SENT_WITH)
	print("PULSEXGAS the chain says this call needs %s" % live.gas)
	check("asked for, not guessed", int(live.gas) > WAS_SENT_WITH, true)
	check("and the node did not refuse it", String(live.refused), "")

	# All-f in the liquidity word: more than the wallet holds, so the node refuses this one.
	var too_much := REMOVE_CALL % deadline
	too_much = too_much.substr(0, 74) + "f".repeat(64) + too_much.substr(138)
	var refused: Dictionary = await wallet.gas_for(ROUTER, too_much, "0x0", WAS_SENT_WITH)
	check("a call the chain refuses says so", String(refused.refused) != "", true)
	check("and falls back rather than inventing a limit", int(refused.gas), WAS_SENT_WITH)
	if String(refused.refused) != "":
		print("PULSEXGAS the node's words: %s" % String(refused.refused).substr(0, 90))

	print("PULSEXGAS %d passed, %d failed" % [ok, bad])
	print("pulsex gas: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
