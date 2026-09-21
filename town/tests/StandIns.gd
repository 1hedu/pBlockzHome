# Assets that are built but not published yet, mounted off disk. The place fetches anything in
# place-assets.json off chain and goes quiet rather than failing when it is missing, so a
# harness that does not mount these reads as a regression. Every harness uses this one list.
#
# Every process on the machine shares `user://preview`, so the server standing these in is
# enough -- the SoundId it publishes is a path each client can open for itself.

## Asset name -> [folder under scripts/, file].
const FILES := {
	"TreeTrunkMesh": ["models", "tree-trunk.obj"],
	"TreeCanopyMesh": ["models", "tree-canopy.obj"],
	"SfxFamiliar1": ["sfx", "familiar1.wav"],
	"SfxFamiliar2": ["sfx", "familiar2.wav"],
	"SfxTrampoline": ["sfx", "trampoline.wav"],
	"SfxStrongHit": ["sfx", "stronghit.wav"],
	"OrbMesh": ["models", "orb.obj"],
	"PulseGradient": ["models", "pulse-gradient.png"],
	"EngramBadge": ["models", "engram-badge.obj"],
	"SfxCharge": ["sfx", "charge.wav"],
	"SfxBuster": ["sfx", "buster.wav"],
	"EverlivingFishThumb": ["logos", "everliving-fish.png"],
}

## Copies each one into user://preview, naming any that are missing: that is a prep script
## nobody ran.
static func stage(who: String) -> void:
	DirAccess.make_dir_recursive_absolute("user://preview")
	for name in FILES:
		var row: Array = FILES[name]
		var bytes := FileAccess.get_file_as_bytes("res://../../../scripts/%s/%s" % [row[0], row[1]])
		if bytes.is_empty():
			printerr("%s: no scripts/%s/%s -- run its prep script first" % [who, row[0], row[1]])
			continue
		var w := FileAccess.open("user://preview/".path_join(row[1]), FileAccess.WRITE)
		if w:
			w.store_buffer(bytes)
			w.close()

## Luau that registers them in ReplicatedStorage.PlaceAssets, where the place's scripts look.
static func chunk(who: String) -> String:
	var pairs := ""
	for name in FILES:
		pairs += '\t{ "%s", "user://preview/%s" },\n' % [name, FILES[name][1]]
	return """
local rs = game:GetService("ReplicatedStorage")
local folder = rs:WaitForChild("PlaceAssets", 60)
if not folder then return end
local n = 0
for _, row in ipairs({
%s}) do
	local v = folder:FindFirstChild(row[1]) or Instance.new("StringValue")
	v.Name = row[1]
	v.Value = row[2]
	v.Parent = folder
	n += 1
end
print(("%s: standing in for %%d asset(s) that are not on chain yet"):format(n))
""" % [pairs, who]
