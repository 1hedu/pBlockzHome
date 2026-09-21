# HttpService reaches the network from a server with the setting on, and refuses everywhere
# else: with the setting off, and from a client whatever the setting says.
#
#   godot --headless --path . -s res://tests/http_test.gd
#
# The URL resolves to nothing on purpose: what is proved is that the script parks and wakes,
# not that some host is up.
extends SceneTree

const URL := "not-a-url"
const ASK := """
local ok, err = pcall(function() return game:GetService("HttpService"):GetAsync("%s") end)
print("done:" .. tostring(ok) .. ":" .. tostring(err))
""" % URL

var worlds := {}
var said := {}
var t := 0.0
var done := false
var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

# mode: 1 server, 2 client. Set before it enters the tree -- the world reads it in _ready.
func spawn(key: String, http_on: bool, mode: int, source: String) -> void:
	var w := PulseBlockzWorld.new()
	w.mode = mode
	w.http_enabled = http_on
	said[key] = ""
	w.script_print.connect(func(_n, txt): said[key] += txt + "\n")
	w.script_error.connect(func(_n, e): said[key] += "ERROR " + e + "\n")
	get_root().add_child(w)
	w.run_chunk("t", source)
	worlds[key] = w

func _initialize() -> void:
	print("HttpService")
	var fresh := PulseBlockzWorld.new()
	check(not fresh.http_enabled, "a fresh world has HTTP off")
	fresh.queue_free()

	spawn("off", false, 1, ASK)          # server, setting off
	spawn("client", true, 2, ASK)        # client, setting on
	spawn("on", true, 1, ASK)            # server, setting on
	spawn("json", false, 1, """
local h = game:GetService("HttpService")
print("json:" .. tostring(h:JSONDecode(h:JSONEncode({a = 7})).a))
""")

func _process(delta: float) -> bool:
	t += delta
	if done or t < 6.0:
		return false
	done = true

	# "Http requests are not enabled" is Roblox's own wording for the refusal.
	check(said["off"].find("Http requests are not enabled") >= 0,
		"with the setting off, it refuses and names the setting")
	check(said["off"].find("done:true") < 0, "and the call did not succeed")

	check(said["client"].find("can only be called from the server") >= 0,
		"a client is refused even when HTTP is enabled")
	check(said["client"].find("done:true") < 0, "and nothing goes out from a client")

	check(said["on"].find("done:") >= 0, "a server with HTTP on parks the script and wakes it again")
	check(said["on"].find("done:false") >= 0, "a request that cannot be made comes back as an error, not a hang")
	check(said["on"].find("Http requests are not enabled") < 0, "and does not claim to be off")

	check(said["json"].find("json:7") >= 0, "JSONEncode/JSONDecode work with HTTP off")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
	return true
