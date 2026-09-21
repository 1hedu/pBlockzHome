# Security properties this client depends on: no code in a worn asset, no script drawing
# over the wallet prompt, no wedging the request channel.
#
#   godot --headless --path . -s res://tests/security_test.gd
extends SceneTree

const COVER := """
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
local screen = Instance.new("ScreenGui")
screen.Name = "Overlay"
screen.DisplayOrder = 100000
screen.Parent = gui
local f = Instance.new("Frame")
f.Size = UDim2.new(1, 0, 1, 0)
f.Parent = screen
print("COVER made a ScreenGui with DisplayOrder " .. tostring(screen.DisplayOrder))
"""

var world: PulseBlockzWorld
var wallet: Node
var t := 0.0
var last_cover := -9.0
var phase := 0
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func trojan() -> Dictionary:
	return {
		"className": "Accessory", "name": "TrojanHat", "properties": {"Name": "TrojanHat"},
		"children": [
			{"className": "Part", "name": "Handle", "properties": {"Size": [1, 1, 1]},
			 "children": [{"className": "Attachment", "name": "HatAttachment", "properties": {"Position": [0, -0.5, 0]}}]},
			{"className": "Script", "name": "Innocuous",
			 "properties": {"Source": "print('PAYLOAD RAN')"}},
		],
	}

## The shape a tailor really publishes: the control that must stay allowed.
func honest() -> Dictionary:
	return {
		"className": "Accessory", "name": "Cape", "properties": {"Name": "Cape"},
		"children": [
			{"className": "Part", "name": "Handle",
			 "properties": {"Size": [1.9, 2.5, 0.08], "Material": "Fabric"},
			 "children": [
				{"className": "Attachment", "name": "BodyBackAttachment", "properties": {"Position": [0, 0.55, -0.14]}},
				{"className": "Decal", "name": "DecalBack", "properties": {"Face": "Back", "Texture": "pblockz://abc"}},
			 ]},
			{"className": "WeldConstraint", "name": "CollarWeld", "properties": {"Part0": "Handle", "Part1": "Collar"}},
		],
	}

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	# Title.gd's own CanvasLayer sits at 200, above the host band the layer check below allows;
	# it is no hole because Main.gd holds the intro until Start, so nothing joins while it is up.
	main.show_title = false
	world = main.get_node("World")
	wallet = main.get_node("Wallet")
	wallet.auto_start = false
	root.add_child(main)
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(n, txt):
		said.append(txt)
		print("    [%s] %s" % [n, txt]))
	print("== security")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 1.5:
		phase = 1

		# ---- an asset must not be able to be a program -------------------------------
		# The engine loads a model with a Script in it by design -- that is how a Rojo
		# project ships code -- so the guard sits on the asset path, in Wallet.gd.
		var bad: Array = wallet._forbidden_classes(trojan())
		check(bad.has("Script"), "a model carrying a Script is refused by name")
		check(bad.has("a Source"), "and by carrying a Source at all, whatever it calls itself")
		check(wallet._forbidden_classes(honest()).is_empty(), "an honest cape is still allowed through")

		# The list is an allowlist of what a wearable needs, not a roster of known dangers.
		var sneaky := {"className": "Accessory", "children": [{"className": "RemoteEvent", "name": "phone"}]}
		check(wallet._forbidden_classes(sneaky).has("RemoteEvent"), "and so is anything not on the allowlist")

		# ---- a worn asset must not be able to shout at the square ---------------------
		# A BillboardGui on an accessory floats over the wearer's head. Keepsakes minted
		# with one are on the chain for good, so it is pruned at wear time, not refused.
		var shouty := {"className": "Accessory", "children": [
			{"className": "Part", "name": "Handle", "children": [
				{"className": "BillboardGui", "name": "Label", "children": [
					{"className": "TextLabel", "name": "Text"}]},
				{"className": "Attachment", "name": "LeftGripAttachment"}]}]}
		check(wallet._forbidden_classes(shouty).is_empty(), "a label is not grounds to refuse a whole model")
		wallet._strip_labels(shouty)
		var still := JSON.stringify(shouty)
		check(not still.contains("BillboardGui"), "but it is taken off before the thing is worn")
		check(still.contains("LeftGripAttachment"), "and the rest of the model is left alone")

		# ---- the request channel must not be wedgeable -------------------------------
		# Sequence numbers are remembered, not ordered: no single number closes the channel.
		wallet._handled.clear()
		wallet._handled.append(2147483647)
		check(not wallet._handled.has(7), "a huge sequence number does not swallow the ones after it")

		# ---- a script must not be able to draw over the wallet prompt -----------------
		# (the overlay itself is made in phase 1, once there is a client to make it on)
	# Gated on the script's own print, not the clock: the chunk waits on PlayerGui, so a fixed
	# delay reads the layers with no overlay there yet. Then 1s for layout; 40s to give up.
	elif phase == 1 and (said.any(func(x): return x.contains("COVER made")) or t > 40.0):
		phase = 15
		t = 0.0
	elif phase == 1 and t - last_cover > 1.0:
		# run_client_chunk drops a chunk silently while there is no client, so it is resent
		# until a print says it ran.
		last_cover = t
		world.run_client_chunk("cover", COVER)
	elif phase == 15 and t > 1.0:
		phase = 2
		# 100 is the host's band -- core GUI and the wallet's confirmation. Unclamped, a
		# DisplayOrder of 100000 would put that Frame on layer 100001, over a signing prompt.
		var highest := -1
		var above := 0
		for node in _all_canvas_layers(root):
			highest = max(highest, node.layer)
			if node.layer > 100:
				above += 1
		check(above == 0, "nothing drawn by a script sits above the host's layer")
		check(highest <= 100, "and the highest layer in the tree is the host's own (%d)" % highest)
		check(said.any(func(s): return s.contains("COVER made")), "even though the script asked for 100000")

		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed else 0)
	return false

func _all_canvas_layers(node: Node, out: Array = []) -> Array:
	if node is CanvasLayer:
		out.append(node)
	for child in node.get_children():
		_all_canvas_layers(child, out)
	return out
