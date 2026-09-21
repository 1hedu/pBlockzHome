# Worst frame while the town's biggest meshes are decomposed for collision, per CollisionFidelity.
#
#   godot --headless --path . -s res://tests/decompose_time_probe.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var worst := 0.0
var fidelities := ["Default", "PreciseConvexDecomposition", "Hull"]
var index := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 1: worst = max(worst, delta)
	if phase == 0 and t > 3.0:
		phase = 1; t = 0.0; worst = 0.0
		world.run_chunk("probe", """
local AssetService = game:GetService("AssetService")
for i, file in ipairs({ "tree-canopy.obj", "tree-trunk.obj", "rocket.obj" }) do
	local p = AssetService:CreateMeshPartAsync(Content.fromUri("res://../../../scripts/models/" .. file), { CollisionFidelity = Enum.CollisionFidelity.%s })
	p.Anchored = true
	p.Size = p.Size * 4
	p.CFrame = CFrame.new(i * 80, 300, 0)
	p.Parent = workspace
end
""" % fidelities[index])
	elif phase == 1 and t > 6.0:
		print("PROBE %s worst frame %.0f ms" % [fidelities[index], worst * 1000])
		index += 1
		if index >= fidelities.size():
			quit(0)
		else:
			phase = 0; t = 0.0
	return false
