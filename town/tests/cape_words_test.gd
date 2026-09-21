# Mixed palette colours and words stamped in the Reactor7 glyphs (shared/Glyphs.luau), from
# the drawing table through the stored cape picture to the tailor.
#
#   godot --headless --path . -s res://tests/cape_words_test.gd
extends SceneTree

var world: PulseBlockzWorld
var t := 0.0
var phase := 0
var passed := 0
var failed := 0
var said: Array[String] = []
var errors: Array[String] = []

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _said(prefix: String) -> String:
	for i in range(said.size() - 1, -1, -1):
		if said[i].begins_with(prefix): return said[i].substr(prefix.length())
	return ""

func _initialize() -> void:
	OS.set_environment("PBLOCKZ_NO_DEV_KEY", "1")
	var main: Node = load("res://Main.tscn").instantiate()
	main.show_title = false
	world = main.get_node("World")
	world.data_store_path = ""
	main.get_node("Wallet").auto_start = false
	world.script_error.connect(func(n, e): errors.append("[%s] %s" % [n, e]); printerr("    LUA ERROR [%s] %s" % [n, e]))
	world.script_print.connect(func(_n, line): said.append(line))
	root.add_child(main)
	print("mixed colours and words on a cape")

func _process(delta: float) -> bool:
	t += delta
	if phase == 0 and t > 10.0:
		phase = 1
		world.run_chunk("picture", """
local rs = game:GetService("ReplicatedStorage")
local Paint, Cape, Glyphs = require(rs.Paint), require(rs.Cape), require(rs.Glyphs)
-- Slot 2 mixed to 12 34 56; everything else as the fixed palette has it.
local hex = ""
for i, c in ipairs(Paint.PALETTE) do
	hex ..= (i == 2) and "123456" or string.format("%02x%02x%02x", c[1], c[2], c[3])
end
local palette = assert(Paint.parsePalette(hex))
local indices = string.rep("1", Paint.W * Paint.H)
local words = assert(Paint.checkText({ text = "PLS", x = 8, y = 20, colour = 4, scale = 2 }))
local px, w, h = Cape.emblemPixels(indices, palette, words)
local function at(x, y) local o = (y * w + x) * 4 return ("%02x%02x%02x"):format(px[o + 1], px[o + 2], px[o + 3]) end
print("MIXED " .. at(w - 1, h - 1))
local ink = 0
for _, ch in ipairs({ "P", "L", "S" }) do
	for _, row in ipairs(Glyphs.set[ch].rows) do
		for c = 1, #row do if row:sub(c, c) == "#" then ink += 1 end end
	end
end
local red = palette[5]
local want = ("%02x%02x%02x"):format(red[1], red[2], red[3])
local stamped = 0
for y = 0, h - 1 do for x = 0, w - 1 do if at(x, y) == want then stamped += 1 end end end
print("INK " .. ink * 4 .. " " .. stamped)
local plain = Cape.emblemPixels(indices, palette, nil)
local same = true
for i = 1, #plain do if plain[i] ~= px[i] and (px[i] ~= red[1] and px[i] ~= red[2] and px[i] ~= red[3]) then same = false break end end
print("ONLYWORDS " .. tostring(same))
local tw, th = Glyphs.measure("PLS", 2)
print("MEASURE " .. tw .. " " .. th)

local long = Paint.checkText({ text = string.rep("A", 40), x = 0, y = 0, colour = 1, scale = 1 })
local _, eraser = Paint.checkText({ text = "hi", x = 0, y = 0, colour = 0, scale = 1 })
local tidy = Paint.checkText({ text = "a\\tb\\1c", x = 0, y = 0, colour = 3, scale = 9 })
local blank = Paint.checkText({ text = "   ", x = 0, y = 0, colour = 3, scale = 1 })
local _, badPalette = Paint.parsePalette("xyz")
print("RULES " .. #long.text .. "|" .. tostring(eraser) .. "|" .. tidy.text .. "|" .. tidy.scale .. "|" .. tostring(blank) .. "|" .. tostring(badPalette))
""")
	elif phase == 1 and t > 11.0:
		phase = 2
		world.run_chunk("open", """
local rs = game:GetService("ReplicatedStorage")
local Paint = require(rs.Paint)
rs.TailorRemote:FireClient(game:GetService("Players"):GetPlayers()[1], "paint", { w = Paint.W, h = Paint.H, palette = Paint.PALETTE })
""")
	elif phase == 2 and t > 13.0:
		phase = 3
		world.run_client_chunk("table", """
local gui = game:GetService("Players").LocalPlayer.PlayerGui
local tbl = gui:WaitForChild("PaintTable")
local window, swatches, mix, box = nil, {}, nil, nil
for _, d in ipairs(tbl:GetDescendants()) do
	if d:IsA("TextButton") and d.Parent:FindFirstChildOfClass("UIGridLayout") then table.insert(swatches, d) end
	if d:IsA("TextButton") and d.Text == "Mix..." then mix = d end
	if d:IsA("TextBox") and d.PlaceholderText == "words on the cape" then box = d end
	if d:IsA("Frame") and d.Name == "Content" and not window then window = d end
end
local bottom = window.AbsolutePosition.Y + window.AbsoluteSize.Y
local inside, under = 0, false
local function overlaps(a, b)
	local ap, as, bp, bs = a.AbsolutePosition, a.AbsoluteSize, b.AbsolutePosition, b.AbsoluteSize
	return ap.X < bp.X + bs.X and bp.X < ap.X + as.X and ap.Y < bp.Y + bs.Y and bp.Y < ap.Y + as.Y
end
for _, s in ipairs(swatches) do
	if s.AbsolutePosition.Y + s.AbsoluteSize.Y <= bottom and s.AbsoluteSize.X > 0 then inside += 1 end
	if mix and overlaps(s, mix) then under = true end
end
print("SWATCHES " .. #swatches .. " " .. inside .. " " .. tostring(mix ~= nil) .. " " .. tostring(under))
box.Text = "PULSE"
task.wait(0.3)
print("TYPED " .. tostring(box.Text))
""")
	elif phase == 3 and t > 15.0:
		phase = 4
		# Three publishes: words in the eraser's colour, a palette that is not hex, then a good one.
		world.run_client_chunk("publish", """
local rs = game:GetService("ReplicatedStorage")
local Paint = require(rs.Paint)
local remote = rs.TailorRemote
remote.OnClientEvent:Connect(function(kind, payload)
	if kind == "say" and type(payload) == "table" then print("TAILOR " .. table.concat(payload.lines or {}, " | ")) end
end)
local hex = ""
for i, c in ipairs(Paint.PALETTE) do hex ..= string.format("%02x%02x%02x", c[1], c[2], c[3]) end
local drawing = string.rep("2", Paint.W * Paint.H)
remote:FireServer("publish", drawing, "Words", hex, { text = "Hi", x = 0, y = 0, colour = 0, scale = 1 })
task.wait(0.5)
remote:FireServer("publish", drawing, "Words", "nope", nil)
task.wait(0.5)
remote:FireServer("publish", drawing, "Words", hex, { text = "Hi", x = 4, y = 4, colour = 3, scale = 2 })
""")
	elif phase == 4 and t > 19.0:
		phase = 5
		_verdict()
	return false

