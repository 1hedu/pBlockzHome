# Screenshots the health meter in each of its states; the arithmetic behind them is
# combat_test.gd's job.
#
#   godot --path . -s res://tests/hearts_look.gd -- <stage dir> <shots dir>
#
# HeartsRemote is fired directly, so reaching a state does not mean arranging a kill.
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var shots := ""
var t := 0.0
var step := 0
const STATES := [
	["full", 6, 6, false],
	["grazed", 5, 6, false],
	["one-left", 2, 6, false],
	["on-fire", 8, 8, true],
	["on-fire-hurt", 5, 8, true],
]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stage = args[0]
	shots = args[1]
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
	root.add_child(main)
	DirAccess.make_dir_recursive_absolute(shots)

func _process(delta: float) -> bool:
	t += delta
	if step == 0 and t > 5.0:
		world.run_chunk("icon", """
local rs = game:GetService("ReplicatedStorage")
local place = rs:FindFirstChild("PlaceAssets") or Instance.new("Folder")
place.Name = "PlaceAssets"
place.Parent = rs
if not place:FindFirstChild("HeartIcon") then
	local v = Instance.new("StringValue")
	v.Name = "HeartIcon"
	v.Value = "user://preview/heart.png"
	v.Parent = place
end
""")
		step = 1
		t = 0.0
	elif step >= 1 and step <= STATES.size() and t > 1.6:
		if step > 1:
			var prev: Array = STATES[step - 2]
			get_root().get_texture().get_image().save_png(shots.path_join("hearts-%s.png" % prev[0]))
			print("  -> hearts-%s.png" % prev[0])
		if step <= STATES.size():
			var st: Array = STATES[step - 1]
			world.run_chunk("state%d" % step, """
local rs = game:GetService("ReplicatedStorage")
local player = game:GetService("Players"):GetPlayers()[1]
local fire = %s
local colours = fire
	and { Color3.fromRGB(228,48,48), Color3.fromRGB(238,200,44), Color3.fromRGB(66,190,76), Color3.fromRGB(56,200,220) }
	or { Color3.fromRGB(228,48,48) }
rs.HeartsRemote:FireClient(player, %d, %d, fire, colours)
""" % ["true" if st[3] else "false", st[1], st[2]])
		step += 1
		t = 0.0
	elif step > STATES.size() and t > 1.6:
		var last: Array = STATES[STATES.size() - 1]
		get_root().get_texture().get_image().save_png(shots.path_join("hearts-%s.png" % last[0]))
		print("  -> hearts-%s.png" % last[0])
		quit(0)
	return false
