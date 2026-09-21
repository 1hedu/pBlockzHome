# The Engram: the town builds the badge in Luau and the client mounts it, and this is where the
# two are made to agree -- welds, grip attachment, allowed classes, and the mounter itself.
# Headless, so the look of it is never checked, only the structure a mount depends on.
#
#   godot --headless --path . -s res://tests/engram_test.gd
extends SceneTree

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the Engram")
	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	_run(main)

## Reads an attribute off whichever ReplicatedStorage.Chain carries it. Play Solo mirrors two nodes
## of that name, the server's and the client's wallet channel, and the first is not always the one set.
func _probe(w, attr: String) -> String:
	var rs: int = w._find_instance("ReplicatedStorage")
	if rs == 0: return ""
	for cid in w.world.get_child_ids(rs):
		if String((w.world.get_instance(cid) as Dictionary).get("name", "")) != "Chain": continue
		var got := String((w.world.get_attributes(cid) as Dictionary).get(attr, ""))
		if got != "": return got
	return ""

func _run(main: Node) -> void:
	var w = main.get_node("Wallet")
	var waited := 0.0
	var raw := ""
	while waited < 40.0 and raw == "":
		await create_timer(1.0).timeout
		waited += 1.0
		if w.world == null:
			continue
		w.world.run_chunk("engram_probe", """
local rs = game:GetService("ReplicatedStorage")
local http = game:GetService("HttpService")
local Engram = require(rs:WaitForChild("Engram"))
local c = rs:FindFirstChild("Chain")
if not c then c = Instance.new("Configuration") c.Name = "Chain" c.Parent = rs end
c:SetAttribute("EngramProbe", http:JSONEncode(Engram.model("Engram 25323800")))
c:SetAttribute("EngramLookProbe", http:JSONEncode(Engram.model("Engram 25323800",
	{ mesh = "user://preview/engram-badge.obj", texture = "user://preview/pulse-gradient.png" })))
""")
		raw = _probe(w, "EngramProbe")

	check(raw != "", "the town builds one")
	if raw == "":
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	var model = JSON.parse_string(raw)
	check(typeof(model) == TYPE_DICTIONARY and String(model.get("className", "")) == "Accessory",
		"as an Accessory, which is what the body knows how to wear")
	check(String((model.get("properties", {}) as Dictionary).get("Name", "")) == "Engram 25323800",
		"named for the block it remembers, so two in a bag are not the same thing twice")

	var children: Array = model.get("children", [])
	var parts := {}
	var welds := {}
	var handle = null
	for c in children:
		var cls := String(c.get("className", ""))
		if cls == "Part":
			parts[String(c.get("name", ""))] = c
			if String(c.get("name", "")) == "Handle": handle = c
		elif cls == "WeldConstraint":
			welds[String((c.get("properties", {}) as Dictionary).get("Part1", ""))] = c

	check(parts.size() == 12, "twelve parts: the band, four points and the heartbeat (%d)" % parts.size())
	check(handle != null, "one of them the Handle, which is what the hand actually holds")

	# Roblox welds only the Handle to the body; an unwelded part stays behind when he walks off.
	var unwelded := []
	for name in parts:
		if name != "Handle" and not welds.has(name):
			unwelded.append(name)
	check(unwelded.is_empty(), "and every other part welded to it" if unwelded.is_empty()
		else "unwelded: " + ", ".join(unwelded))
	check(not welds.has("Handle"), "the Handle is not welded to itself")

	# The Attachment's name is what decides the limb: the client reads the slot off it.
	var attachments := []
	for c in (handle.get("children", []) as Array):
		if String(c.get("className", "")) == "Attachment":
			attachments.append(String(c.get("name", "")))
	check(attachments == ["LeftGripAttachment"], "hung from the left grip, and from nothing else")
	check(String(w._slot_of(model)) == "offhand",
		"which the client reads back as the off hand, without being told")

	var glass := 0
	var neon := 0
	for name in parts:
		var props: Dictionary = parts[name].get("properties", {})
		if String(props.get("Material", "")) == "Glass" and float(props.get("Transparency", 0)) > 0.3:
			glass += 1
		if String(props.get("Material", "")) == "Neon":
			neon += 1
	check(glass == 5, "the badge itself is glass you can see through: %d part(s)" % glass)
	check(neon == 7, "and the heartbeat is neon, so it carries in the dark: %d segment(s)" % neon)

	# A mounted model is data: no class that can carry code, the town's own model included.
	var forbidden: Array = w._forbidden_classes(model)
	check(forbidden.is_empty(), "nothing in it the client would refuse to mount"
		if forbidden.is_empty() else "refused: " + ", ".join(forbidden))

	# The name inside the model wins over the one passed to add_model: _mount_model reads it back.
	if w.world != null:
		w.world.add_model("ReplicatedStorage/OnChain", "EngramProbeModel", raw)
		# add_model lands through the change log, not immediately.
		await create_timer(0.5).timeout
		check(w._find_instance("ReplicatedStorage/OnChain/Engram 25323800") != 0,
			"and the client mounts it, under the name the model gives itself")

	_check_look(w)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

## Given the place's mesh and texture, band and points collapse into one hexagon Handle wearing
## the PulseBlockz gradient.
func _check_look(w) -> void:
	var raw := _probe(w, "EngramLookProbe")
	var model = JSON.parse_string(raw) if raw != "" else null
	check(typeof(model) == TYPE_DICTIONARY, "with the place's pictures, it still builds")
	if typeof(model) != TYPE_DICTIONARY: return
	var parts := {}
	var welds := {}
	for c in (model.get("children", []) as Array):
		if String(c.get("className", "")) == "Part": parts[String(c.get("name", ""))] = c
		elif String(c.get("className", "")) == "WeldConstraint": welds[String((c.get("properties", {}) as Dictionary).get("Part1", ""))] = c
	check(parts.size() == 8, "one badge and the seven beats: the hexagon is one part now (%d)" % parts.size())
	var handle = parts.get("Handle")
	var mesh = null
	var grip := false
	for c in ((handle.get("children", []) if handle else []) as Array):
		if String(c.get("className", "")) == "SpecialMesh": mesh = c.get("properties", {})
		if String(c.get("className", "")) == "Attachment" and String(c.get("name", "")) == "LeftGripAttachment": grip = true
	check(mesh != null and String(mesh.get("MeshType", "")) == "FileMesh" and String(mesh.get("MeshId", "")).ends_with("engram-badge.obj")
		and String(mesh.get("TextureId", "")).ends_with("pulse-gradient.png"),
		"the Handle wears the hexagon, painted with the PulseBlockz gradient: %s" % str(mesh))
	var hp: Dictionary = handle.get("properties", {}) if handle else {}
	check(String(hp.get("Material", "")) == "Glass" and float(hp.get("Transparency", 0)) > 0.3 and grip,
		"still glass you can see through, still hung from the left grip")
	var unwelded := []
	for name in parts:
		if name != "Handle" and not welds.has(name): unwelded.append(name)
	check(unwelded.is_empty(), "and the heartbeat still welded to it")
	check((w._forbidden_classes(model) as Array).is_empty(), "nothing in it the client would refuse to mount: %s" % str(w._forbidden_classes(model)))
