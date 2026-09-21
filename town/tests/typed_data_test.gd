# EIP-712 in the host, against ethers' own vectors.
#
#   node scripts/gen-typed-vectors.js     (writes tests/typed_vectors.json)
#   godot --headless --path . -s res://tests/typed_data_test.gd
extends SceneTree

const TypedData = preload("res://host/TypedData.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("typed data")
	var raw := FileAccess.get_file_as_string("res://tests/typed_vectors.json")
	var doc = JSON.parse_string(raw)
	check(typeof(doc) == TYPE_DICTIONARY, "the vectors are there")
	if typeof(doc) != TYPE_DICTIONARY:
		_finish()
		return
	var key := String(doc.key)
	for v in doc.vectors:
		var got := TypedData.digest(v.typed)
		var hex := "0x" + (got.get("digest", PackedByteArray()) as PackedByteArray).hex_encode()
		check(got.get("ok", false) and hex == String(v.digest), "%s: the digest ethers computes (%s)" % [v.name, hex.substr(0, 18)])
		if got.get("ok", false):
			var sig: String = PulseBlockzCrypto.sign_digest(got.digest, key)
			check(PulseBlockzCrypto.recover_address(got.digest, sig) == String(doc.signer)
				and PulseBlockzCrypto.recover_address(got.digest, String(v.signature)) == String(doc.signer),
				"%s: the host's signature and ethers' both recover to the signer" % v.name)

	var bad: Dictionary = (doc.vectors[1].typed as Dictionary).duplicate(true)
	bad.message.teamA = ["not an address"]
	check(not TypedData.digest(bad).get("ok", true), "an address that is not one is refused")
	var missing: Dictionary = (doc.vectors[1].typed as Dictionary).duplicate(true)
	missing.message.erase("winner")
	check(not TypedData.digest(missing).get("ok", true), "a missing field is refused")

	_wallet(doc)

## Wallet.sign_typed with the confirmation prompt off -- nothing here can click it.
func _wallet(doc: Dictionary) -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	var wallet: Node = main.get_node("Wallet")
	wallet.auto_start = false
	wallet.confirm_purchases = false
	get_root().add_child(main)
	await create_timer(0.5).timeout
	var duel: Dictionary = (doc.vectors[1].typed as Dictionary).duplicate(true)

	wallet._key = ""
	var keyless: Dictionary = await wallet.sign_typed(duel, "")
	check(not keyless.get("ok", true), "with no key there is nothing to sign with: %s" % keyless.get("message", ""))

	wallet.adopt_key(String(doc.key))
	var signed: Dictionary = await wallet.sign_typed(duel, "a test")
	check(signed.get("ok", false) and String(signed.get("signature", "")).length() == 132, "the wallet signs typed data")
	var digest: PackedByteArray = TypedData.digest(duel).digest
	check(PulseBlockzCrypto.recover_address(digest, String(signed.get("signature", ""))) == String(doc.signer),
		"and the signature is the signer's, over that digest")

	var elsewhere: Dictionary = duel.duplicate(true)
	elsewhere.domain.chainId = 1
	var refused: Dictionary = await wallet.sign_typed(elsewhere, "")
	check(not refused.get("ok", true), "a domain for another chain is refused: %s" % refused.get("message", ""))
	_finish()

func _finish() -> void:
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
