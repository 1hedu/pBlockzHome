# The engine loads the pet meshes.
#
#   godot --headless --path . -s res://tests/mesh_test.gd
#
# A mesh that fails to load does so silently: the MeshPart stays a MeshPart but draws a plain
# block, so this checks its reported bounds and the engine's own Mesh warnings.
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var warnings: Array[String] = []
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok:
		passed += 1
		print("  PASS ", what)
	else:
		failed += 1
		printerr("  FAIL ", what)

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	world.script_warn.connect(func(n, t): warnings.append("%s: %s" % [n, t]))
	world.script_print.connect(func(n, t): said.append(t))
	print("== pet meshes")
	_run()

## The prepared files, put where the host's cache puts them and named as _cache_media names
## them: the extension is what picks the loader.
func _stage() -> Dictionary:
	var src := "../../../scripts/models/"
	var here := ProjectSettings.globalize_path("res://").path_join(src)
	var out := {}
	DirAccess.make_dir_recursive_absolute("user://media")
	for f in ["steven-face.obj", "steven-skull.obj", "wing-bodyL.obj", "wing-bodyR.obj", "wing-rimL.obj", "wing-rimR.obj", "pup-dark2.obj", "steven-face.png"]:
		var bytes := FileAccess.get_file_as_bytes(here.path_join(f))
		if bytes.is_empty():
			continue
		var path := "user://media/test-%s" % f
		var w := FileAccess.open(path, FileAccess.WRITE)
		if w:
			w.store_buffer(bytes)
			w.close()
			out[f] = path
	return out

func _run() -> void:
	await create_timer(1.0).timeout
	var files := _stage()
	check(files.size() == 8, "all eight prepared files staged (%d)" % files.size())
	if files.size() < 8:
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return

	# Each entry copies the catalogue's own shape for a pet MeshPart, TextureID included.
	world.add_model("Workspace", "MeshProbe", JSON.stringify({
		"className": "Model", "name": "MeshProbe",
		"children": [
			{"className": "MeshPart", "name": "Head", "properties": {
				"Position": [0, 5, 0], "Size": [0.92, 1.24, 0.66],
				"MeshId": files["steven-face.obj"], "TextureID": files["steven-face.png"],
				"Anchored": true, "CanCollide": false}},
			{"className": "MeshPart", "name": "Skull", "properties": {
				"Position": [0, 5, 2], "Size": [0.92, 1.24, 0.66],
				"MeshId": files["steven-skull.obj"], "Anchored": true, "CanCollide": false}},
			{"className": "MeshPart", "name": "Wing", "properties": {
				"Position": [2, 5, 0], "Size": [0.78, 0.48, 0.05],
				"MeshId": files["wing-bodyL.obj"], "Anchored": true, "CanCollide": false}},
			{"className": "MeshPart", "name": "Rim", "properties": {
				"Position": [2, 5, 2], "Size": [1.83, 0.78, 0.02],
				"MeshId": files["wing-rimR.obj"], "Anchored": true, "CanCollide": false}},
			{"className": "MeshPart", "name": "Pup", "properties": {
				"Position": [4, 5, 0], "Size": [1.15, 1.05, 1.65],
				"MeshId": files["pup-dark2.obj"], "Anchored": true, "CanCollide": false}},
		],
	}))
	await create_timer(1.5).timeout

	# MeshSize comes back from the parsed file: zero means the fallback block.
	world.run_chunk("meshes", """
local probe = workspace:FindFirstChild("MeshProbe")
if not probe then print("MESH no probe") return end
for _, name in ipairs({"Head", "Skull", "Wing", "Rim", "Pup"}) do
    local p = probe:FindFirstChild(name)
    if not p then print("MESH " .. name .. " missing")
    else
        local s = p.MeshSize
        print(("MESH %s class=%s size=%.3f,%.3f,%.3f"):format(name, p.ClassName, s.X, s.Y, s.Z))
    end
end
""")
	await create_timer(1.0).timeout

	var all := " ".join(said)
	for name in ["Head", "Skull", "Wing", "Rim", "Pup"]:
		check(all.contains("MESH %s class=MeshPart" % name), "%s stayed a MeshPart" % name)
	check(not all.contains("size=0.000,0.000,0.000"), "every mesh reports real bounds, so none fell back to a block")

	var complaints := []
	for w in warnings:
		if w.begins_with("Mesh:"):
			complaints.append(w)
	check(complaints.is_empty(), "the engine raised no mesh warnings")
	for c in complaints:
		printerr("      ", c)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed else 0)
