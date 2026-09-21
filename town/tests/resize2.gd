# Does writing Size after a GuiObject is built resize it?
#
#   godot --headless --path . -s res://tests/resize2.gd
#
# Prints Size and AbsoluteSize either side of the write. AbsoluteSize is the renderer's own
# answer, not the property read back. Wardrobe.client.luau sizes its panel once and for all on
# the claim that AbsoluteSize never moves after the build; no other test writes Size.
extends SceneTree
var world
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	_run()

func _run() -> void:
	for _i in 60:
		await process_frame
	world.run_client_chunk("build", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local s = Instance.new("ScreenGui")
s.Name = "ResizeMe"
s.Parent = gui
local f = Instance.new("Frame")
f.Name = "Box"
f.Position = UDim2.new(0, 20, 0, 20)
f.Size = UDim2.new(0, 200, 0, 100)
f.Parent = s
""")
	for _i in 20:
		await process_frame
	world.run_client_chunk("grow", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local f = gui:WaitForChild("ResizeMe"):WaitForChild("Box")
print(("SIZE before: property %s, absolute %s"):format(tostring(f.Size), tostring(f.AbsoluteSize)))
f.Size = UDim2.new(0, 400, 0, 300)
""")
	for _i in 30:
		await process_frame
	world.run_client_chunk("read", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local f = gui:WaitForChild("ResizeMe"):WaitForChild("Box")
print(("SIZE after:  property %s, absolute %s"):format(tostring(f.Size), tostring(f.AbsoluteSize)))
""")
	for _i in 20:
		await process_frame
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 60.0:
		quit(0)
	return false
