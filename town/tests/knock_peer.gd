# A real client standing still, writing down how far each shove actually moved it.
#
#   godot --headless --path . -s res://tests/knock_peer.gd -- --name=Shoved --out=<file>
#
# The shove is a velocity the server writes onto a body this machine simulates, so the
# measuring happens here, off this client's own root part. Armed by this body's health
# changing -- the one signal already crossing the wire for it, so no second channel is needed.
extends SceneTree

var world: PulseBlockzWorld
var who := "Shoved"
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
	out = _flag("out", "user://knock.txt")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8897"))
	world.player_name = who
	world.default_camera = false
	# No hands on the controls: a walk of its own would read as a shove.
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("[peer] LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(_heard)
	get_root().add_child(main)
	var blank := FileAccess.open(out, FileAccess.WRITE)
	if blank: blank.close()
	print("[peer] %s asking for the town" % who)

func _heard(_name: String, line: String) -> void:
	if not line.begins_with("KNOCK "):
		return
	log.append(line.substr(6))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log))
		f.close()

func _process(_delta: float) -> bool:
	if not world.is_server_connected() or joined:
		return false
	joined = true
	print("[peer] %s is in" % who)
	world.run_chunk("shoved", """
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local me = Players.LocalPlayer
local ch = me.Character or me.CharacterAdded:Wait()
local hum = ch:WaitForChild("Humanoid")
local root = ch:WaitForChild("HumanoidRootPart")

-- The furthest this body gets from where it was standing, along the ground.
--
-- The furthest rather than where it ends up: the walk drags a shoved body back toward a
-- standstill once its feet are down, so the resting place understates the throw and would
-- read a real shove as nothing much. What is being asked is how far you were sent.
--- How close the nearest other body is, and which one.
---
--- Kept in every report because it is the difference between a shove that failed and a shove
--- that landed on somebody who had nowhere to go. A character wedged against another
--- character cannot slide sideways, and a blocked body reads exactly like a shove that never
--- arrived -- the distance travelled is nought for both.
local function nearest()
	local best, who = 1e9, "nobody"
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= me and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r then
				local d = (r.Position - root.Position).Magnitude
				if d < best then best, who = d, p.Name end
			end
		end
	end
	return best, who
end

--- Stand clear before being shoved.
---
--- The bots pile up on the spawn point -- serve_bots has a long note about it -- and this
--- client joins into the same spot. Measuring a shove on a body pinned inside that pile
--- measures the pile. Moving out of it is this client's own business: it owns this body, so
--- a CFrame written here sticks, where one written by the server would only be a suggestion.
local function standClear()
	-- Every round, not only when the crowd is close: a shove throws the body several studs and
	-- it stays there, so without a reset each round starts somewhere else and a body parked
	-- against a wall reads like the pile.
	-- Away from the crowd's middle, which is the direction with room in it.
	local mid, n = Vector3.new(0, 0, 0), 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= me and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r then mid = mid + r.Position n = n + 1 end
		end
	end
	if n == 0 then return end
	mid = mid / n
	local away = root.Position - mid
	away = Vector3.new(away.X, 0, away.Z)
	away = away.Magnitude > 1e-3 and away.Unit or Vector3.new(1, 0, 0)
	root.CFrame = CFrame.new(mid + away * 22 + Vector3.new(0, root.Position.Y - mid.Y, 0))
	root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	task.wait(0.35)
end

local function measure(at)
	standClear()
	local wasNear, nearWho = nearest()
	local start = root.Position
	local best, top, peak = 0.0, 0.0, 0.0
	local t0 = os.clock()
	while os.clock() - t0 < 2.5 do
		RunService.Heartbeat:Wait()
		local d = root.Position - start
		local flat = Vector3.new(d.X, 0, d.Z).Magnitude
		if flat > best then best = flat end
		if d.Y > top then top = d.Y end
		-- The fastest this body was ever actually going, sideways.
		--
		-- This is what separates the two ways a shove can come to nothing. If the peak is
		-- the speed the server asked for then the velocity crossed the wire and landed and
		-- something here ate it; if the peak is nought it never arrived. They want opposite
		-- fixes and they look identical from the distance travelled.
		local v = root.AssemblyLinearVelocity
		local sideways = Vector3.new(v.X, 0, v.Z).Magnitude
		if sideways > peak then peak = sideways end
	end
	print(("KNOCK at=%s went=%.2f up=%.2f peak=%.2f near=%.1f(%s)"):format(
		tostring(at), best, top, peak, wasNear, nearWho))
end

local last = hum.Health
while true do
	RunService.Heartbeat:Wait()
	if hum.Health ~= last then
		last = hum.Health
		measure(last)
	end
end
""")
	return false
