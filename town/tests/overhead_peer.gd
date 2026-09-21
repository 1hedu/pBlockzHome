# The client half of overhead_test.gd: joins the server and reports what its OWN PlayerGui
# draws over everyone's head, since boards are built per client. The server half owns health
# and the PvP flag, so the two talk through a file -- the script sandbox has no io library.
#
#   godot --headless --path . -s res://tests/overhead_peer.gd -- --name=Watcher [--port=8815]
extends SceneTree

var world: PulseBlockzWorld
var who := "Watcher"
var joined := false
var out := ""

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	out = _flag("out", "user://overhead.json")
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8815"))
	world.player_name = who
	# place_billboard returns early without a camera, so a cameraless peer could report that a
	# board exists but never its AbsolutePosition or AbsoluteSize.
	world.default_camera = true
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("[peer] LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(_heard)
	get_root().add_child(main)
	print("[peer] %s asking %s:%d for the town" % [who, world.server_address, world.server_port])

## The Lua half's latest report, overwritten in place in the file the server half reads.
func _heard(_name: String, line: String) -> void:
	if not line.begins_with("PEER "):
		return
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string(line.substr(5))
		f.close()

func _process(_delta: float) -> bool:
	if not world.is_server_connected() or joined:
		return false
	joined = true
	print("[peer] %s is in" % who)
	world.run_chunk("report", """
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Theme = require(ReplicatedStorage:WaitForChild("Theme"))
local me = Players.LocalPlayer
local gui = me:WaitForChild("PlayerGui")

-- What one board actually contains, walked rather than assumed: what is under test is that
-- the pieces are there and pointed at the right things.
local function readBoard(board)
	local name, hearts, full, empty = nil, nil, 0, 0
	for _, d in ipairs(board:GetDescendants()) do
		if d:IsA("TextLabel") and d.Name == "Name" then name = d end
		if d:IsA("Frame") and d.Name == "Hearts" and d.Parent == board then hearts = d end
		-- A container's filled part is shown through a window whose width is how much of it
		-- is left, so the windows added up are the half-hearts.
		if d:IsA("Frame") and d.Name == "Window" and d.Visible then full += d.Size.X.Scale end
		if d:IsA("ImageLabel") and d.Name == "Empty" then empty += 1 end
	end
	-- Where the host actually put it. AbsolutePosition and AbsoluteSize are written back by
	-- the renderer every frame, so a board that is in the tree but never drawn reads nought
	-- here -- which is the whole difference between "it exists" and "you can see it".
	local drawn = 0
	local at = Vector2.new(0, 0)
	if name then
		at = name.AbsolutePosition
		drawn = name.AbsoluteSize.X
	end
	-- The RAW health this client can see for that body, beside what the row drew from it.
	-- If the two ever disagree the row is at fault; if they agree and the SERVER disagrees,
	-- the property never crossed the wire and no amount of redrawing will help.
	local who = board.Name:sub(#"Overhead" + 1)
	local them = Players:FindFirstChild(who)
	local hum = them and them.Character and them.Character:FindFirstChildOfClass("Humanoid")
	return {
		board = board.Name,
		seenHealth = hum and hum.Health or -1,
		-- What a WATCHER thinks this body is doing. Its owner publishes StateName and the
		-- property replicates, so this should say Running for anybody standing still. If it
		-- says Freefall the answer is not arriving -- and that is the arms-up-on-flat-ground.
		seenState = hum and tostring(hum:GetState()) or "?",
		-- Where the arms actually ARE, on this machine, which is the symptom itself. The
		-- freefall pose puts them straight up, so an arm above the head is a body wearing it.
		-- GetState saying Running and the arms still up would mean the pose is not coming
		-- from the state at all.
		armUp = (function()
			local ch2 = them and them.Character
			local arm = ch2 and ch2:FindFirstChild("Right Arm")
			local hd = ch2 and ch2:FindFirstChild("Head")
			if not arm or not hd then return "?" end
			return ("%.2f"):format(arm.Position.Y - hd.Position.Y)
		end)(),
		seenMax = hum and hum.MaxHealth or -1,
		drawnWidth = drawn,
		atX = at.X,
		atY = at.Y,
		adornee = board.Adornee and board.Adornee:GetFullName() or "",
		enabled = board.Enabled,
		text = name and name.Text or "",
		-- The place's own face on the name, which is the thing that was asked for. Reported
		-- alongside whether the theme has a font at all, so a font that never arrived reads
		-- as "not fetched" rather than as this script having missed it.
		faced = name ~= nil and Theme.font ~= nil and tostring(name.FontFace) == tostring(Theme.font),
		themeHasFont = Theme.font ~= nil,
		heartsShown = hearts ~= nil and hearts.Visible or false,
		containers = empty,
		halves = math.floor(full * 2 + 0.5),
	}
end

-- Every distinct health this client is handed for each body, in order.
--
-- Sampled rather than signalled: a property set to the value it already holds fires nothing,
-- and what is in question is precisely how many changes arrive. If the list has one entry and
-- the server has taken six hearts off, the wire stopped after the first.
local seenRun = {}
task.spawn(function()
	while true do
		task.wait(0.05)
		for _, p in ipairs(Players:GetPlayers()) do
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				local run = seenRun[p.Name]
				if not run then run = {} seenRun[p.Name] = run end
				if run[#run] ~= hum.Health then table.insert(run, hum.Health) end
			end
		end
	end
end)

while true do
	task.wait(0.4)
	local report = { mine = false, screen = false, boards = {}, runs = {} }
	for who, run in pairs(seenRun) do
		local bits = {}
		for _, v in ipairs(run) do table.insert(bits, tostring(v)) end
		report.runs[who] = table.concat(bits, ">")
	end
	local screen = gui:FindFirstChild("Overhead")
	report.screen = screen ~= nil
	if screen then
		for _, board in ipairs(screen:GetChildren()) do
			if board:IsA("BillboardGui") then
				-- A board for the watcher itself is the one thing that must never be built:
				-- you have the meter along the bottom of your own screen.
				if board.Name == ("Overhead" .. me.Name) then report.mine = true end
				table.insert(report.boards, readBoard(board))
			end
		end
	end
	local ok, blob = pcall(function() return HttpService:JSONEncode(report) end)
	if ok then print("PEER " .. blob) end
end
""")
	return false
