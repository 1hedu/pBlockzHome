# Is the spoon server script alive, and does a click reach it?
#
#   godot --path . -s res://tests/spoon_probe.gd -- <stage dir>
extends SceneTree
var world: PulseBlockzWorld
var stage := ""
var t := 0.0
var phase := 0

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
	root.add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 6.0:
		phase = 1
		world.run_client_chunk("screens", """
local gui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local blocking = {}
for _, screen in ipairs(gui:GetChildren()) do
	if screen:IsA("ScreenGui") then
		local hud = screen:GetAttribute("Hud") and " [hud]" or ""
		local blocks = screen.Enabled and screen.Name ~= "TownDialog" and not screen:GetAttribute("Hud")
		if blocks then table.insert(blocking, screen.Name) end
		print(("PROBE screen %-14s enabled=%-5s%s%s"):format(screen.Name, tostring(screen.Enabled), hud,
			blocks and "  <-- BLOCKS SWINGING" or ""))
	end
end
print("PROBE blocking the spoon: " .. (#blocking == 0 and "nothing" or table.concat(blocking, ", ")))
""")
		world.run_chunk("probe", """
local rs = game:GetService("ReplicatedStorage")
local sss = game:GetService("ServerScriptService")
print("PROBE WeaponRemote exists: " .. tostring(rs:FindFirstChild("WeaponRemote") ~= nil))
print("PROBE HeartsRemote exists: " .. tostring(rs:FindFirstChild("HeartsRemote") ~= nil))
print("PROBE CombatSfx exists: " .. tostring(rs:FindFirstChild("CombatSfx") ~= nil))
print("PROBE Health module present: " .. tostring(sss:FindFirstChild("Health") ~= nil))
local ok, err = pcall(function() return require(sss.Health) end)
print("PROBE require(Health): " .. tostring(ok) .. " " .. tostring(err))
for _, d in ipairs(sss:GetChildren()) do
	if d.Name == "Spoon" then print("PROBE Spoon script class: " .. d.ClassName) end
end
""")
		t = 0.0
	elif phase == 1 and t > 3.0:
		quit(0)
	return false
