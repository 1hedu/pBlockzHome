# A click on an action bar square is a click on the square, and not also a swing.
#
#   node scripts/stage-preview.js crudespoon <stage dir>
#   godot --path . -s res://tests/bar_click_test.gd -- <stage dir>
#
# The bar is a HUD, so Weapons.client.luau's window check passes it over. What keeps the press
# from also swinging is gameProcessedEvent, which only a real click at a real pixel exercises.
extends SceneTree
const Verdict = preload("res://tests/Verdict.gd")
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0
var lines: Array[String] = []
var at := Vector2.ZERO
var lit := false                 # the intro has handed the screen over
var slot_at := Vector2.ZERO      # the middle of bar square 1, as the bar reports it

func _initialize() -> void:
	stage = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute("user://preview")
	var dir := DirAccess.open(stage)
	for f in (dir.get_files() if dir else PackedStringArray()):
		var w := FileAccess.open("user://preview/".path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(stage.path_join(f)))
			w.close()
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	# The title card is a ScreenGui over everything: while it is up windowOpen() in Weapons.client
	# is true and the spoon is disarmed. So no title, and nothing until the intro lets go.
	main.show_title = false
	world.script_print.connect(func(_n, line):
		var l := String(line)
		lines.append(l)
		if l.begins_with("intro:") and l.find("the engine ran") >= 0: lit = true
		if l.begins_with("SLOT "):
			var bits: PackedStringArray = l.substr(5).split(" ")
			if bits.size() == 4:
				slot_at = Vector2(float(bits[0]) + float(bits[2]) / 2, float(bits[1]) + float(bits[3]) / 2))
	root.add_child(main)

func click(p: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = p
		e.global_position = p
		get_root().push_input(e, true)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and lit and t > 2.0:
		phase = 1
		t = 0.0
		var raw := FileAccess.get_file_as_string(stage.path_join("crudespoon.json"))
		world.add_model("ReplicatedStorage", "crudespoon",
			raw.replace(stage.replace("\\", "/") + "/", "user://preview/"))
		world.run_chunk("count", """
local rs = game:GetService("ReplicatedStorage")
local n = Instance.new("IntValue")
n.Name = "SwingCount"
n.Value = 0
n.Parent = rs
rs:WaitForChild("WeaponRemote").OnServerEvent:Connect(function()
	n.Value += 1
end)
""")
		world.run_client_chunk("fill", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local bar = Players.LocalPlayer:WaitForChild("PlayerGui"):WaitForChild("ActionBar", 20)
-- The bar draws whatever the wardrobe last pushed, and in a world with no chain that is
-- nothing. Nothing is fine: the question is whether the press reaches the world through it,
-- and an empty square is still a control that sinks the pointer.
local slot = bar:WaitForChild("Row"):WaitForChild("Slot1")
local p, s = slot.AbsolutePosition, slot.AbsoluteSize
print(("SLOT %d %d %d %d"):format(p.X, p.Y, s.X, s.Y))
""")
	elif phase == 1 and t > 2.0:
		phase = 2
		t = 0.0
		# Where the bar reports square 1, not a position computed from the layout: that misses it.
		at = slot_at
		click(at)
	elif phase == 2 and t > 1.5:
		phase = 3
		t = 0.0
		world.run_chunk("look1", """
local rs = game:GetService("ReplicatedStorage")
print("BARCLICK swings after a press on a square: " .. tostring(rs.SwingCount.Value) .. " (wanted 0)")
""")
	elif phase == 3 and t > 1.5:
		phase = 4
		t = 0.0
		# The same press in the open must swing, or the check above passes on a dead spoon.
		world.run_chunk("arm", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local player = Players:GetPlayers()[1]
local spoon = rs:FindFirstChild("Spoonie")
if spoon then spoon:Clone().Parent = player.Character end
local held = {}
for _, d in ipairs(player.Character:GetChildren()) do table.insert(held, d.Name .. "/" .. d.ClassName) end
print("ARMED spoon=" .. tostring(spoon ~= nil) .. " holding: " .. table.concat(held, ", "))
""")
	elif phase == 4 and t > 1.5:
		phase = 5
		t = 0.0
		var view := get_root().get_visible_rect().size
		click(Vector2(view.x / 2, view.y * 0.35))
	elif phase == 5 and t > 2.0:
		phase = 6
		world.run_chunk("look2", """
local rs = game:GetService("ReplicatedStorage")
print("BARCLICK swings after a press on the world: " .. tostring(rs.SwingCount.Value) .. " (wanted 1)")
""")
	elif phase == 6 and t > 1.5:
		quit(Verdict.finish(lines, "BARCLICK"))
	return false
