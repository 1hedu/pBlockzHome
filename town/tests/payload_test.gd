# Boots the real place against the real chain and checks the payload a desk gets: Ledger.data(player),
# whose items and listings come off Chain.server.luau and whose gas and history come off the player's own
# Wallet.gd -- a failed assertion names the half to open. town_test feeds its consumers a fixture, so this
# is the only cover the producing half has. It talks to a public node and a live chain: red means look,
# not necessarily broken.
#
#   godot --headless --path . -s res://tests/payload_test.gd
extends SceneTree

const Picture = preload("res://tests/Picture.gd")

var main: Node
var passed := 0
var failed := 0
var got: Dictionary = {}

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

## Ledger.data(player) as a desk sees it. Empty until the place has read its half.
func _payload() -> Dictionary:
	var w = main.get_node("Wallet")
	if w.world == null:
		return {}
	return Picture.of(w.world)

func _initialize() -> void:
	print("the payload, off the real chain")
	main = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	_run()

func _run() -> void:
	# 180s: the wallet publishes its half before the place can read its own -- a hundred-odd
	# calls over three round trips to a public node, plus sixty documents. History lands last.
	var waited := 0.0
	while waited < 180.0:
		got = _payload()
		if String(got.get("status", "")) == "ok" and not (got.get("history", []) as Array).is_empty():
			break
		await create_timer(2.0).timeout
		waited += 2.0

	check(not got.is_empty(), "the place published something")
	if got.is_empty():
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	check(String(got.get("status", "")) == "ok", "and says it finished rather than loading (after %.0fs)" % waited)
	check(String(got.get("address", "")).begins_with("0x"), "for an address")

	# One check per collector, so a break names which one.
	check(String(got.get("gas", "")) != "" and String(got.get("gas_wei", "")) != "",
		"PLS balance: %s" % got.get("gas", ""))
	check((got.get("tokens", []) as Array).is_empty(), "and no mock tokens beside it")

	var items: Array = got.get("items", [])
	check(items.size() > 0, "inventory: %d item(s)" % items.size())
	if items.size() > 0:
		check(String(items[0].get("name", "")) != "", "and they are resolved to names, not ids")
		check(_is_uri(String(items[0].get("uri", ""))), "each naming its own metadata")

	var listings: Array = got.get("listings", [])
	check(listings.size() > 0, "shelf: %d listing(s)" % listings.size())
	if listings.size() > 0:
		var priced := 0
		for l in listings:
			if _is_uri(String(l.get("uri", ""))): priced += 1
		check(priced > 0, "and they carry the uri a shelf claims by")

	var holder: Dictionary = got.get("holder", {})
	check(holder.has("tier"), "the rung you stand on")

	var history: Array = got.get("history", [])
	check(history.size() > 0, "history: %d transaction(s)" % history.size())
	if history.size() > 0:
		check(String(history[0].get("hash", "")).begins_with("0x"), "each with the hash an Engram is taken from")
	check(String(got.get("explorer", "")) != "", "and says which explorer answered")

	# The batched read, against the node. An off-by-one at a slice boundary would hand the place
	# somebody else's answer, so the batch alternates nextId() -- the same number every call --
	# with balanceOf for a different id: a shifted slot stops the constant being constant.
	# The three addresses come off the payload; the client does not hold them. Refusals belong to
	# tests/primitives_test.gd, which pins them in process; nothing here asserts one.
	var w = main.get_node("Wallet")
	var registry := String(got.get("registry", ""))
	var market := String(got.get("marketplace", ""))
	var inv := String((got.get("chain", {}) as Dictionary).get("inventory", ""))
	check(registry.begins_with("0x") and market.begins_with("0x") and inv.begins_with("0x"),
		"the payload names the three contracts the town runs on")
	var calls := []
	for i in 60:
		calls.append({"to": registry, "fn": "nextId()", "args": [], "returns": ["uint256"]})
		calls.append({"to": registry, "fn": "balanceOf(address,uint256)",
			"args": [String(got.get("address", "")), i + 1], "returns": ["uint256"]})
	check(calls.size() > w.READS_PER_TRIP, "the batch is bigger than one round trip: %d calls" % calls.size())
	var many: Dictionary = await w.chain_read_many(calls)
	check(many.get("ok", false), "and the node answered it")
	if many.get("ok", false):
		var res: Array = many.results
		check(res.size() == calls.size(), "every slot came back: %d" % res.size())
		var all_ok := true
		for one in res:
			if not one.get("ok", false): all_ok = false
		check(all_ok, "and every one of them is an answer")
		var first := String(res[0].words[0]) if res.size() > 0 and res[0].get("ok", false) else ""
		var steady := first != ""
		for i in range(0, res.size(), 2):
			if String(res[i].words[0]) != first: steady = false
		check(steady, "the constant stayed constant across all %d, so no slot shifted" % (res.size() / 2))

	# fetch, in each form a place needs. Real documents, because the failures that matter are a
	# thumbnail path with no file behind it and a model under a name the game cannot look up.
	if items.size() > 0:
		var uri := String(items[0].get("uri", ""))
		var doc: Dictionary = await w.host_fetch({"uri": uri, "as": "text"})
		check(doc.get("ok", false), "fetch as text answers")
		var meta = JSON.parse_string(String(doc.get("text", ""))) if doc.get("ok", false) else null
		check(typeof(meta) == TYPE_DICTIONARY and String(meta.get("name", "")) != "",
			"and it is the metadata document, with the item's name in it")
		if typeof(meta) == TYPE_DICTIONARY:
			var thumb := String(meta.get("thumbnail", ""))
			if thumb != "":
				var pic: Dictionary = await w.host_fetch({"uri": thumb, "as": "file"})
				check(pic.get("ok", false) and FileAccess.file_exists(String(pic.get("path", ""))),
					"fetch as file leaves a file that is actually there")
			var model_uri := String(meta.get("model", ""))
			if model_uri != "":
				var mounted: Dictionary = await w.host_fetch({"uri": model_uri, "as": "model"})
				check(mounted.get("ok", false), "fetch as model decodes and mounts it")
				check(String(mounted.get("name", "")) != "", "under a name the game can look it up by")
				var again: Dictionary = await w.host_fetch({"uri": model_uri, "as": "model"})
				check(again.get("name", "") == mounted.get("name", ""),
					"and asking twice mounts once -- the uri is a hash, so it cannot have changed")

		var some := []
		for i in min(8, items.size()):
			some.append(String(items[i].get("uri", "")))
		var lot: Dictionary = await w.host_fetch({"uris": some, "as": "text"})
		check(lot.get("ok", false) and (lot.results as Array).size() == some.size(),
			"a batched fetch answers every slot: %d" % some.size())
		var lined_up := true
		for i in some.size():
			var one: Dictionary = lot.results[i]
			if not one.get("ok", false) or String(one.get("uri", "")) != some[i]:
				lined_up = false
		check(lined_up, "and each answer says which uri it is the answer to")

	# Dynamic returns checked against the collectors' own numbers: two decoders reaching the
	# same answer, rather than read() agreeing with itself.
	var rungs: Dictionary = await w.chain_read(inv, "ladder()", [], ["uint256[]"])
	check(rungs.get("ok", false) and typeof(rungs.words[0]) == TYPE_ARRAY,
		"ladder() reads back as a list rather than a refusal")
	if rungs.get("ok", false):
		var got_rungs: Array = rungs.words[0]
		check(got_rungs.size() > 0, "the ladder has rungs: %d" % got_rungs.size())
		# The place worked out its tier from these same rungs and balance; agreeing covers
		# Units.luau -- decimal comparison against a uint256, where a float goes wrong.
		# Below the first rung is rung -1, the same rule as tests/shelf_ladder_test.gd. The creator
		# key this plays as pays for every publish and holds less than the bottom rung, so -1 is the
		# branch that runs, not a defensive start value.
		var expect := -1
		var held := String(got.get("gas_wei", "0"))
		for i in got_rungs.size():
			var a := held.lstrip("0")
			var b := String(got_rungs[i]).lstrip("0")
			var below := a.length() < b.length() or (a.length() == b.length() and a < b)
			if not below: expect = i
		check(int((got.get("holder", {}) as Dictionary).get("tier", -99)) == expect,
			"and the place stands on rung %d, worked out from the same wei" % expect)

	# Three dynamic arrays in one return: the second and third offsets are what a half-decoder
	# gets wrong.
	var page: Dictionary = await w.chain_read(inv, "inventoryOf(address,uint256,uint256)",
		[String(got.get("address", "")), 0, 128], ["bytes32[]", "bytes32[]", "bytes32[]"])
	check(page.get("ok", false), "inventoryOf answers")
	if page.get("ok", false):
		var ids: Array = page.words[0]
		var counts: Array = page.words[1]
		var datas: Array = page.words[2]
		check(ids.size() > 0, "with a page of ids: %d" % ids.size())
		check(counts.size() == ids.size() and datas.size() == ids.size(),
			"and all three arrays the same length, so the later offsets were read right")
		var held := 0
		for c in counts:
			if String(c).trim_prefix("0x").lstrip("0") != "": held += 1
		check(held > 0, "at least one of them held")

	# A string return and a list of addresses, asked about an id that is actually on the shelf
	# rather than a low one: id 2 still carries an ipfs:// placeholder uri.
	var shelf_id: int = int(listings[0].get("id", 0)) if listings.size() > 0 else 0
	var named: Dictionary = await w.chain_read(registry, "uri(uint256)", [shelf_id], ["string"])
	check(named.get("ok", false) and (String(named.words[0]).begins_with("pblockz://")),
		"uri() reads back as a uri and not as a wall of hex")
	check(String(named.words[0]) == String(listings[0].get("uri", "")),
		"the same uri the collector read, character for character")
	var pays: Dictionary = await w.chain_read(market, "tokensFor(uint256)", [shelf_id], ["address[]"])
	check(pays.get("ok", false) and typeof(pays.words[0]) == TYPE_ARRAY,
		"tokensFor() reads back as a list of addresses")
	if pays.get("ok", false) and (pays.words[0] as Array).size() > 0:
		check(String(pays.words[0][0]).begins_with("0x") and String(pays.words[0][0]).length() == 42,
			"each of them an address rather than a padded word")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _is_uri(s: String) -> bool:
	return s.begins_with("pblockz://")
