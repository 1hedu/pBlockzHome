# The title screen: three doors on the picture, the town held until one is pressed, and the
# two Connect paths driven through the wallet.
#
#   godot --path . -s res://tests/title_test.gd -- <shots dir>
extends SceneTree
var main: Node
var title: Node
var wallet: Node
var world: PulseBlockzWorld
var shots := ""
var t := 0.0
var phase := 0
var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("TITLE %-46s %-8s (wanted %s)%s" % [what, str(got), str(want),
		"" if got == want else "   <-- WRONG"])

func _initialize() -> void:
	shots = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(shots)
	# A key or address left by an earlier run would make this pass without doing anything.
	for f in ["user://player.key", "user://watch.address"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	main = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	wallet.auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 5.0:
		phase = 1
		t = 0.0
		title = main.get_node_or_null("Title")
		check("the title screen is up", title != null, true)
		if title != null:
			var row: Control = title.get_child(2)
			check("three doors", row.get_child_count(), 3)
			var art: Rect2 = title._art_rect()
			var start: Button = row.get_child(0)
			check("and they sit on the picture",
				art.has_point(start.position + start.size / 2.0), true)
		check("an address is taken", wallet.watch_address("0xc571203f199e002c0ea3233198ea683e5f5cab7c"), true)
		check("and it cannot sign", wallet.can_buy(), false)
		check("a short one is refused", wallet.watch_address("0x1234"), false)
		# Nothing real is typed anywhere in this file: 32 zero bytes is not a key on this curve.
		check("rubbish is not a key", wallet.adopt_key("0x" + "00".repeat(32)), false)
	elif phase == 1 and t > 1.0:
		phase = 2
		t = 0.0
		world.run_client_chunk("waiting", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local node = rs:FindFirstChild("Title")
print("TITLEWAIT the town is told to wait: " .. tostring(node ~= nil and node:GetAttribute("Waiting") == true))
-- Not merely that it has not finished: that it has not BEGUN. The card is hidden until the
-- first beat, so a visible one means the arrival is playing behind a title screen nobody has
-- pressed -- and pressing Start would then drop you into the town with no intro at all.
local intro = gui:FindFirstChild("Intro")
local card = intro and intro:FindFirstChild("Card")
print("TITLEWAIT and the intro has not started: "
	.. tostring(intro ~= nil and card ~= nil and not card.Visible))
""")
	elif phase == 2 and t > 2.0:
		phase = 3
		t = 0.0
		get_root().get_texture().get_image().save_png(shots.path_join("title.png"))
		print("  -> title.png")
		# _new_wallet is the only path that writes user://player.key.
		if title != null:
			title._new_wallet()
		check("a made key is kept", FileAccess.file_exists("user://player.key"), true)
		var made := FileAccess.get_file_as_string("user://player.key").strip_edges()
		check("and it is a key this curve accepts",
			PulseBlockzCrypto.address_from_key(made) != "", true)
		check("which is now the account we sign for",
			wallet.wallet_address == PulseBlockzCrypto.address_from_key(made), true)
		check("so signing is on", wallet.can_buy(), true)
		var was: String = wallet.wallet_address
		title._new_wallet()
		check("and making a second one is refused", wallet.wallet_address, was)
		if title != null:
			title._start()
	elif phase == 3 and t > 2.0:
		phase = 4
		t = 0.0
		world.run_client_chunk("released", """
local rs = game:GetService("ReplicatedStorage")
local node = rs:FindFirstChild("Title")
print("TITLEWAIT pressing a door lets the town go: " .. tostring(node ~= nil and node:GetAttribute("Waiting") == false))
""")
	elif phase == 4 and t > 2.0:
		for f in ["user://player.key", "user://watch.address"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		print("TITLE done: %d right, %d wrong" % [ok, bad])
		quit(0)
	return false
