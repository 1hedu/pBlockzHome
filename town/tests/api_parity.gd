# Writes PARITY.md: every class and member Roblox documents that a script here cannot reach.
#
#   python scripts/roblox-api-reference.py        (refreshes scripts/roblox-api.json from Roblox's docs)
#   godot --headless --path . -s res://tests/api_parity.gd
#
# A class is present when the runtime declares it (get_class_members). A member is present when a
# Luau script reads it: the generator makes one instance of each class (a recipe in PROBE for what
# game:GetService and Instance.new cannot give -- game itself, UserSettings(), the joined Player, its
# Mouse and folders, a Tween... -- else game:GetService, else Instance.new, else the same lookup on the
# first descendant it can make) and runs pcall(function() return inst[name] end); the member is absent
# only when the error says it is not a valid member, so a read that fails for a missing capability
# still counts. A class none of these ways makes is measured by its declared members
# (get_class_members, which leaves out Hidden props).
#
# Deprecated members are counted apart from the rest: Roblox still runs most of them.
extends SceneTree

const REFERENCE := "res://../../../scripts/roblox-api.json"
const OUT := "res://../../../PARITY.md"

# The Luau side. P is every documented class with its superclass, the tree a descendant is found
# through; K is {class, {member names}} per class the runtime declares. One line per class the
# runtime declares: "PARITY <class> <class it was read on> <one 0/1 per name>", or "PARITY <class> - "
# when obtain() finds no recipe, service or Instance.new for it or a descendant; PARITY_DONE last.
const PROBE := """
local P = %s
local K = %s
local kids = {}
for _, e in ipairs(P) do
	if e[2] ~= "" then kids[e[2]] = kids[e[2]] or {} table.insert(kids[e[2]], e[1]) end
end
local function player() return game:GetService("Players"):GetPlayers()[1] end
local function ofPlayer(cls) return function() return player():FindFirstChildOfClass(cls) end end
local recipes = {
	DataModel = function() return game end,
	ServiceProvider = function() return game end,
	GenericSettings = function() return UserSettings() end,
	UserSettings = function() return UserSettings() end,
	UserGameSettings = function() return UserSettings():GetService("UserGameSettings") end,
	Player = player,
	Mouse = function() return player():GetMouse() end,
	PlayerGui = ofPlayer("PlayerGui"), Backpack = ofPlayer("Backpack"), PlayerScripts = ofPlayer("PlayerScripts"), StarterGear = ofPlayer("StarterGear"),
	StarterPlayerScripts = function() return game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterPlayerScripts") end,
	StarterCharacterScripts = function() return game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterCharacterScripts") end,
	Terrain = function() return workspace.Terrain end,
	Tween = function() return game:GetService("TweenService"):Create(Instance.new("Part"), TweenInfo.new(1), { Transparency = 1 }) end,
	AnimationTrack = function() return Instance.new("Animator"):LoadAnimation(Instance.new("Animation")) end,
	Path = function() return game:GetService("PathfindingService"):CreatePath() end,
	DataStore = function() return game:GetService("DataStoreService"):GetDataStore("parity") end,
	OrderedDataStore = function() return game:GetService("DataStoreService"):GetOrderedDataStore("parity") end,
	GlobalDataStore = function() return game:GetService("DataStoreService"):GetGlobalDataStore() end,
}
local function direct(cls)
	local ok, inst
	if recipes[cls] then ok, inst = pcall(recipes[cls]) if ok and inst then return inst end end
	ok, inst = pcall(function() return game:GetService(cls) end)
	if ok and inst then return inst end
	ok, inst = pcall(Instance.new, cls)
	if ok and inst then return inst end
	return nil
end
-- The class itself, else the first descendant (breadth first, alphabetical) that can be made.
local made = {}
local function obtain(cls)
	if made[cls] ~= nil then return made[cls] or nil end
	local inst = nil
	local queue, i = { cls }, 1
	while queue[i] and not inst do
		local c = queue[i]
		inst = direct(c)
		if inst then
			local ok, isa = pcall(function() return inst:IsA(cls) end)
			if not ok or not isa then inst = nil end
		end
		for _, k in ipairs(kids[c] or {}) do table.insert(queue, k) end
		i += 1
	end
	made[cls] = inst or false
	return inst
end
for _, e in ipairs(K) do
	local cls, names = e[1], e[2]
	local inst = obtain(cls)
	if inst then
		local bits = table.create(#names)
		for j, n in ipairs(names) do
			local ok, err = pcall(function() return inst[n] end)
			bits[j] = (ok or not string.find(tostring(err), "is not a valid member", 1, true)) and "1" or "0"
		end
		print("PARITY " .. cls .. " " .. inst.ClassName .. " " .. table.concat(bits))
	else
		print("PARITY " .. cls .. " - ")
	end
end
print("PARITY_DONE")
"""

const KINDS := ["properties", "methods", "events", "callbacks"]

var said: Array[String] = []
var errors: Array[String] = []

