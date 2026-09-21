# The transaction signer, against vectors ethers.js produced, offline.
#
#   godot --headless --path . -s res://tests/tx_test.gd
#
# The whole raw transaction is compared byte for byte with ethers.js, not merely round-tripped
# with itself. KEY is anvil's first default account: public, and funded on no real network.
extends SceneTree

const Tx = preload("res://host/Tx.gd")

const KEY := "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
const ADDRESS := "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func equal(got: Variant, want: Variant, what: String) -> void:
	check(got == want, what if got == want else "%s\n         got  %s\n         want %s" % [what, got, want])

func _init() -> void:
	print("tx_test")

	# ---- RLP, on the yellow paper's own examples ----
	equal(Tx.to_hex(Tx.rlp_bytes("dog".to_utf8_buffer())), "0x83646f67", "rlp of a short string")
	equal(Tx.to_hex(Tx.rlp_bytes(PackedByteArray())), "0x80", "rlp of the empty string")
	equal(Tx.to_hex(Tx.rlp_bytes(PackedByteArray([0x0f]))), "0x0f", "a single byte below 0x80 is itself")
	equal(Tx.to_hex(Tx.rlp_bytes(PackedByteArray([0x04, 0x00]))), "0x820400", "rlp of 1024")
	equal(Tx.to_hex(Tx.rlp_list([])), "0xc0", "rlp of the empty list")
	equal(Tx.to_hex(Tx.rlp_list([Tx.rlp_bytes("cat".to_utf8_buffer()), Tx.rlp_bytes("dog".to_utf8_buffer())])),
		"0xc88363617483646f67", "rlp of a list of two strings")
	# 56 bytes is the shortest payload RLP gives a long-form length prefix.
	var long := PackedByteArray()
	for i in 56:
		long.append(0x61)
	equal(Tx.to_hex(Tx.rlp_bytes(long)).substr(0, 6), "0xb838", "long strings take a two-stage length prefix")

	# ---- quantities ----
	equal(Tx.to_hex(Tx.int_bytes(0)), "0x", "zero is the empty string, not a zero byte")
	equal(Tx.to_hex(Tx.hex_bytes("0x0000ff")), "0xff", "leading zeros are stripped from a quantity")
	equal(Tx.arg_uint_dec("0"), "0".lpad(64, "0"), "decimal zero encodes as a zero word")
	equal(Tx.arg_uint_dec("250000000"), "%064x" % 250000000, "a decimal amount matches the hex encoding")
	equal(Tx.arg_uint_dec("1000000000000000000000"), "00000000000000000000000000000000000000000000003635c9adc5dea00000",
		"and keeps working past what a 64-bit int holds")

	# ---- keys ----
	equal(PulseBlockzCrypto.address_from_key(KEY), ADDRESS, "the address derived from a key")
	equal(PulseBlockzCrypto.address_from_key("0xdeadbeef"), "", "a key of the wrong length is refused")

	# ---- a whole transaction, against ethers.js ----
	var tx := {
		"chain_id": 943, "nonce": 7,
		"max_priority_fee": "0x3b9aca00",     # 1 gwei
		"max_fee": "0x77359400",              # 2 gwei
		"gas": 120000,
		"to": "0x9f1A5C5d8328C863EDcDef8416745391A3Ef2968",
		"value": "0x0",
		"data": "0xd96a094a0000000000000000000000000000000000000000000000000000000000000009",
	}
	equal(Tx.to_hex(Tx.signing_digest(tx)), "0xef4d2e7623475a5406cf49d44afdf08b3cb9df8a3fd76aca60f6100d4f7bafd1",
		"the digest a type-2 transaction is signed over")
	equal(Tx.sign(tx, KEY),
		"0x02f8918203af07843b9aca0084773594008301d4c0949f1a5c5d8328c863edcdef8416745391a3ef296880a4d96a094a" +
		"0000000000000000000000000000000000000000000000000000000000000009c001a043a00c8e6313f83ccf231729f6de9c728e1fb8dbde87289637ad0d828ad1c357" +
		"a00d5a30fa5e28d7e6c26de5c47a90bc4de215b3afc5822afd06ecfaf5e255d45d",
		"the signed transaction, byte for byte with ethers.js")

	# RFC6979 nonces: the same input signs the same way every time.
	equal(Tx.sign(tx, KEY), Tx.sign(tx, KEY), "signing is deterministic")

	var sig: String = PulseBlockzCrypto.sign_digest(Tx.signing_digest(tx), KEY)
	equal(PulseBlockzCrypto.recover_address(Tx.signing_digest(tx), sig), ADDRESS,
		"and recovers to the address that made it")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
