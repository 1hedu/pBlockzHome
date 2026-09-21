# A real client jumping over and over, writing down every apex.
#
#   godot --headless --path . -s res://tests/jump_peer.gd -- --name=Jumper --out=<file>
#
# A jump is refused unless the engine says the feet are down, and the launch velocity is SET not
# added, so a double write goes much higher. Both ends are timing: the spread over many jumps is
# the measurement, and it shows only on a real client against a real server, never in Play Solo.
extends SceneTree

var world: PulseBlockzWorld
var who := "Jumper"
var out := ""
var joined := false
var log := PackedStringArray()

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	out = _flag("out", "user://jump.txt")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8896"))
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

func _heard(_name: String, line: String) -> void:
	if not line.begins_with("HOP "):
		return
	log.append(line.substr(4))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log))
		f.close()

func _process(_delta: float) -> bool:
	if not world.is_server_connected() or joined:
		return false
	joined = true
	print("[peer] %s is in" % who)
	world.run_chunk("hop", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local map = workspace:WaitForChild("Map", 30)
local ground = map and map:FindFirstChild("Ground", true)
local flat = ground and (ground.Position + Vector3.new(0, ground.Size.Y / 2 + 4, 0))
	or Vector3.new(0, 8, 0)

local char = me.Character or me.CharacterAdded:Wait()
local root = char:WaitForChild("HumanoidRootPart")
local hum = char:WaitForChild("Humanoid")
root.CFrame = CFrame.new(flat)
root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
for _ = 1, 120 do RunService.Heartbeat:Wait() end

for n = 1, 16 do
	-- Freshly looked up each time: a respawn hands out a new body and the old root keeps
	-- answering from wherever it was destroyed.
	char = me.Character
	root = char and char:FindFirstChild("HumanoidRootPart")
	hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum then
		local floor = root.Position.Y
		hum.Jump = true
		local peak, up, frames = floor, false, 0
		for _ = 1, 160 do
			RunService.Heartbeat:Wait()
			frames += 1
			local y = root.Position.Y
			if y > peak then peak = y end
			if y > floor + 0.5 then up = true end
			if up and y <= floor + 0.2 then break end
		end
		print(("HOP %d|apex %.2f|held %d frames|floor %.2f peak %.2f ended %.2f"):format(
			n, peak - floor, frames, floor, peak, root.Position.Y))
	else
		print(("HOP %d|apex -1.00|held 0 frames|entered at 0.0 up"):format(n))
	end
	task.wait(0.7)
end

-- A held space bar: the control path sets Humanoid.Jump every frame the key is down, so
-- writing it every frame is what the engine sees from a player holding it.
for n = 1, 8 do
	char = me.Character
	root = char and char:FindFirstChild("HumanoidRootPart")
	hum = char and char:FindFirstChildOfClass("Humanoid")
	if root and hum then
		local floor = root.Position.Y
		local peak, up, relaunches = floor, false, 0
		local lastY = 0
		for f = 1, 160 do
			-- Held for the first 40 frames, about two thirds of a second.
			if f <= 40 then hum.Jump = true end
			RunService.Heartbeat:Wait()
			local y = root.Position.Y
			local vy = root.AssemblyLinearVelocity.Y
			-- A launch that happens again after the first: the upward speed jumping back up
			-- when it should only ever be falling.
			if f > 2 and vy > lastY + 20 then relaunches += 1 end
			lastY = vy
			if y > peak then peak = y end
			if y > floor + 0.5 then up = true end
			if up and y <= floor + 0.2 then break end
		end
		print(("HOP held-%d|apex %.2f|held %d frames|entered at %d up"):format(
			n, peak - floor, 40, relaunches))
	end
	task.wait(1.0)
end

""")
	return false
