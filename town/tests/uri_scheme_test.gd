# The asset uri scheme, read and written -- one spelling, pblockz://.
#
#   godot --headless --path . -s res://tests/uri_scheme_test.gd
#
# Everything on chain is stored in that spelling, so the parser refuses any other rather than
# carrying a reader for it.
extends SceneTree

const HASH := "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12"
const STORE := "0x0f9D08e13BE2345856026615d05F7251F07efAfA"
# Split in two, like the engine's own copy, so a rename sweep cannot rewrite it.
const LEGACY := "pb" + "lox://"

var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("URI %-54s %-14s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	var query := "?chain=943:%s:1061&mime=application%%2Fjson" % STORE

	var now: Dictionary = PulseBlockzChain.parse_asset_uri("pblockz://" + HASH + query)
	check("the scheme parses", String(now.get("content_hash", "")), "0x" + HASH)
	check("with the blob it names", int(now.get("blob_id", 0)), 1061)
	check("and the store it is in", String(now.get("store", "")).to_lower(), STORE.to_lower())

	var written: String = PulseBlockzChain.format_asset_uri(now)
	check("what it writes is the same scheme", written.begins_with("pblockz://"), true)

	check("the spelling it used to have is refused",
		String(PulseBlockzChain.parse_asset_uri(LEGACY + HASH + query).get("content_hash", "")), "")
	check("and so is a scheme that was never ours",
		String(PulseBlockzChain.parse_asset_uri("pblockzz://" + HASH).get("content_hash", "")), "")

	print("URI %d passed, %d failed" % [ok, bad])
	print("uri scheme: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
