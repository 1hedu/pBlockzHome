# PulseBlockz Town: a square, a fountain, and a bank with a teller at the counter.
# Nothing binds E: ContextActionService actions are offered a key before
# ProximityPrompts are, so a binding here would take E from the teller's prompt.
extends Node3D

@onready var world: PulseBlockzWorld = $World

## Ask before running a fetched place. Off only for headless tests, as Wallet.confirm_purchases is.
@export var confirm_place := true

## Put the title card up and wait for Start. Off for tests, which have nobody to press it.
@export var show_title := true

## Splash card for a game run off this project's own files. A published game names its own in
## its manifest (publish-experience.js --splash), and _mount_place puts that up as soon as the
## manifest has been read, before any script is fetched.
const SPLASH := "res://splash.png"

func _publish_splash(from_file: String = SPLASH) -> void:
	# Out to user://: every other asset reaches the world as a cache path, and a packaged build
	# has no res:// file an image loader can open. Rewritten each run, never reused.
	var into := "user://splash.png"
	if from_file.begins_with("res://"):
		var bytes := FileAccess.get_file_as_bytes(from_file)
		if bytes.is_empty() or bytes.slice(0, 4).get_string_from_ascii() == "GST2":
			# "GST2" is the imported .ctex magic: an exported build remaps res://splash.png to the
			# texture Godot made, so the picture has to come back out of that.
			var tex = load(from_file) if ResourceLoader.exists(from_file) else null
			var img: Image = tex.get_image() if tex is Texture2D else null
			if img != null:
				img.save_png(into)
				bytes = PackedByteArray()
			else:
				printerr("[town] no splash card at %s" % from_file)
				return
		if not bytes.is_empty():
			var w := FileAccess.open(into, FileAccess.WRITE)
			if not w:
				printerr("[town] could not write %s" % into)
				return
			w.store_buffer(bytes)
			w.close()
	else:
		into = from_file
	# mode 1 is a server: no screen of its own, and it names this card for its joining clients,
	# so only a chain uri will do -- a local path replicates as a filename nobody else can open.
	if world != null and int(world.mode) == 1 and not into.begins_with("pblockz://"):
		return
	# ReplicatedFirst, where Roblox keeps a loading screen's assets: this machine's own card,
	# up before anything of the server's has arrived. Not a PlaceAssets folder made here -- on a
	# joined client that one sits beside the server's replicated ReplicatedStorage.PlaceAssets,
	# is the one every WaitForChild("PlaceAssets") finds, and holds nothing but the splash.
	world.run_chunk("splash", """
local first = game:GetService("ReplicatedFirst")
local v = first:FindFirstChild("SplashImage")
if not v then
	v = Instance.new("StringValue")
	v.Name = "SplashImage"
	v.Parent = first
end
v.Value = %s
""" % preload("res://host/Luau.gd").quote(into))

## Set the flag the intro waits on. The intro is a client script and starts the moment the place
## loads; holding it rather than the world lets the chain read, assets and map arrive behind it.
func _hold_intro(held: bool) -> void:
	world.run_chunk("title", """
local rs = game:GetService("ReplicatedStorage")
local node = rs:FindFirstChild("Title")
if not node then
	node = Instance.new("Configuration")
	node.Name = "Title"
	node.Parent = rs
end
node:SetAttribute("Waiting", %s)
""" % ("true" if held else "false"))

## Which place to run, if not the one on disk.
##
##   godot --path . -- --place pblockz://<hash>?chain=943:0x...:N
##
## Without it the scripts under res://scripts run. With it the place is fetched by content
## hash, every file checked against its own hash before it is loaded, and nothing runs until
## the whole set has arrived.
func _place_uri() -> String:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--place" and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("--place="):
			return args[i].substr("--place=".length())
	return ""

