# Does CFrame.new(from, to) stay level for every horizontal heading?
#
#   godot --path . -s res://tests/lookat_probe.gd
extends SceneTree
var world: PulseBlockzWorld
var t := 0.0
var phase := 0

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 4.0:
		phase = 1
		world.run_chunk("lookat", """
local worst, worstAt = 0, 0
for deg = 0, 355, 5 do
	local a = math.rad(deg)
	local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
	local cf = CFrame.new(Vector3.new(0, 0, 0), dir)
	-- Level means the right-hand axis is horizontal and up is up.
	local roll = math.deg(math.asin(math.clamp(cf.RightVector.Y, -1, 1)))
	local up = cf.UpVector.Y
	-- And the nose must actually point where it was asked to.
	local aim = cf.LookVector:Dot(dir)
	if math.abs(roll) > math.abs(worst) then worst, worstAt = roll, deg end
	if deg % 45 == 0 or math.abs(roll) > 0.01 or up < 0.999 or aim < 0.999 then
		print(("LOOKAT %3d deg -> roll %8.3f  up.y %7.4f  aims %7.4f"):format(deg, roll, up, aim))
	end
end
print(("LOOKAT worst roll %.3f deg at %d deg"):format(worst, worstAt))
""")
		t = 0.0
	elif phase == 1 and t > 2.0:
		quit(0)
	return false
