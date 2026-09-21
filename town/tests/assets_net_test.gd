# A joined client draws the place's assets from its own fetch, not the server's disk.
#
#   godot --headless --path . -s res://tests/assets_net_test.gd
#
# The server replicates pblockz:// uris -- in SoundId, MeshId, Texture, sky faces -- never a path
# on its own disk, and each machine fetches them through its own wallet. So the peer holds a user
# folder of its own (Peer.gd): PreloadAsync Success there means the bytes reached it. Needs chain.
# NEEDED mirrors Intro.client.luau's wait-list plus SfxTrampoline and Reactor7; hence the 12s.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
const Peer = preload("res://tests/Peer.gd")
const PORT := 8828

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var peer := {}
var heard: Array[String] = []
var t := 0.0
var phase := 0
var report := ""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _file_last(path: String, prefix: String) -> String:
	if not FileAccess.file_exists(path): return ""
	var lines := FileAccess.get_file_as_string(path).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i].begins_with(prefix): return lines[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	print("assets over the wire: a client fetches its own")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.mode = 1
	world.listen_port = PORT
	world.default_camera = false
	world.default_controls = false
	world.data_store_path = ""
	world.script_print.connect(func(_n, line): heard.append(line))
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	get_root().add_child(main)
	Arrive.now(world)

	report = OS.get_user_data_dir().path_join("assets_peer.txt")
	DirAccess.remove_absolute(report)
	var chunk := OS.get_user_data_dir().path_join("assets_peer.luau")
	var f := FileAccess.open(chunk, FileAccess.WRITE)
	f.store_string("""
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local SCHEME = "pblockz://"
local NEEDED = { "SkyboxUp", "SkyboxDn", "SkyboxFt", "SkyboxBk", "SkyboxLf", "SkyboxRt",
                 "RocketMesh", "TreeMesh", "HeartIcon", "FlameSprite", "SfxTrampoline", "Reactor7" }
local place = ReplicatedStorage:WaitForChild("PlaceAssets", 60)
local list, uris, other = {}, 0, 0
for _, name in ipairs(NEEDED) do
	local v = place and place:WaitForChild(name, 60)
	local value = v and v.Value or ""
	-- By the scheme itself rather than a counted number of characters: the count was the old
	-- scheme's and stayed behind when the name changed, which reads as every asset arriving as
	-- a path.
	if value:sub(1, #SCHEME) == SCHEME then uris += 1 elseif value ~= "" then other += 1 end
	if value ~= "" then table.insert(list, value) end
end
print(("SEEN VALUES uris=%d paths=%d of=%d"):format(uris, other, #NEEDED))
local sky = Lighting:WaitForChild("MoonEarthSky", 60)
print("SEEN SKY " .. (sky and sky.SkyboxUp:sub(1, #SCHEME) or "none"))
-- The sounds this client made for itself off PlaceAssets (the menu blip, the NES voices): by uri.
local SoundService = game:GetService("SoundService")
local blip = SoundService:WaitForChild("menu", 60)
print("SEEN BOUNCE " .. (blip and blip.SoundId:sub(1, #SCHEME) or "none"))
local ok, bad, t0 = 0, 0, os.clock()
ContentProvider:PreloadAsync(list, function(id, status)
	if status == Enum.AssetFetchStatus.Success then ok += 1 else bad += 1 print("SEEN FAILED " .. id) end
end)
print(("SEEN PRELOAD ok=%d bad=%d of=%d secs=%.1f queue=%d"):format(ok, bad, #list, os.clock() - t0, ContentProvider.RequestQueueSize))
""")
	f.close()
	peer = Peer.spawn("res://tests/chunk_peer.gd",
		["--port=%d" % PORT, "--chunk=%s" % chunk, "--out=%s" % report], { "name": "Visitor", "reads": false })

func _process(delta: float) -> bool:
	t += delta
	var loaded := _file_last(report, "PRELOAD ")
	if phase == 0 and (loaded != "" or t > 150.0):
		phase = 1
		var values := _file_last(report, "VALUES ")
		print("    client sees: ", values, " | sky ", _file_last(report, "SKY "), " | bounce ", _file_last(report, "BOUNCE "))
		print("    preload: ", loaded)
		for line in FileAccess.get_file_as_string(report).split("\n", false):
			if line.begins_with("FAILED "): print("    ", line)
		check(values.contains("uris=12") and values.contains("paths=0"), "every place asset reaches the client as a pblockz:// uri, none as a path")
		check(_file_last(report, "SKY ") == "pblockz://", "the sky's faces are uris on the client")
		check(_file_last(report, "BOUNCE ") == "pblockz://", "a Sound the client made off PlaceAssets names its clip by uri")
		check(loaded.contains("ok=12") and loaded.contains("bad=0"), "and PreloadAsync on the client fetched all twelve onto the client's own machine")
		var media := DirAccess.get_files_at(String(peer.user_dir).path_join("Godot/app_userdata/PulseBlockz Town/media"))
		var any_media := media.size() > 0
		check(any_media, "the files are in the client's own user folder (%d there)" % media.size())
		Peer.stop(peer)
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