# Roblox's YAML quotes one name with a trailing space ('StarterPlayer.LoadCharacterLayeredClothing ')
# and scripts/roblox-api-reference.py keeps the quote: strip quotes and blanks from both ends.
static func clean_name(n: String) -> String:
	return n.strip_edges().trim_prefix("'").trim_suffix("'").trim_prefix("\"").trim_suffix("\"").strip_edges()

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(REFERENCE))
	var api = JSON.parse_string(text)
	if typeof(api) != TYPE_DICTIONARY:
		printerr("no reference at ", REFERENCE, " -- run scripts/roblox-api-reference.py")
		quit(1)
		return
	_run(api)

func _run(api: Dictionary) -> void:
	var identifier := RegEx.new()
	identifier.compile("^[A-Za-z_][A-Za-z0-9_]*$")
	var names: Array = api.keys()
	names.sort()

	# Names a Luau script could not index with a dot are left out, counted per class.
	var left_out := {}                  # class -> count
	var left_out_total := 0
	var declared := {}                  # class -> {kind -> PackedStringArray}, empty when the runtime lacks the class
	var world := PulseBlockzWorld.new()
	for cls in names:
		var ref: Dictionary = api[cls]
		for kind in KINDS:
			var kept := []
			for m in ref[kind]:
				var n: String = clean_name(m["name"])
				if identifier.search(n) == null:
					left_out[cls] = left_out.get(cls, 0) + 1
					left_out_total += 1
					continue
				var copy: Dictionary = m.duplicate()
				copy["name"] = n
				kept.append(copy)
			ref[kind] = kept
		declared[cls] = world.get_class_members(cls)

	# One instance of every class the runtime declares, read from Luau.
	var probe_names := {}               # class -> [member names], the order the bits come back in
	var tree := PackedStringArray()
	var entries := PackedStringArray()
	for cls in names:
		var parent = api[cls]["inherits"]
		tree.append("{\"%s\",\"%s\"}" % [cls, parent if parent != null else ""])
		if declared[cls].is_empty(): continue
		var list := PackedStringArray()
		for kind in KINDS:
			for m in api[cls][kind]: list.append(m["name"])
		probe_names[cls] = list
		var quoted := PackedStringArray()
		for n in list: quoted.append("\"%s\"" % n)
		entries.append("{\"%s\",{%s}}" % [cls, ",".join(quoted)])
	var source := PROBE % ["{\n" + ",\n".join(tree) + "\n}", "{\n" + ",\n".join(entries) + "\n}"]

	world.mode = PulseBlockzWorld.MODE_SERVER
	world.max_millis_per_call = 60000.0
	world.max_steps = 0
	world.max_memory_mb = 64
	get_root().add_child(world)
	world.script_print.connect(func(_n, t): said.append(t))
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_killed.connect(func(n, e): errors.append("%s killed: %s" % [n, e]))
	await process_frame
	world.add_player("Parity", 1)       # a headless Player: Player, Mouse, PlayerGui, Backpack come from it
	world.run_chunk("api_parity", source)
	var waited := 0.0
	while not said.has("PARITY_DONE") and waited < 180.0:
		await create_timer(0.1).timeout
		waited += 0.1
	for e in errors: printerr(e)
	if not said.has("PARITY_DONE"):
		printerr("the probe never finished")
		quit(1)
		return
	var read_on := {}                   # class -> the ClassName it was read on, or "-"
	var bits := {}                      # class -> "0101..."
	for line in said:
		if not line.begins_with("PARITY "): continue
		var parts: PackedStringArray = line.split(" ")
		if parts.size() < 4: continue
		read_on[parts[1]] = parts[2]
		bits[parts[1]] = parts[3]

	var missing_classes: Array[String] = []
	var by_declaration: Array[String] = []
	var by_class := {}                  # class -> {kind -> [names]}
	var deprecated_by_class := {}
	var totals := {"properties": [0, 0], "methods": [0, 0], "events": [0, 0], "callbacks": [0, 0]}   # [have, of]
	var dep_missing := 0
	var class_have := 0

	for cls in names:
		var ref: Dictionary = api[cls]
		var have: Dictionary = declared[cls]
		if have.is_empty():
			missing_classes.append(cls)
			for kind in totals:
				for m in ref[kind]:
					if not m["deprecated"]: totals[kind][1] += 1
			continue
		class_have += 1
		var probed: bool = read_on.get(cls, "-") != "-" and bits[cls].length() == probe_names[cls].size()
		if not probed: by_declaration.append(cls)
		var lookup := {}
		for kind in KINDS: lookup[kind] = have.get(kind, PackedStringArray())
		var at := 0
		for kind in KINDS:
			for m in ref[kind]:
				var n: String = m["name"]
				var present: bool
				if probed:
					present = bits[cls][at] == "1"
				else:
					present = lookup[kind].has(n)
					# The runtime answers Roblox's old lowercase spellings (obj:findFirstChild) by
					# capitalising the first letter, and nothing beyond that.
					if not present and n.length() > 0 and n[0] >= "a" and n[0] <= "z":
						present = lookup[kind].has(n[0].to_upper() + n.substr(1)) or (n == "cframe" and lookup[kind].has("CFrame"))
				at += 1
				if m["deprecated"]:
					if not present:
						dep_missing += 1
						if not deprecated_by_class.has(cls): deprecated_by_class[cls] = []
						deprecated_by_class[cls].append("%s (%s)" % [n, kind.trim_suffix("s")])
					continue
				totals[kind][1] += 1
				if present:
					totals[kind][0] += 1
				else:
					if not by_class.has(cls): by_class[cls] = {}
					if not by_class[cls].has(kind): by_class[cls][kind] = []
					by_class[cls][kind].append(n)

	var lines := PackedStringArray()
	lines.append("# Parity with Roblox's engine API")
	lines.append("")
	lines.append("Generated by `luau/gdextension/demo2/tests/api_parity.gd` from `scripts/roblox-api.json` (Roblox/creator-docs,")
	lines.append("class reference). Every entry below is something Roblox has that a script here cannot reach -- which")
	lines.append("makes it a job, not a note. A class is present when the runtime declares it. A member is present when a")
	lines.append("Luau script reads it: the generator makes one instance of each class (`game:GetService`, `Instance.new`, or a")
	lines.append("recipe: `game` itself, `UserSettings()`, the joined Player, its Mouse and its PlayerGui / Backpack /")
	lines.append("PlayerScripts / StarterGear, StarterPlayer's script folders, `workspace.Terrain`, a Tween, an AnimationTrack,")
	lines.append("a Path, a data store; else the same lookup on the first descendant it can make -- BasePart is read on %s," % read_on.get("BasePart", "a descendant"))
	lines.append("WorldRoot on %s) and runs `pcall(function() return inst[name] end)`; the member is absent only when" % read_on.get("WorldRoot", "Workspace"))
	lines.append("the error says it is not a valid member, so a read that fails for a missing capability still counts.")
	lines.append("%d classes none of these ways makes (no recipe, service or `Instance.new` for them or a descendant) are" % by_declaration.size())
	lines.append("measured by their declared members instead, Hidden ones excluded (listed below). A present member that does nothing is")
	lines.append("`scripts/parity-audit.py`'s to find.")
	lines.append("")
	lines.append("| | kit has | Roblox documents | missing |")
	lines.append("|---|---:|---:|---:|")
	lines.append("| classes | %d | %d | %d |" % [class_have, names.size(), missing_classes.size()])
	for kind in KINDS:
		lines.append("| %s (not deprecated) | %d | %d | %d |" % [kind, totals[kind][0], totals[kind][1], totals[kind][1] - totals[kind][0]])
	lines.append("| deprecated members missing, on classes the kit has | | | %d |" % dep_missing)
	lines.append("")
	var left_out_parts := PackedStringArray()
	var left_out_classes: Array = left_out.keys()
	left_out_classes.sort()
	for cls in left_out_classes: left_out_parts.append("%s %d" % [cls, left_out[cls]])
	lines.append("Not counted: %d documented names that are not identifiers (%s)." % [left_out_total, ", ".join(left_out_parts)])
	lines.append("")
	lines.append("## Classes the kit does not have (%d)" % missing_classes.size())
	lines.append("")
	lines.append(", ".join(missing_classes))
	lines.append("")
	lines.append("## Classes measured by their declared members (%d)" % by_declaration.size())
	lines.append("")
	lines.append(", ".join(by_declaration))
	lines.append("")
	lines.append("## Members missing from classes the kit has")
	lines.append("")
	var gap_classes: Array = by_class.keys()
	gap_classes.sort()
	for cls in gap_classes:
		var parts := PackedStringArray()
		for kind in KINDS:
			if by_class[cls].has(kind):
				parts.append("%s: %s" % [kind, ", ".join(by_class[cls][kind])])
		var on: String = read_on.get(cls, "-")
		var how: String = " (by declaration)" if on == "-" else (" (read on %s)" % on if on != cls else "")
		lines.append("- **%s**%s -- %s" % [cls, how, "; ".join(parts)])
	lines.append("")
	lines.append("## Deprecated members missing (Roblox still runs most of these)")
	lines.append("")
	var dep_classes: Array = deprecated_by_class.keys()
	dep_classes.sort()
	for cls in dep_classes:
		lines.append("- **%s** -- %s" % [cls, ", ".join(deprecated_by_class[cls])])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()

	print("classes: kit %d of %d (%d missing)" % [class_have, names.size(), missing_classes.size()])
	for kind in KINDS:
		print("%s: %d of %d (%d missing)" % [kind, totals[kind][0], totals[kind][1], totals[kind][1] - totals[kind][0]])
	print("deprecated members missing on present classes: %d" % dep_missing)
	print("read from Luau: %d classes; by declaration: %d; names left out: %d" % [class_have - by_declaration.size(), by_declaration.size(), left_out_total])
	print("written to PARITY.md")
	quit(0)
