# The teller can send any of what you hold, not only PLS.
#
#   godot --headless --path . -s res://tests/bank_send_test.gd
#
# The menu is the trading house's list -- the tokens the town ships with plus any this player
# pasted in by address, read on their own machine. Nothing is signed: this stops before the prompt.
extends SceneTree

const Arrive = preload("res://tests/Arrive.gd")
var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var said: Array[String] = []

func _initialize() -> void:
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	root.add_child(main)
	Arrive.now(world)
	world.script_print.connect(func(_n, s): said.append(String(s)))
	world.script_error.connect(func(n, s): print("ERR %s: %s" % [n, s]))

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 50.0:
		phase = 1
		world.run_client_chunk("bank", """
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("BankRemote", 25)
if not remote then print("BANK no BankRemote") return end
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("BANK %-52s %-12s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end
-- Somebody else's address, which is never signed for: this stops before the prompt.
local THEM = "0x000000000000000000000000000000000000dEaD"
local step, menu, input = nil, nil, nil
remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "say" or kind == "open" then
		step = payload
		menu = payload and payload.menu
		input = payload and payload.input
	end
end)
local function waitForStep()
	step = nil
	local waited = 0
	while step == nil and waited < 12 do task.wait(0.25) waited += 0.25 end
	return step
end

remote:FireServer("ask_send", nil, "")
waitForStep()
remote:FireServer("send_to", nil, THEM)
waitForStep()
-- The token menu: every holding, by symbol, before any amount is asked for.
local offered, sawPls, sawPlsx = 0, false, false
for _, item in ipairs(menu or {}) do
	if item.id == "send_token" then
		offered += 1
		if item.label:find("PLS ") or item.label:match("^PLS%s") then sawPls = true end
		if item.label:match("^PLSX") then sawPlsx = true end
		print("BANK offered: " .. tostring(item.label))
	end
end
check("the teller asks which, not how much PLS", offered > 0, true)
check("PLS is one of them", sawPls, true)
check("and so is a token that is not PLS", sawPlsx, true)
check("no amount box until a token is chosen", input == nil, true)

-- Choose the one that is not the native coin, then the amount box should name it.
local plsx = nil
for _, item in ipairs(menu or {}) do
	if item.id == "send_token" and item.label:match("^PLSX") then plsx = item end
end
if plsx then
	remote:FireServer("send_token", plsx.arg, "")
	waitForStep()
	check("choosing one asks how much of THAT", input ~= nil and tostring(input.placeholder):find("PLSX") ~= nil, true)
	-- More than is held is turned down here rather than at the wallet.
	remote:FireServer("send", nil, "999999999999")
	waitForStep()
	local line = step and step.lines and step.lines[1] or ""
	check("more than you hold is refused before signing", tostring(line):find("more than that") ~= nil, true)
end
print(("BANK %d passed, %d failed"):format(ok, bad))
""")
	elif phase == 1 and t > 78.0:
		var failed := 0
		var seen := false
		for l in said:
			if l.begins_with("BANK"):
				print("   ", l)
				seen = true
				if l.contains("WRONG"):
					failed += 1
		print("bank send: %s" % ("PASS" if failed == 0 and seen else "FAIL"))
		quit(0 if failed == 0 and seen else 1)
	return false
