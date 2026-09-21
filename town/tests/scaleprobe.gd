# Does asking for a bigger panel actually make one?
#
#   godot --headless --path . -s res://tests/scaleprobe.gd
#
# Prints all four links in the chain: the camera's ViewportSize, the scale Theme works out of
# it, the UIScale instance under each ScreenGui, and the CanvasLayer transform the host sets.
extends SceneTree
var world
var t := 0.0
var done := false

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	root.add_child(main)
	_run(main)

func _layers(n: Node, out: Array) -> void:
	if n is CanvasLayer:
		out.append(n)
	for k in n.get_children():
		_layers(k, out)

func _report(tag: String) -> void:
	var found: Array = []
	_layers(world, found)
	for l in found:
		if l.name in ["Explorer", "Screener", "Swap", "PulseX"]:
			var root_ctl = l.get_child(0) if l.get_child_count() > 0 else null
			print("  %-8s %-9s layer scale=%.3f  root size=%s"
				% [tag, l.name, l.get_transform().get_scale().x,
				   str(root_ctl.size) if root_ctl is Control else "?"])

func _run(main: Node) -> void:
	for _i in 60:
		await process_frame
	print("== ui scale")
	print("  viewport (godot) = %s" % [get_root().get_visible_rect().size])
	world.run_client_chunk("look", """
local cam = workspace.CurrentCamera
print(("CAM ViewportSize = %s"):format(cam and tostring(cam.ViewportSize) or "no camera"))
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
	local u = s:FindFirstChildOfClass("UIScale")
	if u then print(("UIS %s Scale=%.3f"):format(s.Name, u.Scale)) end
end
""")
	for _i in 20:
		await process_frame
	_report("before")

	world.run_client_chunk("bump", """
local Theme = require(game:GetService("ReplicatedStorage"):WaitForChild("Theme"))
print(("SET asked for 2x, got %.3f"):format(Theme.setUiScale(2)))
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
for _, s in ipairs(gui:GetChildren()) do
	local u = s:FindFirstChildOfClass("UIScale")
	if u then print(("UIS %s Scale=%.3f"):format(s.Name, u.Scale)) end
end
""")
	for _i in 30:
		await process_frame
	_report("after")
	done = true

func _process(delta: float) -> bool:
	t += delta
	if done or t > 60.0:
		quit(0)
	return false
