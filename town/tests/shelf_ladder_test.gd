# The shelf only offers what the chain will hand over: Inventory.add reverts NotBigEnough when
# the buyer's balance is below the rung an item sits on, and the bottom rung costs 5 PLS. Which
# half of the rule this run checks depends on what the wallet it plays as holds.
#
#   godot --headless --path . -s res://tests/shelf_ladder_test.gd
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
	# 50s: the catalogue and the wallet's balance both have to arrive from the chain first.
	if phase == 0 and t > 50.0:
		phase = 1
		world.run_chunk("ladder", """
local Players = game:GetService("Players")
local rs = game:GetService("ReplicatedStorage")
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local Units = require(rs:WaitForChild("Units"))
local ok, bad = 0, 0
local function check(what, got, want)
	if got == want then ok += 1 else bad += 1 end
	print(("LADDER %-46s %-22s (wanted %s)%s"):format(what, tostring(got), tostring(want),
		got == want and "" or "   <-- WRONG"))
end
local player = Players:GetPlayers()[1]
local d = player and Ledger.data(player)
if not d or Ledger.loading(d) then
	print("LADDER the ledger never finished reading the chain")
	print("LADDER 0 passed, 1 failed")
	return
end
local holder = d.holder or {}
local held = tostring(d.gas_wei or "0")
-- The bottom rung's price, read off the same ladder the contract publishes.
local bottom = nil
for _, l in ipairs(d.listings or {}) do if l.tier == 0 then bottom = l break end end
local below = Units.lessThan(held, "5000000000000000000")
print(("LADDER holding %s wei, %s the bottom rung"):format(held, below and "below" or "on or above"))
if below then
	check("no rung when you hold less than the first costs", holder.tier, -1)
	check("and no rung name to print", holder.name, "")
	check("the next rung up is the bottom one", holder.next, "Common")
	local offered = 0
	for _, l in ipairs(d.listings or {}) do if not l.locked then offered += 1 end end
	check("nothing at all is offered", offered, 0)
else
	check("a rung you are on has a number", holder.tier >= 0, true)
	check("and a name", holder.name ~= "", true)
	if bottom then check("the bottom rung is not locked to you", bottom.locked, false) end
end
print(("LADDER %d passed, %d failed"):format(ok, bad))
""")
	elif phase == 1 and t > 62.0:
		var failed := 0
		for l in said:
			if l.begins_with("LADDER"):
				print("   ", l)
				if l.contains("WRONG") or l.contains("never finished"):
					failed += 1
		print("shelf ladder: %s" % ("PASS" if failed == 0 and said.size() > 0 else "FAIL"))
		quit(0 if failed == 0 else 1)
	return false
