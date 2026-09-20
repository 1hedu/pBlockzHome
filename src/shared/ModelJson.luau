-- A model described the way a published one is -- className, name, properties, children -- built
-- into real Instances here, with no round trip through the chain.
--
-- The host mounts a published model from exactly this shape (world.add_model). The town's own
-- models -- the Engram badge, the fish, the rod -- are described the same way and built by this, so
-- one description could be published unchanged and nothing about how it is worn would move.
local ModelJson = {}

local function valueOf(v)
	if type(v) == "table" then
		if v.Color3uint8 then
			local c = v.Color3uint8
			return Color3.fromRGB(c[1], c[2], c[3])
		end
		if #v == 3 then return Vector3.new(v[1], v[2], v[3]) end
	end
	return v
end

local function applyTo(inst, properties)
	for key, raw in pairs(properties or {}) do
		if key == "Material" and type(raw) == "string" then
			inst.Material = Enum.Material[raw]
		elseif key == "Shape" and type(raw) == "string" then
			inst.Shape = Enum.PartType[raw]
		elseif key == "MeshType" and type(raw) == "string" then
			inst.MeshType = Enum.MeshType[raw]
		elseif key ~= "Part0" and key ~= "Part1" then
			inst[key] = valueOf(raw)
		end
	end
end

local function buildInto(node, parent, byName)
	local inst = Instance.new(node.className)
	if node.name then inst.Name = node.name end
	applyTo(inst, node.properties)
	inst.Parent = parent
	if node.name then byName[node.name] = inst end
	for _, child in ipairs(node.children or {}) do
		buildInto(child, inst, byName)
	end
	return inst
end

--- The description, as Instances. Welds are joined last, once every part is where it goes, so each
--- one holds the offset the description gave it.
function ModelJson.build(desc)
	local byName = {}
	local root = buildInto(desc, nil, byName)
	local function join(node)
		if node.className == "WeldConstraint" and node.properties then
			local weld = byName[node.name]
			if weld then
				weld.Part0 = byName[tostring(node.properties.Part0)]
				weld.Part1 = byName[tostring(node.properties.Part1)]
			end
		end
		for _, child in ipairs(node.children or {}) do join(child) end
	end
	join(desc)
	return root
end

--- A part, in worn space, the way scripts/catalogue.js writes one.
function ModelJson.part(name, pos, size, opts)
	opts = opts or {}
	local props = {
		Position = pos, Size = size,
		Material = opts.material or "SmoothPlastic",
		Color = { Color3uint8 = opts.color or { 200, 200, 200 } },
		CanCollide = false, Massless = true,
	}
	if opts.shape then props.Shape = opts.shape end
	if opts.orientation then props.Orientation = opts.orientation end
	if opts.reflectance then props.Reflectance = opts.reflectance end
	if opts.transparency then props.Transparency = opts.transparency end
	return { className = "Part", name = name, properties = props, children = opts.children }
end

--- An Accessory out of parts, the way scripts/catalogue.js's accessory() makes one: the first part is
--- the Handle, carrying the Attachment it hangs from, and the rest are welded to it. A turned first
--- part cannot be the Handle -- a worn Handle's own turn is discarded and would cancel its siblings'
--- -- so a speck goes in front of it to be the Handle instead.
function ModelJson.accessory(name, attachment, parts)
	if parts[1].properties.Orientation then
		local at = parts[1].properties.Position
		table.insert(parts, 1, ModelJson.part("Anchor", at, { 0.05, 0.05, 0.05 }, { transparency = 1 }))
	end
	local handle = parts[1]
	local at = handle.properties.Position
	local handleChildren = { { className = "Attachment", name = attachment,
		properties = { Position = { -at[1], -at[2], -at[3] } } } }
	for _, c in ipairs(handle.children or {}) do table.insert(handleChildren, c) end
	local children = { { className = "Part", name = "Handle", properties = handle.properties, children = handleChildren } }
	for i = 2, #parts do table.insert(children, parts[i]) end
	for i = 2, #parts do
		table.insert(children, { className = "WeldConstraint", name = parts[i].name .. "Weld",
			properties = { Part0 = "Handle", Part1 = parts[i].name } })
	end
	return { className = "Accessory", name = name, properties = { Name = name }, children = children }
end

return ModelJson
