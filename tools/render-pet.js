// A textured render of a catalogue model, so a mesh item can be looked at before it costs gas.
// The drawing is scripts/mesh-view.js, shared with the catalogue thumbnails so a shelf picture
// cannot disagree with the model it sells.
const fs = require("fs");
const { Canvas, encode } = require("./png");
const view = require("./mesh-view");
const { ITEMS, MESH_FILES } = require("./catalogue");

const [, , key, out, ...flags] = process.argv;
if (!key) {
  console.error("usage: node scripts/render-pet.js <key> <out.png> [--back]");
  process.exit(1);
}
const item = ITEMS.find((i) => i.key === key);
if (!item) throw new Error("no catalogue item " + key);
const uris = Object.fromEntries(Object.keys(item.assets || {}).map((n) => [n, n]));
const c = new Canvas(460, 460);
const r = view.draw(c, item.model(uris), MESH_FILES[key] || {}, {
  back: flags.includes("--back"),
  background: [74, 78, 104],
});
fs.writeFileSync(out || `${key}.png`, encode(c.px, c.w, c.h));
console.log(`${key}: ${r.triangles} triangles -> ${out || key + ".png"}`);