func _verdict() -> void:
	check(_said("MIXED ") == "123456", "a mixed colour is what the stored picture is painted in: %s" % _said("MIXED "))
	# Block-scaled, no antialiasing: one ink cell becomes scale x scale pixels, so scale 2 wants ink * 4.
	var ink := _said("INK ").split(" ")
	check(ink.size() == 2 and ink[0] == ink[1] and int(ink[0]) > 0,
		"the words are stamped with exactly the glyphs' ink at twice the size: %s" % _said("INK "))
	check(_said("ONLYWORDS ") == "true", "and nothing but the words changed")
	check(_said("MEASURE ").begins_with("") and int(_said("MEASURE ").split(" ")[1]) == 24, "a line at 2x is 24 pixels tall: %s" % _said("MEASURE "))
	var rules := _said("RULES ").split("|")
	print("    rules: ", _said("RULES "))
	check(rules.size() == 6 and rules[0] == "24", "words are cut at 24 characters")
	check(rules.size() == 6 and rules[1].contains("not the eraser"), "words in the eraser's colour are refused")
	check(rules.size() == 6 and rules[2] == "abc", "unprintable characters are dropped")
	check(rules.size() == 6 and rules[3] == "3", "the size is held to 3x at most")
	check(rules.size() == 6 and rules[4] == "nil", "blank words are no words")
	check(rules.size() == 6 and rules[5].contains("not a palette"), "a palette that is not one is refused")
	var sw := _said("SWATCHES ").split(" ")
	print("    swatches: ", _said("SWATCHES "))
	check(sw.size() == 4 and sw[0] == "16" and sw[1] == "16", "all sixteen colours are inside the window")
	check(sw.size() == 4 and sw[2] == "true" and sw[3] == "false", "and Mix... is there, under none of them")
	check(_said("TYPED ") == "PULSE", "typing words on the table draws them")
	var tailor := PackedStringArray()
	for line in said:
		if line.begins_with("TAILOR "): tailor.append(line.substr(7))
	print("    tailor said: ", " / ".join(tailor))
	check(tailor.size() >= 1 and tailor[0].contains("not the eraser"), "the tailor turns away words in the eraser's colour")
	check(tailor.size() >= 2 and tailor[1].contains("not a palette"), "and a palette that is not one")
	check(tailor.size() >= 3 and tailor[2].contains("Off it goes"), "and takes a drawing with mixed colours and words")
	check(errors.is_empty(), "no script errors: %s" % " ; ".join(errors))
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