## Fetch and mount a published place, behind the intro's blackout. The "run this?" screen is
## Experience.gd's, drawn from the host before the first script exists: a screen asking whether
## you trust some code cannot be drawn by that code.
func _mount_place(uri: String) -> void:
	# In time, but only just: ScriptSync's _ready has run, but it defers _start, so the disk
	# load has not. world.http_enabled has no such gap -- the world builds its runtime in
	# _ready proper, so that one is set in Main.tscn.
	var sync := $ScriptSync
	sync.load_from_disk = false
	var experience = preload("res://host/Experience.gd").new()
	experience.name = "Experience"
	experience.sync_path = ^"../ScriptSync"
	experience.confirm = confirm_place
	add_child(experience)
	# The manifest before the mount: the card covers the fetch, so it has to go up first.
	var info: Dictionary = await experience.preview(uri)
	# By uri: the engine fetches a pblockz:// where it draws it, so no download blocks the card.
	if info.get("ok", false) and String(info.get("splash", "")) != "":
		_publish_splash(String(info.splash))
	var got: Dictionary = await experience.mount(uri)
	if not got.get("ok", false):
		# An empty world, and the hold released: the intro must not wait on a place that will
		# never arrive.
		push_error("[place] %s: %s" % [uri, got.get("error", "could not be loaded")])
		_hold_intro(false)
		return
	print("[place] running %s (%d files) from %s" % [got.get("name", "?"), got.get("mounted", 0), uri])
	# Roblox counts PlaceVersion from 1, one up per publish. No such counter here: the version
	# is the moment the place went on chain -- monotonic, checkable against the transaction,
	# and the same for everybody running the same bytes.
	if world != null and int(got.get("published", 0)) > 0:
		world.set_property(0, "PlaceVersion", int(got.get("published", 0)))

## SAFETY.md §1: no network from a player's machine, and a place fetched by hash is somebody
## else's code. In Play Solo its server half runs here, so HttpService goes off before the world
## builds its runtime. A server (mode 1, Serve.gd) is the operator's box and keeps the setting.
func _enter_tree() -> void:
	var w := get_node_or_null("World")
	if w != null and _place_uri() != "" and int(w.mode) != 1:
		w.http_enabled = false
	# Luau heap ceiling for a place's scripts, in megabytes. The town peaks at 4.98 MiB, so 64
	# is about twelve times a rich place; the engine's own default is no cap at all. No mode
	# check, unlike http_enabled above: a server running somebody else's place by --place runs
	# the same untrusted code a player's machine does.
	#
	# In _enter_tree, not _ready: the world builds its runtime in its own _ready, a child's
	# _ready runs before its parent's, and a budget set after that is read by nothing.
	if w != null:
		w.max_memory_mb = 64

func _ready() -> void:
	# From the chain, the card is the game's and _mount_place puts it up instead.
	if _place_uri() == "":
		_publish_splash()
	# Held only while there is a card to get past: a hold with no Start button on screen is a
	# town that never begins.
	_hold_intro(show_title)
	if show_title:
		var title := preload("res://host/Title.gd").new()
		title.name = "Title"
		title.chosen.connect(func(): _hold_intro(false))
		add_child(title)
	# A ceiling on the master bus: voices summing in the mixer clip past full scale. The Player
	# sets the same one, so a place sounds the same whichever of the two opens it.
	add_child(preload("res://host/Audio.gd").new())
	# Its own node: a public API read, no key and nothing signed, so it is not the wallet's
	# business and does not queue behind a purchase.
	var scan := preload("res://host/Scan.gd").new()
	scan.name = "Scan"
	add_child(scan)
	# The market, on the same terms. This client reaches three sites -- the explorer, DexScreener
	# and PulseX -- and no verb takes a URL: a place names a search, the client owns the source.
	var market := preload("res://host/Market.gd").new()
	market.name = "Market"
	add_child(market)
	# HttpService is turned on in Main.tscn, on the World node, for the ordering reason in
	# _enter_tree; set here it is a frame late and does nothing. Serve.gd works under the same
	# constraint: it assigns world.mode on the instanced scene before adding it to the tree.
	# ServerScriptService.Ranks -- a Luau script shipping with the place, not with this client
	# -- reads the five tokens through it, under Roblox's rules: the server only, and only when
	# the operator says so.
	var place := _place_uri()
	if place != "":
		# Replicated to joining clients as a pointer, not as code: the server sends no source, so
		# they fetch the place from the chain and check it file by file. A server running
		# unpublished scripts names nothing here, and its clients run none of them.
		world.place_uri = place
		_mount_place(place)

	world.script_print.connect(func(n, t): print("[%s] %s" % [n, t]))
	world.script_warn.connect(func(n, t): push_warning("[%s] %s" % [n, t]))
	world.script_error.connect(func(n, e): push_error("[%s] %s" % [n, e]))
	world.leave_game.connect(func(): get_tree().quit())
	# The wallet's half only; Chain.server.luau prints what the town makes of it.
	$Wallet.published.connect(func(d):
		print("[town] wallet: %s, %s PLS, %d token(s)" % [d.address, d.gas, d.tokens.size()]))
