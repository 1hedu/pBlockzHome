## A player's picture of the world as the desks see it: `Ledger.data(player)` on the server,
## one per player, in the server's own memory: the town's catalogue, what the server read of that
## player's holdings, and the wallet half their machine handed over. Asynchronous -- this
## returns the last answer and asks for a fresh one, so poll it.
extends RefCounted

static var _last := {}
static var _hooked := {}

static func of(world: Object, player_index: int = 1) -> Dictionary:
	var key: int = world.get_instance_id()
	if not _hooked.has(key):
		_hooked[key] = true
		world.script_print.connect(func(_n, txt):
			var line := String(txt)
			if line.begins_with("PICTURE "):
				var parsed = JSON.parse_string(line.substr(8))
				if typeof(parsed) == TYPE_DICTIONARY:
					_last[key] = parsed)
	world.run_chunk("picture", """
local Ledger = require(game:GetService("ServerScriptService").Ledger)
local player = game:GetService("Players"):GetPlayers()[%d]
local d = player and Ledger.data(player)
if d then print("PICTURE " .. game:GetService("HttpService"):JSONEncode(d)) end
""" % player_index)
	return _last.get(key, {})
