# The three primitives a place may ask of a wallet: read, write, who. A place cannot be shown
# one signature and sign another, and every refusal lands before anything is signed.
#
#   godot --headless --path . -s res://tests/primitives_test.gd
extends SceneTree

const Abi = preload("res://host/Abi.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the three primitives")
	var w = preload("res://host/Wallet.gd").new()

	check(w._arg_types("setFighting(bool)") == ["bool"], "reads one argument type")
	check(w._arg_types("add(bytes32,uint8)") == ["bytes32", "uint8"], "reads several")
	check(w._arg_types("ladder()") == [], "reads none")
	check(w._arg_types("garbage") == [], "refuses to guess at a malformed signature")

	# The selector is derived from the signature shown, so display and send cannot differ.
	var shown := "setFighting(bool)"
	var sneaky := "transferOwnership(address)"
	check(Abi.selector(shown) != Abi.selector(sneaky), "two signatures are two selectors")
	# The expected selectors come from ethers.js, not from this code.
	check(Abi.selector(shown) == "0xd4e76132", "and setFighting's matches ethers")
	check(Abi.selector(sneaky) == "0xf2fde38b", "as does transferOwnership's")
	# 10 = "0x" and the four-byte selector; 64 = one 32-byte ABI word.
	var data := Abi.selector(shown) + Abi.encode(["bool"], [true])
	check(data.begins_with(Abi.selector(shown)),
		"the calldata a place gets is prefixed by the signature it displayed")
	check(data.length() == 10 + 64, "and carries exactly its arguments")

	var who: Dictionary = w.chain_who()
	check(who.ok and not who.can_sign, "who() answers, and says signing is off with no key")
	check(who.has("network") and who.has("chain_id"), "and which chain it would be")

	var refused: Dictionary = await w.chain_write("0x" + "11".repeat(20), "setFighting(bool)", [true], "", "")
	check(not refused.ok, "a write with no key is refused")

	w._key = "0x" + "22".repeat(32)
	var bad: Dictionary = await w.chain_write("not-an-address", "setFighting(bool)", [true], "", "")
	check(not bad.ok and String(bad.message).find("address") >= 0, "a write to a non-address is refused")
	var wrong: Dictionary = await w.chain_write("0x" + "11".repeat(20), "setFighting(bool)", [], "", "")
	check(not wrong.ok and String(wrong.message).find("argument") >= 0,
		"a write whose arguments do not match its signature is refused")

	# store takes bytes and returns a uri. Refusals only: a store that goes through is a real
	# transaction and spends gas.
	w._key = ""
	var nokey: Dictionary = await w.chain_store(Marshalls.raw_to_base64("hello".to_utf8_buffer()), "text/plain", "")
	check(not nokey.ok, "a store with no key is refused")
	w._key = "0x" + "22".repeat(32)
	var empty: Dictionary = await w.chain_store("", "text/plain", "")
	check(not empty.ok, "storing nothing is refused rather than sent")
	# The ceiling is the store contract's chunk size, not a client preference.
	var huge := Marshalls.raw_to_base64(PackedByteArray(range(30000).map(func(_i): return 65)))
	var big: Dictionary = await w.chain_store(huge, "text/plain", "")
	check(not big.ok and String(big.message).find("too big") >= 0,
		"a blob past one chunk is refused before anything is signed")

	# Refusals only again: a fetch that goes through needs a live chain to fetch from.
	var nofetch: Dictionary = await w.host_fetch("pblockz://deadbeef")
	check(not nofetch.ok, "a fetch with nothing to fetch with is refused")
	var notauri: Dictionary = await w.host_fetch("https://example.com/x.png")
	check(not notauri.ok and String(notauri.message).find("pblockz") >= 0,
		"and a fetch of anything but a pblockz:// uri is refused before it goes anywhere")
	var badmode: Dictionary = await w.host_fetch({"uri": "pblockz://deadbeef", "as": "sideways"})
	check(not badmode.ok and String(badmode.message).find("bytes") >= 0,
		"and a fetch as something the client cannot decode to is refused, not guessed at")
	# pblockz://<hash, no 0x>?chain=<chain id>:<store>:<blob>&mime=..., composed by the client
	# from the fields a store contract hands back -- ch::formatAssetUri in chain_assets.cpp
	var composed: String = w._uri_of({"hash": "0x" + "ab".repeat(32), "store": "0x" + "cd".repeat(20),
		"blob": 7, "mime": "application/json"})
	check(composed.begins_with("pblockz://" + "ab".repeat(32)), "parts compose into a uri named by the hash")
	check(composed.find(":7") > 0 and composed.find("chain=") > 0, "carrying the store and blob that hold it")
	check(w._uri_of({"hash": "0x" + "ab".repeat(32)}) == "", "and a hash with no blob composes nothing rather than something wrong")

	# A batched read answers slot for slot, including the entries refused before they reach
	# the node -- those are what can shift the rest out of line.
	var mixed: Dictionary = await w.chain_read_many([
		{"to": "not-an-address", "fn": "ladder()", "returns": []},
		{"to": "0x" + "11".repeat(20), "fn": "add(bytes32,uint8)", "args": [], "returns": []},
		"not a table",
	])
	check(mixed.ok and (mixed.results as Array).size() == 3,
		"a batched read answers every slot, including the ones it refused")
	check(not mixed.results[0].ok and String(mixed.results[0].message).find("address") >= 0,
		"the bad address is refused in its own slot")
	check(not mixed.results[1].ok and String(mixed.results[1].message).find("argument") >= 0,
		"as is the one whose arguments do not match its signature")
	check(not mixed.results[2].ok, "and something that is not a call at all")
	var none: Dictionary = await w.chain_read_many([])
	check(none.ok and (none.results as Array).is_empty(), "asking nothing answers nothing, and says so")
	var toomany := []
	for i in w.MAX_READS + 1:
		toomany.append({"to": "0x" + "11".repeat(20), "fn": "ladder()", "returns": []})
	var over: Dictionary = await w.chain_read_many(toomany)
	check(not over.ok and String(over.message).find("at most") >= 0,
		"and there is a ceiling, so a place cannot ask for the whole chain in one breath")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
