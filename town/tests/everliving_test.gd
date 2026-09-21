# The Everliving Fish: held, lying face up in the fountain, a wounded player stands up whole.
#
#   godot --headless --path . -s res://tests/everliving_test.gd
#
# Play Solo. /lay goes through the chat as a player would type it; standing is moving off.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the Everliving Fish")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)
	Arrive.now(world)
	_run()

func _said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _server(body: String) -> void:
	world.run_chunk("everliving", """
local Players = game:GetService("Players")
local player = Players:GetPlayers()[1]
local ch = player.Character
local hum = ch and ch:FindFirstChildOfClass("Humanoid")
local root = ch and ch:FindFirstChild("HumanoidRootPart")
local water = workspace.Map.Fountain.Water
local function fish(on)
	local have = ch:FindFirstChild("Everliving Fish")
	if on and not have then
		local acc = Instance.new("Accessory")
		acc.Name = "Everliving Fish"
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.4, 0.6, 1.3)
		handle.CanCollide = false
		handle.Massless = true
		handle.Parent = acc
		hum:AddAccessory(acc)
	elseif not on and have then
		have:Destroy()
	end
end
local function at(x, z) root.CFrame = CFrame.new(x, water.Position.Y + 3.2, z) root.AssemblyLinearVelocity = Vector3.zero end
""" + body)

func _say(line: String) -> void:
	world.run_client_chunk("say", """
game:GetService("TextChatService"):WaitForChild("TextChannels"):WaitForChild("RBXGeneral"):SendAsync("%s")
""" % line)

## One case: returns the health it ended on, out of its max, as "h/m".
func _case(name: String, fish_before: bool, fish_inside: bool, roll: bool, in_fountain: bool) -> String:
	_server("""
fish(%s)
at(water.Position.X + 16, water.Position.Z)
local ff = ch:FindFirstChildOfClass("ForceField") if ff then ff:Destroy() end
hum.Health = 2
""" % ("true" if fish_before else "false"))
	await create_timer(0.8).timeout
	_server("""
if %s then at(water.Position.X + 1.5, water.Position.Z + 1.5) end
""" % ("true" if in_fountain else "false"))
	await create_timer(0.8).timeout
	if fish_inside:
		_server("fish(true)")
		await create_timer(0.8).timeout
	_say("/lay")
	await create_timer(1.5).timeout
	if roll:
		_say("/roll")
		await create_timer(1.5).timeout
	# Moving off is what stands a laid-down character up.
	_server("""
root.CFrame = root.CFrame + Vector3.new(0, 0, 8)
""")
	await create_timer(1.2).timeout
	said.clear()
	_server("""
print("HEALTH " .. math.floor(hum.Health + 0.5) .. "/" .. hum.MaxHealth .. " emote=" .. tostring(ch:GetAttribute("Emote")))
""")
	await create_timer(0.4).timeout
	var got := _said("HEALTH ")
	print("    %s: %s" % [name, got])
	return got

func _run() -> void:
	await create_timer(10.0).timeout
	var full := await _case("fish in hand, face up, in the fountain", true, false, false, true)
	var none := await _case("no fish", false, false, false, true)
	var late := await _case("fish taken out once already in", false, true, false, true)
	var belly := await _case("rolled over face down", true, false, true, true)
	var dry := await _case("lying outside the fountain", true, false, false, false)
	check(full.begins_with("6/6") and full.contains("emote=nil"), "fish in hand as they step in, lie face up, stand: whole again (%s)" % full)
	check(none.begins_with("2/"), "without the fish, still wounded (%s)" % none)
	check(late.begins_with("2/"), "fish taken out only once in the water: still wounded (%s)" % late)
	check(belly.begins_with("2/"), "rolled over face down before standing: still wounded (%s)" % belly)
	check(dry.begins_with("2/"), "lying down outside the fountain: still wounded (%s)" % dry)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
