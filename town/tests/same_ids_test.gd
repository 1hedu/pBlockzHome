# Two worlds given the same place make the same instances at the same ids.
#
#   godot --headless --path . -s res://tests/same_ids_test.gd
#
# A client mounts the published place itself and takes only live state from the server, so the
# server's "part 412 moved" has to land on the instance the client also calls 412.
extends SceneTree

var ok := 0
var bad := 0

func check(what: String, got, want) -> void:
	if got == want:
		ok += 1
	else:
		bad += 1
	print("IDS %-56s %-14s (wanted %s)%s" % [what, str(got), str(want), "" if got == want else "   <-- WRONG"])

## A world with the files mounted the way a place is: one batch, in one fixed order.
## host/Experience.gd sorts the names before it loads them, and that sort is what has the two
## sides walk the files alike and hand out the same ids.
func _world_with(files: Array) -> PulseBlockzWorld:
	var w := PulseBlockzWorld.new()
	w.mode = PulseBlockzWorld.MODE_PLAY_SOLO
	w.auto_join = false
	w.data_store_path = ""
	root.add_child(w)
	for f in files:
		w.load_file(f[0], f[1])
	return w

## The id at a tree path, walked the way host/Wallet.gd walks one.
func _at(w: PulseBlockzWorld, path: String) -> int:
	var id := 0
	for want in path.split("/"):
		var found := 0
		for cid in w.get_child_ids(id):
			if String((w.get_instance(cid) as Dictionary).get("name", "")) == want:
				found = cid
				break
		if found == 0:
			return 0
		id = found
	return id

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var dir := "res://scripts/src"
	var files := []
	for rel in ["shared/Pictures.luau", "shared/Mixer.luau", "shared/Carry.luau",
			"shared/ModelPicture.luau", "shared/HeartRow.luau"]:
		var at := dir.path_join(rel)
		if FileAccess.file_exists(at):
			files.append(["ReplicatedStorage/" + rel.get_file(), FileAccess.get_file_as_string(at)])
	check("the town has files to load", files.size() > 0, true)
	if files.is_empty():
		quit(1)
		return

	var a := _world_with(files)
	var b := _world_with(files)
	# load_file queues onto the runtime's own thread; a frame or two later the tree is still empty.
	await create_timer(4.0).timeout

	var same := 0
	var seen := 0
	for f in files:
		var name: String = String(f[0]).get_file().get_basename()
		var ia: int = _at(a, "ReplicatedStorage/" + name)
		var ib: int = _at(b, "ReplicatedStorage/" + name)
		if ia != 0 and ib != 0:
			seen += 1
			if ia == ib:
				same += 1
			else:
				print("IDS   %s is %d in one world and %d in the other" % [name, ia, ib])
	check("every file landed in both worlds", seen, files.size())
	check("and at the same id in each", same, seen)

	# Terrain gets a fixed id from the loader, so a client makes the same one for itself.
	var ta: int = _at(a, "Workspace/Terrain")
	var tb: int = _at(b, "Workspace/Terrain")
	check("Terrain is at the same id in both", ta == tb and ta != 0, true)

	print("IDS %d passed, %d failed" % [ok, bad])
	print("same ids: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
