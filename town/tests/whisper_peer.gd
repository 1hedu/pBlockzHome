# One client in the town, writing down every line of chat it hears. whisper_test.gd is the
# server. A whisper is private by delivery -- its channel holds only the two TextSources in
# it -- so the client that must not hear it has to be a process of its own.
#
#   godot --headless --path . -s res://tests/whisper_peer.gd -- --name=Alice --out=<file> \
#       [--port=8816] [--say="/w Bob are you there"] [--after=6]
extends SceneTree

var world: PulseBlockzWorld
var who := "Peer"
var out := ""
var said := PackedStringArray()
var after := 6.0
var joined := false
var spoke := 0
var t := 0.0
var log := PackedStringArray()

func _flag(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(("--%s=" % name).length())
	return fallback

func _initialize() -> void:
	who = _flag("name", who)
	out = _flag("out", "user://whisper-%s.txt" % who)
	# --say takes several lines with ";;" between them, one spoken every `after` seconds.
	var say := _flag("say", "")
	said = PackedStringArray() if say == "" else say.split(";;")
	after = float(_flag("after", str(after)))
	var main: Node = load("res://Main.tscn").instantiate()
	world = main.get_node("World")
	world.mode = 2
	world.server_address = _flag("host", "127.0.0.1")
	world.server_port = int(_flag("port", "8816"))
	world.player_name = who
	world.default_camera = false
	world.default_controls = false
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("[peer %s] LUA ERROR [%s] %s" % [who, n, e]))
	world.script_print.connect(_heard)
	get_root().add_child(main)
	# Both files exist from the start, so the server half can tell "heard nothing" from
	# "never started".
	_write()
	var blank := FileAccess.open(out + ".drew", FileAccess.WRITE)
	if blank: blank.close()
	print("[peer] %s asking for the town" % who)

## HEARD is what the runtime delivered; DREW is what the chat window put on screen. /squelch
## is the window's own decision, so HEARD alone would pass with squelch doing nothing.
func _heard(_name: String, line: String) -> void:
	if line.begins_with("HEARD "):
		log.append(line.substr(6))
		_write()
	elif line.begins_with("DREW "):
		var f := FileAccess.open(out + ".drew", FileAccess.WRITE)
		if f:
			f.store_string(line.substr(5))
			f.close()

## Rewritten whole rather than appended to: the server half reads it whenever it likes, and
## half a written line would parse as a line.
func _write() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log))
		f.close()

func _process(delta: float) -> bool:
	t += delta
	if not world.is_server_connected():
		return false
	if not joined:
		joined = true
		print("[peer] %s is in" % who)
		t = 0.0
		world.run_chunk("listen", """
local TextChatService = game:GetService("TextChatService")
-- The service's signal, which fires once per message for every channel. A whisper arrives
-- on a channel of its own, so a listener on RBXGeneral alone would hear nothing and the
-- test would pass by being deaf.
TextChatService.MessageReceived:Connect(function(msg)
	local channel = msg.TextChannel
	local from = msg.TextSource
	print(("HEARD %s|%s|%s"):format(
		channel and tostring(channel.Name) or "?",
		from and tostring(from.Name) or "-",
		tostring(msg.Text or "")))
end)

-- And what the window actually drew. Its own loop rather than a line per message, because
-- what is wanted is the state of the log and not the events that built it.
local Players = game:GetService("Players")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
task.spawn(function()
	while true do
		task.wait(0.5)
		local chat = gui:FindFirstChild("TownChat")
		local rows = {}
		if chat then
			for _, d in ipairs(chat:GetDescendants()) do
				if d:IsA("TextLabel") and d.Parent and d.Parent:IsA("ScrollingFrame") then
					table.insert(rows, { order = d.LayoutOrder, text = d.Text })
				end
			end
		end
		table.sort(rows, function(a, b) return a.order < b.order end)
		local texts = {}
		for _, r in ipairs(rows) do table.insert(texts, r.text) end
		print("DREW " .. table.concat(texts, "  //  "))
	end
end)
""")
		return false
	# Held off until everybody has joined: a whisper to somebody not in the town yet reaches
	# nobody.
	if spoke < said.size() and t > after * (spoke + 1):
		var line := String(said[spoke])
		spoke += 1
		print("[peer] %s says [%s]" % [who, line])
		world.run_chunk("say", ("""
local TextChatService = game:GetService("TextChatService")
local general = TextChatService:WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
-- Through the chat box, because that is where a leading slash becomes a command.
general:SendAsync("WHAT_WAS_SAID")
""").replace("WHAT_WAS_SAID", line))
	return false
