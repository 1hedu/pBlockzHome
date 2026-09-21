# The wallet's verdict on a transaction against a real chain: confirmed only with a receipt,
# a refused call reported reverted, stored bytes coming back with the chain's blob id.
#
#   anvil --fork-url https://rpc.v4.testnet.pulsechain.com --port 8547 --block-time 3 --hardfork shanghai
#   PBLOCKZ_RPC_URL=http://127.0.0.1:8547 PBLOCKZ_PLAYER_KEY=<a key with testnet PLS> godot --headless --path . -s res://tests/wallet_receipt_chain_test.gd
#
# --block-time 3 is what catches a wallet calling a transaction confirmed before it is mined.
extends SceneTree

const FISHING := "0x5d8CB335B202e456b82113a92cBEb6508a5746Fc"

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("wallet receipts on a chain")
	if OS.get_environment("PBLOCKZ_RPC_URL") == "" or OS.get_environment("PBLOCKZ_PLAYER_KEY") == "":
		printerr("  FAIL set PBLOCKZ_RPC_URL to a local fork and PBLOCKZ_PLAYER_KEY to a funded key")
		print("0 passed, 1 failed")
		quit(1)
		return
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	main.get_node("World").data_store_path = ""
	var wallet: Node = main.get_node("Wallet")
	wallet.auto_start = false
	wallet.confirm_purchases = false
	get_root().add_child(main)
	_run(wallet)

func _run(wallet: Node) -> void:
	await create_timer(3.0).timeout
	var sent: Dictionary = await wallet.chain_write(wallet.wallet_address, "", [], "0.001", "")
	var receipt: Dictionary = await wallet._rpc_dict("eth_getTransactionReceipt", [String(sent.get("hash", ""))])
	check(sent.get("ok", false) and String(receipt.get("status", "")) == "0x1",
		"a transfer is confirmed, and there is a receipt for it by then: %s / %s" % [sent.get("message", ""), receipt.get("status", "none")])

	# reel() with no line out: Fishing reverts it, at estimate and on chain.
	var refused: Dictionary = await wallet.chain_write(FISHING, "reel()", [], "", "")
	check(not refused.get("ok", true) and String(refused.get("message", "")).contains("reverted"),
		"a call the contract refuses is reported reverted: %s" % refused.get("message", ""))

	var bytes := ("receipt test %d" % Time.get_ticks_msec()).to_utf8_buffer()
	var stored: Dictionary = await wallet.chain_store(Marshalls.raw_to_base64(bytes), "text/plain", "")
	check(stored.get("ok", false) and String(stored.get("uri", "")).contains("chain=943:"),
		"storing bytes comes back with where the chain put them: %s" % stored.get("uri", stored.get("message", "")))

	var block: Dictionary = await wallet._rpc_dict("eth_getBlockByNumber", ["latest", false])
	check(String(block.get("number", "")) != "" and block.has("baseFeePerGas"), "a block reads as a block: number %s" % block.get("number", "none"))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
