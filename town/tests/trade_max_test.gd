# The swap desk sends a balance with every token it shelves, which is what Max fills from.
#
#   godot --headless --path . -s res://tests/trade_max_test.gd
#
# Sends nothing. PLSX is checked as well as PLS: the wallet's own `tokens` list holds the
# town's tokens only, so a PulseX token's balance can only come off the desk.
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
	# 50s: the balances land with the wallet's first pass over the chain.
	if phase == 0 and t > 50.0:
		phase = 1
		world.run_client_chunk("max", """
local rs = game:GetService("ReplicatedStorage")
local remote = rs:WaitForChild("TradeRemote", 25)
if not remote then print("MAX no TradeRemote") return end
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("MAX %-52s %-14s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end
local done = false
remote.OnClientEvent:Connect(function(kind, payload)
	if kind ~= "market" or done then return end
	if payload and payload.loading then return end
	done = true
	local byName = {}
	for _, token in ipairs(payload.tokens or {}) do byName[token.symbol] = token end
	local pls, plsx = byName.PLS, byName.PLSX
	check("the list reaches the panel", #(payload.tokens or {}) > 0, true)
	check("PLS is on it", pls ~= nil, true)
	check("with a balance to read", pls ~= nil and pls.balance ~= nil and pls.balance ~= "", true)
	check("and the units behind it", pls ~= nil and pls.balance_units ~= nil and pls.balance_units ~= "", true)
	check("PLSX carries its balance too", plsx ~= nil and plsx.balance_units ~= nil and plsx.balance_units ~= "", true)
	if pls then print(("MAX PLS %s (%s units), PLSX %s"):format(tostring(pls.balance),
		tostring(pls.balance_units), plsx and tostring(plsx.balance) or "-")) end
	print(("MAX %d passed, %d failed"):format(ok, bad))
end)
remote:FireServer("open")
task.wait(25)
if not done then print("MAX the desk never sent a shelf of tokens") print("MAX 0 passed, 1 failed") end
""")
	elif phase == 1 and t > 85.0:
		var failed := 0
		var seen := false
		for l in said:
			if l.begins_with("MAX"):
				print("   ", l)
				seen = true
				if l.contains("WRONG") or l.contains("never sent"):
					failed += 1
		print("trade max: %s" % ("PASS" if failed == 0 and seen else "FAIL"))
		quit(0 if failed == 0 and seen else 1)
	return false
