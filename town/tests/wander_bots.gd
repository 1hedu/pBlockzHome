# Two bots on the .env.testnet wallets, wandering, jumping and riding the trampolines until
# a stop file appears or the minutes run out.
#   godot --headless --path . -s res://tests/zz_bots.gd -- <stopfile> [minutes]
extends SceneTree
const Peer = preload("res://tests/Peer.gd")
var t := 0.0
var peers := []
var stopfile := ""
var minutes := 25.0
var chunk := ""

func _key(name: String) -> String:
	var f := FileAccess.open("res://../../../.env.testnet", FileAccess.READ)
	if f == null:
		# res:// will not walk above the project, so globalize first and go up from there.
		f = FileAccess.open(ProjectSettings.globalize_path("res://").path_join("../../../.env.testnet").simplify_path(), FileAccess.READ)
	if f == null:
		return ""
	for line in f.get_as_text().split("\n"):
		var l := line.strip_edges()
		if l.begins_with(name + "="):
			return l.substr(name.length() + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	stopfile = args[0] if args.size() > 0 else "user://stop-bots"
	minutes = float(args[1]) if args.size() > 1 else 25.0
	chunk = OS.get_user_data_dir().path_join("bot.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("""
local Players = game:GetService("Players")
local me = Players.LocalPlayer
task.wait(12)
local char = me.Character or me.CharacterAdded:Wait()
local hum = char:WaitForChild("Humanoid")
local root = char:WaitForChild("HumanoidRootPart")
local home = root.Position
print(("SEEN bot up as %s at %s"):format(me.Name, tostring(home)))
local map = workspace:WaitForChild("Map", 30)
local pads = {}
if map then for _, d in ipairs(map:GetDescendants()) do if d:IsA("BasePart") and d.Name:find("^Trampoline") then table.insert(pads, d) end end end
print(("SEEN %d trampoline pad(s)"):format(#pads))
me.CharacterAdded:Connect(function(c)
	char = c
	hum = c:WaitForChild("Humanoid")
	root = c:WaitForChild("HumanoidRootPart")
	print("SEEN respawned")
end)
local rides = 0
-- Walks by steering, a Move a frame, until it is there or has had long enough: MoveToFinished
-- does not fire for a client's own body here, and waiting on it left the bots standing.
local function walkTo(target, patience)
	local t0 = os.clock()
	while os.clock() - t0 < patience do
		local away = target - root.Position
		away = Vector3.new(away.X, 0, away.Z)
		if away.Magnitude < 2 then break end
		hum:Move(away.Unit)
		task.wait()   -- every frame: a Move here lasts the one frame, as the controls' own does
	end
	hum:Move(Vector3.new(0, 0, 0))
	local left = (target - root.Position)
	print(("SEEN walked %.1fs, %.1f studs short, MoveDirection %s, state %s"):format(os.clock() - t0, Vector3.new(left.X, 0, left.Z).Magnitude, tostring(hum.MoveDirection), tostring(hum:GetState())))
end
task.spawn(function() while true do task.wait(15); print("SEEN at " .. tostring(root.Position)) end end)
while true do
	local pick = math.random()
	if #pads > 0 and pick < 0.35 then
		-- Toward a pad on foot, and onto it if the walk got there. A wall in the way ends it short,
		-- as it would for anyone; there is no teleporting.
		local pad = pads[math.random(#pads)]
		walkTo(pad.Position + Vector3.new(7, 0, 0), 14)
		walkTo(pad.Position, 4)
		rides += 1
		task.wait(3)
	elseif pick < 0.8 then
		-- Somewhere near home, and a hop on the way.
		local target = home + Vector3.new(math.random(-25, 25), 0, math.random(-25, 25))
		if math.random() < 0.5 then task.delay(0.5, function() hum.Jump = true end) end
		walkTo(target, 10)
	else
		task.wait(2)
	end
	if rides > 0 and rides % 5 == 0 then print(("SEEN %d rides, at %s"):format(rides, tostring(root.Position))); rides += 1 end
end
""")
	f.close()
	var keys := [["PLAYER_KEY", "BotPlayer"], ["RELAYER_KEY", "BotRelayer"]]
	for k in keys:
		var key := _key(k[0])
		if key == "":
			print("no ", k[0], " in the env file; that bot is a guest")
		var out := OS.get_user_data_dir().path_join("bot-%s.txt" % k[1])
		var opts := { "name": k[1], "host": "play.safewrap.xyz", "reads": true }
		if key != "": opts["key"] = key
		peers.append({ "p": Peer.spawn("res://tests/chunk_peer.gd", ["--port=8800", "--chunk=%s" % chunk, "--out=%s" % out], opts), "out": out, "name": k[1], "seen": 0 })
	print("bots launched; stop with ", stopfile)

func _process(delta: float) -> bool:
	t += delta
	for b in peers:
		if FileAccess.file_exists(b.out):
			var lines := FileAccess.get_file_as_string(b.out).split("\n")
			while b.seen < lines.size():
				var l: String = lines[b.seen]
				if l.strip_edges() != "": print("[%s] %s" % [b.name, l.strip_edges()])
				b.seen += 1
	if FileAccess.file_exists(stopfile) or t > minutes * 60.0:
		for b in peers: Peer.stop(b.p)
		print("bots stopped after %.0f s" % t)
		quit(0)
		return true
	return false
