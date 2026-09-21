# GeometryService:CalculateConstraintsToPreserve, record by record, against what the Roblox
# reference says it returns for each WeldConstraintPreserve setting.
#
#   godot --headless --path . -s res://tests/solid_constraints_test.gd
extends SceneTree

var world: PulseBlockzWorld
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []
var t := 0.0
var phase := 0

const SCRIPT := """
local GeometryService = game:GetService("GeometryService")
local CollectionService = game:GetService("CollectionService")
local function say(k, v) print("C " .. k .. " " .. tostring(v)) end
local function part(size, at)
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = CFrame.new(at)
	p.Anchored = true
	p.Parent = workspace
	return p
end
local function attach(to, at, name)
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = at
	a.Parent = to
	return a
end

local bar = part(Vector3.new(6, 1, 1), Vector3.new(0, 120, 0))
local above = part(Vector3.new(1, 1, 1), Vector3.new(-2.5, 121, 0))     -- sits on the long piece
local far = part(Vector3.new(1, 1, 1), Vector3.new(20, 120, 0))

local hingeAt = attach(bar, Vector3.new(-2.5, 0.5, 0), "HingeAt")
local aboveAt = attach(above, Vector3.new(0, -0.5, 0), "AboveAt")
local hinge = Instance.new("HingeConstraint")
hinge.Attachment0 = hingeAt
hinge.Attachment1 = aboveAt
hinge.Parent = bar

local lonely = attach(bar, Vector3.new(2.5, 0.5, 0), "Lonely")

local goneAt = attach(bar, Vector3.new(1, 0.5, 0), "GoneAt")                -- on the top face, where the cut is
local rope = Instance.new("RopeConstraint")
rope.Attachment0 = goneAt
rope.Attachment1 = aboveAt
rope.Parent = bar

local weldAbove = Instance.new("WeldConstraint")
weldAbove.Part0 = bar
weldAbove.Part1 = above
weldAbove.Parent = bar
local weldFar = Instance.new("WeldConstraint")
weldFar.Part0 = far
weldFar.Part1 = bar
weldFar.Parent = far
local noCollide = Instance.new("NoCollisionConstraint")
noCollide.Part0 = bar
noCollide.Part1 = far
noCollide.Parent = bar

-- Off-centre, so the pieces are 3.5 and 1.5 long.
local cutter = part(Vector3.new(1, 3, 3), Vector3.new(1, 120, 0))
CollectionService:AddTag(cutter, "rbxNegate")
local pieces = GeometryService:UnionAsync(bar, { cutter })
say("PIECES", #pieces)
local long, short
for _, p in ipairs(pieces) do
	if p.Size.X > 2.5 then long = p else short = p end
	p.Parent = workspace
end
say("LONGSHORT", tostring(long ~= nil) .. " " .. tostring(short ~= nil))

local function who(i)
	if i == nil then return "nil" end
	if i == long then return "long" end
	if i == short then return "short" end
	return i.Name
end

local function report(tag, options)
	local recs = GeometryService:CalculateConstraintsToPreserve(bar, pieces, options)
	local lines = {}
	for _, r in ipairs(recs) do
		if r.Attachment then
			table.insert(lines, ("att %s con=%s ap=%s cp=%s"):format(r.Attachment.Name, r.Constraint and r.Constraint.ClassName or "nil",
				who(r.AttachmentParent), who(r.ConstraintParent)))
		elseif r.WeldConstraint then
			table.insert(lines, ("weld %s p=%s 0=%s 1=%s"):format(r.WeldConstraint == weldAbove and "above" or "far",
				who(r.WeldConstraintParent), who(r.WeldConstraintPart0), who(r.WeldConstraintPart1)))
		elseif r.NoCollisionConstraint then
			table.insert(lines, ("nocollide p=%s 0=%s 1=%s"):format(who(r.NoCollisionConstraintParent),
				who(r.NoCollisionConstraintPart0), who(r.NoCollisionConstraintPart1)))
		end
	end
	table.sort(lines)
	say(tag, table.concat(lines, " | "))
end

report("ALL", { tolerance = 0.1, weldConstraintPreserve = Enum.WeldConstraintPreserve.All, dropAttachmentsWithoutConstraints = false })
report("TOUCHING", { tolerance = 0.1, weldConstraintPreserve = Enum.WeldConstraintPreserve.Touching })
report("NONE", { tolerance = 0.1, weldConstraintPreserve = Enum.WeldConstraintPreserve.None })
say("DONE", "ok")
"""

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _c(key: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		var s := String(said[i])
		if s.begins_with("C " + key + " "): return s.substr(("C " + key + " ").length())
	return ""

func _initialize() -> void:
	print("CalculateConstraintsToPreserve")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("%s: %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	get_root().add_child(main)

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 9.0:
		phase = 1; t = 0.0
		world.run_chunk("constraints", SCRIPT)
	elif phase == 1 and (_c("DONE") == "ok" or t > 30.0) and t > 1.0:
		phase = 2
		check(_c("PIECES") == "2" and _c("LONGSHORT") == "true true", "the cut leaves a long piece and a short one: %s %s" % [_c("PIECES"), _c("LONGSHORT")])
		var all := _c("ALL")
		print("    ALL: ", all)
		check(all.find("att HingeAt con=HingeConstraint ap=long cp=long") >= 0,
			"a hinge's attachment over the long piece goes to the long piece, constraint and all")
		check(all.find("att GoneAt con=RopeConstraint ap=nil cp=nil") >= 0,
			"an attachment on surface the cut removed is past tolerance: it and its rope get nil")
		check(all.find("att Lonely con=nil ap=short cp=nil") >= 0,
			"dropAttachmentsWithoutConstraints = false keeps a lone attachment, on the piece it is by")
		check(all.find("weld above p=long 0=long 1=AboveHelper") < 0 and all.find("weld above p=long 0=long 1=Part") >= 0 and all.find("weld above p=short 0=short 1=Part") >= 0,
			"WeldConstraintPreserve.All keeps a weld on every piece, the original part swapped for the piece")
		check(all.find("weld far p=long 0=Part 1=long") >= 0 and all.find("weld far p=short 0=Part 1=short") >= 0,
			"including one where the original part was Part1")
		check(all.find("nocollide p=long 0=long 1=Part") >= 0 and all.find("nocollide p=short 0=short 1=Part") >= 0,
			"NoCollisionConstraints are carried over to each piece")
		var touching := _c("TOUCHING")
		print("    TOUCHING: ", touching)
		check(touching.find("weld above p=long") >= 0 and touching.find("weld above p=short") < 0 and touching.find("weld far") < 0,
			"WeldConstraintPreserve.Touching keeps only welds between parts that touch")
		check(touching.find("att Lonely con=nil ap=nil") >= 0, "and by default a lone attachment is dropped")
		var none := _c("NONE")
		check(none.find("weld ") < 0 and none.find("att HingeAt") >= 0, "WeldConstraintPreserve.None drops every weld and nothing else")
		check(errors.is_empty(), "nothing threw: %s" % str(errors.slice(0, 3)))
		print("%d passed, %d failed" % [passed, failed])
		quit(1 if failed > 0 else 0)
	return false
