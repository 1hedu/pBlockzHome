# A real client meeting a trampoline two ways: landing on it from the air, and walking on.
#
#   godot --headless --path . -s res://tests/tramp_peer.gd -- --name=Jumper --out=<file>
#
# The arc is measured inside the client, the machine actually simulating the body: the server
# runs Touched and writes the velocity, and it has to cross the wire to get here.
extends SceneTree

var world: PulseBlockzWorld
var who := "Jumper"
var out := ""
var joined := false
var t := 0.0

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	out = _flag("out", "user://tramp.txt")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8817"))
	world.player_name = who
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("[peer] LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(_heard)
	get_root().add_child(main)
	var blank := FileAccess.open(out, FileAccess.WRITE)
	if blank: blank.close()
	print("[peer] %s asking for the town" % who)

var log := PackedStringArray()

func _heard(_name: String, line: String) -> void:
	if not line.begins_with("RODE "):
		return
	log.append(line.substr(5))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log))
		f.close()

func _process(delta: float) -> bool:
	t += delta
	if not world.is_server_connected() or joined:
		return false
	joined = true
	print("[peer] %s is in" % who)
	world.run_chunk("ride", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local map = workspace:WaitForChild("Map", 30)
local pad = map and map:FindFirstChild("TrampolineWestNorth", true)
if not pad then print("RODE nopad") return end

--- Meets the pad and reports how high it threw them, measured on THIS machine.
---
--- `drop` is how far above the pad to start. Nought puts them on it standing -- which is
--- walking onto it, near enough, and the case that is said to work. Anything more is a
--- landing: they arrive moving, which is what jumping onto one is.
local function ride(drop, label)
	local char = me.Character or me.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")
	local hum = char:WaitForChild("Humanoid")
	hum.Health = hum.MaxHealth
	root.CFrame = CFrame.new(pad.Position + Vector3.new(0, 3.2 + drop, 0))
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	task.wait(0.15)
	local padY = pad.Position.Y
	local peak, fell = root.Position.Y, false
	local touched = 0
	for _ = 1, 260 do
		RunService.Heartbeat:Wait()
		local y = root.Position.Y
		if y > peak then peak = y end
		if y < padY then fell = true end
	end
	print(("RODE %s|drop %.1f|apex over the pad %.1f|ended %.1f"):format(
		label, drop, peak - padY, root.Position.Y - padY))
	task.wait(1.8)                 -- past the pad's own cooldown before the next go
end

-- And an ordinary jump on this machine, with nothing to do with a trampoline: the height a
-- real player over the wire actually gets, which is the other half of what was reported.
do
	local char = me.Character or me.CharacterAdded:Wait()
	local root = char:WaitForChild("HumanoidRootPart")
	local hum = char:WaitForChild("Humanoid")
	-- On the Ground, well away from any pad: dropped onto the pad it was launched by the
	-- trampoline and the "jump" was measured on a body still falling off the map.
	local ground = map:FindFirstChild("Ground", true)
	local flat = ground and (ground.Position + Vector3.new(0, ground.Size.Y / 2 + 4, 0))
		or Vector3.new(0, 8, 0)
	root.CFrame = CFrame.new(flat)
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	for _ = 1, 90 do RunService.Heartbeat:Wait() end            -- settle on the floor
	print(("RODE settled|drop 0.0|apex over the pad 0.00|ended %.2f"):format(root.Position.Y))
	local floor = root.Position.Y
	hum.Jump = true
	local peak, up = floor, false
	for _ = 1, 200 do
		RunService.Heartbeat:Wait()
		local y = root.Position.Y
		if y > peak then peak = y end
		if y > floor + 0.5 then up = true end
		if up and y <= floor + 0.2 then break end
	end
	print(("RODE a plain jump|drop 0.0|apex over the pad %.2f|ended 0.0"):format(peak - floor))
	task.wait(0.5)
end

ride(0, "stood on it")
ride(14, "dropped onto it from fourteen studs")
ride(0, "stood on it again")
ride(26, "dropped onto it from twenty-six")
""")
	return false
