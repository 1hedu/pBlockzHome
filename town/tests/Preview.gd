# Unpublished catalogue items, staged off disk by `node scripts/stage-preview.js all <dir>` and
# installed into ReplicatedStorage/OnChain -- the same folder the host mounts verified chain
# models into, under the same names, so a staged item overwrites the published one. An item's
# model lives in scripts/catalogue.js until it is published; StandIns.gd stands in the same way
# for a place's own blobs, sounds and meshes.
#
# The staged JSON names its files by absolute local path, hence the copy into user://preview:
# every process on the machine shares that folder, so one of them staging covers them all.
extends RefCounted

const DIR := "user://preview/catalogue"

## Copies a staged catalogue into user:// and returns its manifest's item count.
static func stage(who: String, from: String) -> int:
	DirAccess.make_dir_recursive_absolute(DIR)
	var dir := DirAccess.open(from)
	if dir == null:
		printerr("%s: no staged catalogue at %s -- run: node scripts/stage-preview.js all %s"
			% [who, from, from])
		return 0
	for f in dir.get_files():
		var w := FileAccess.open(DIR.path_join(f), FileAccess.WRITE)
		if w:
			w.store_buffer(FileAccess.get_file_as_bytes(from.path_join(f)))
			w.close()
	var raw := FileAccess.get_file_as_string(DIR.path_join("manifest.json"))
	var man = JSON.parse_string(raw)
	if typeof(man) != TYPE_ARRAY:
		printerr("%s: %s/manifest.json is not a manifest" % [who, from])
		return 0
	return (man as Array).size()

## Installs every staged item into ReplicatedStorage/OnChain, over anything already there.
## Call once the world is running: add_model into a folder that does not exist yet drops the
## model without a word.
static func install(world, who: String, from: String) -> int:
	var raw := FileAccess.get_file_as_string(DIR.path_join("manifest.json"))
	var man = JSON.parse_string(raw)
	if typeof(man) != TYPE_ARRAY:
		return 0
	# A bot town runs no wallet, so nothing else creates OnChain.
	world.run_chunk("previewfolder", """
local rs = game:GetService("ReplicatedStorage")
if not rs:FindFirstChild("OnChain") then
	local f = Instance.new("Folder") f.Name = "OnChain" f.Parent = rs
end
""")
	var listing := DirAccess.open(DIR)
	var files := listing.get_files() if listing else PackedStringArray()
	var n := 0
	for row in man:
		var key := String(row.get("key", ""))
		var instance := String(row.get("instance", key))
		if key == "": continue
		var model := FileAccess.get_file_as_string(DIR.path_join(key + ".json"))
		if model == "": continue
		# Paths are matched by leaf filename: the host opens only res:// and user://. A prefix
		# replace fails silently instead -- every caller globalizes a res:// path containing "..",
		# which comes back with the dots unresolved, while the staged JSON holds the resolved
		# spelling, so nothing matches and every texture keeps a path the host cannot open. These
		# JSON strings hold no escaped quotes, so splitting on `"` puts each value at an odd index.
		var parts := model.split("\"")
		for i in range(1, parts.size(), 2):
			var v := String(parts[i])
			var cut := v.rfind("/")
			var leaf := v.substr(cut + 1) if cut >= 0 else v
			if leaf != "" and files.has(leaf):
				parts[i] = DIR + "/" + leaf
		model = "\"".join(parts)
		world.add_model("ReplicatedStorage/OnChain", instance, model)
		n += 1
		# Wardrobe.server looks an item up by the name the chain has, so a renamed one goes in
		# under the old name too. addModelJson applies properties.Name after building, so the
		# copy's own Name must be rewritten or both models claim the new name, second wins.
		# Only the model changes: the name and thumbnail on the tile are item.name and item.thumb,
		# chain data that scripts/publish-catalogue.js alone writes.
		var was := String(row.get("previously", ""))
		if was != "" and was != instance:
			var doc = JSON.parse_string(model)
			if typeof(doc) == TYPE_DICTIONARY:
				if typeof(doc.get("properties")) == TYPE_DICTIONARY:
					doc["properties"]["Name"] = was
				doc["name"] = was
				world.add_model("ReplicatedStorage/OnChain", was, JSON.stringify(doc))
				n += 1
	print("[%s] %d catalogue item(s) standing in, local build over anything on chain" % [who, n])
	return n
