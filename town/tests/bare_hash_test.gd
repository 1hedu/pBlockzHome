# A link that names only its content still fetches.
#
#   godot --headless --path . -s res://tests/bare_hash_test.gd
#
# pblockz://<hash> with nothing after it names WHAT the bytes are, not which chain or store
# holds them, so a document that stores one needs no rewriting when a store changes. Supplying
# the where is the client's job: the same bytes come back by full link and by content alone.
extends SceneTree

var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("BARE %-52s %-12s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var assets := root.get_node_or_null("ChainAssets")
	if assets == null:
		print("BARE no ChainAssets autoload")
		print("bare hash: FAIL")
		quit(1)
		return
	var Wallet = preload("res://host/Wallet.gd")
	assets.rpc_url = "https://rpc.v4.testnet.pulsechain.com"
	assets.chain_id = int(Wallet.ADDRESSES.chain_id)
	assets.asset_store = String(Wallet.ADDRESSES.AssetStore)

	# Something already on chain, named the long way, out of the place's own manifest.
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://place-assets.json"))
	var full := ""
	for name in (manifest as Dictionary).keys():
		var v := String(manifest[name])
		if v.begins_with("pblockz://") and v.contains("chain="):
			full = v
			break
	check("the place names something on chain", full != "", true)
	if full == "":
		quit(1)
		return

	var whole: PackedByteArray = await assets.fetch(full)
	check("it fetches by the long link", whole.size() > 0, true)

	# The cache is keyed by hash, so the cached copy goes first: otherwise the store is never
	# asked and the fetch proves nothing.
	var hash := String(PulseBlockzChain.parse_asset_uri(full).content_hash).trim_prefix("0x")
	var cached: String = String(assets.cache_dir).path_join(hash)
	if FileAccess.file_exists(cached):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cached))
	var bare: PackedByteArray = await assets.fetch("pblockz://" + hash)
	check("and by content alone", bare.size() > 0, true)
	check("the same bytes either way", bare == whole, true)
	var found: Dictionary = assets._located.get("0x" + hash, {})
	check("which the store was asked for", int(found.get("blob", 0)) > 0, true)
	check("and told what kind of thing it is", String(found.get("mime", "")) != "", true)

	var nowhere: PackedByteArray = await assets.fetch("pblockz://" + "ab".repeat(32))
	check("content no store has comes back empty", nowhere.size(), 0)

	# Godot picks its loader from the extension, so a bare link whose mime went unread would be
	# filed as .png by the fallback, and a font or a mesh under that name fails silently.
	var other := ""
	for name in (manifest as Dictionary).keys():
		var v := String(manifest[name])
		if v.begins_with("pblockz://") and v.contains("mime=") and not v.contains("image"):
			other = v
			break
	if other != "":
		var its_hash := String(PulseBlockzChain.parse_asset_uri(other).content_hash).trim_prefix("0x")
		var said: String = String(PulseBlockzChain.parse_asset_uri(other).get("mime", ""))
		var kind_back: String = await assets.mime_of("pblockz://" + its_hash)
		check("content alone still says what kind it is (%s)" % said, kind_back, said)
	check("the place has something that is not an image to ask about", other != "", true)

	# A document field is a hash alone, so the seams that hand it on put the scheme back.
	const Experience = preload("res://host/Experience.gd")
	check("a hash a manifest named becomes a link",
		Experience._asset("0x" + hash), "pblockz://" + hash)
	check("a link a manifest named is left alone",
		Experience._asset(full), full)
	check("and nothing named is still nothing", Experience._asset(""), "")
	check("32 bytes of hex is content", Wallet.is_content_hash("0x" + hash), true)
	check("a whole link is not", Wallet.is_content_hash(full), false)
	check("nor is something merely hex-shaped", Wallet.is_content_hash("0xdeadbeef"), false)

	print("BARE %d passed, %d failed" % [ok, bad])
	print("bare hash: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
