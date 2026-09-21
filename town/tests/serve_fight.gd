# A town that arms everybody who walks in, and does nothing else.
#
#   godot --headless --path . -s res://tests/serve_fight.gd -- [--port=8892]
#
# serve_bots.gd arms only a player whose NAME is a weapon; this arms every player every pass
# and otherwise leaves them be: no row to stand in, nobody moved, nothing tidied.
extends SceneTree

const StandIns = preload("res://tests/StandIns.gd")
const DEFAULT_PORT := 8892
var world: PulseBlockzWorld
var started := false
var t := 0.0

func _flag(name: String, fallback: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return int(a.get_slice("=", 1))
	return fallback

func _initialize() -> void:
	var port := _flag("port", DEFAULT_PORT)
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = port
	world.default_camera = false
	world.default_controls = false
	world.auto_join = false
	# The trampolines' bounce and the rest are not on chain yet, so they come off disk.
	StandIns.stage("fight")
	get_root().add_child(main)
	print("[fight] a town on %d; everybody who joins gets a BFS 9000" % port)

func _process(delta: float) -> bool:
	t += delta
	if started or t < 4.0:
		return false
	started = true
	world.run_chunk("standins", StandIns.chunk("fight"))
	world.run_chunk("arm", """
local Players = game:GetService("Players")
local Health = require(game:GetService("ServerScriptService").Health)

-- Every blow the server judges, named, in the server's own log. This is the line that says
-- whether somebody's swings are landing and on whom.
local realHit = Health.hit
Health.hit = function(who, attacker, half, shove)
	local landed = realHit(who, attacker, half, shove)
	print(("HIT %s -> %s for %s, landed=%s"):format(
		attacker and attacker.Name or "(nobody)", who and who.Name or "?",
		tostring(half), tostring(landed)))
	return landed
end

--- A stick in somebody's hand. The one thing a client may not do for itself.
---
--- Weapons.server.luau looks for an Accoutrement whose Name is a weapon and nothing else, so a
--- handle and the right name is a whole weapon as far as the fight is concerned.
local function arm(p)
	local ch = p.Character
	if not ch or ch:FindFirstChild("BFS 9000") then return false end
	local acc = Instance.new("Accessory")
	acc.Name = "BFS 9000"
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 2.2, 0.4)
	handle.Parent = acc
	acc.Parent = ch
	return true
end

while true do
	for _, p in ipairs(Players:GetPlayers()) do
		-- Every pass, because a death hands out a new body and the weapon went with the old
		-- one -- which reads as a swing that stopped working.
		if arm(p) then print(("armed %s"):format(p.Name)) end
		Health.setFights(p, true)
	end
	task.wait(1)
end
""")
	return false
