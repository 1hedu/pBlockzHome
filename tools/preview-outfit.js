// Draws a worn item on a body, so clothing can be looked at before it costs gas.
//
//   node scripts/preview-outfit.js goldcoat out.png
//   node scripts/preview-outfit.js all <path to wardrobe.png>
//
// An outfit is several Accessories on different limbs -- trousers are one per leg plus a
// waistband, a coat a body plus a cuff per arm -- and each one's parts are positioned in ITS
// attachment's space, not the body's, so the rig's attachment points are written down below.
// Orthographic boxes, front and side: it answers where a garment hangs and what it covers.
const fs = require("fs");
const { Canvas, encode, shade } = require("./png");
const { ITEMS, TEXTURES } = require("./catalogue");

// The R6 rig, in body space: the torso is 2 x 2 x 1 centred on the origin.
const BODY = [
  { name: "Head", pos: [0, 1.87, 0], size: [1.4, 1.73, 1.0], skin: true },
  { name: "Torso", pos: [0, 0, 0], size: [2, 2, 1] },
  { name: "ArmLeft", pos: [-1.5, 0, 0], size: [1, 2, 1], skin: true },
  { name: "ArmRight", pos: [1.5, 0, 0], size: [1, 2, 1], skin: true },
  { name: "LegLeft", pos: [-0.5, -2, 0], size: [1, 2, 1] },
  { name: "LegRight", pos: [0.5, -2, 0], size: [1, 2, 1] },
];

/// Where each attachment sits on the rig, in body space.
const ATTACH = {
  HatAttachment: [0, 2.73, 0],
  NeckAttachment: [0, 1, 0],
  WaistCenterAttachment: [0, -1, 0],
  BodyFrontAttachment: [0, 0, -0.5],
  BodyBackAttachment: [0, 0, 0.5],
  LeftFootAttachment: [-0.5, -3, 0],
  RightFootAttachment: [0.5, -3, 0],
  LeftGripAttachment: [-1.5, -1, 0],
  RightGripAttachment: [1.5, -1, 0],
};

const SKIN = [206, 170, 138];
const CLOTH = [92, 96, 110];

/// Every part of an item, moved into body space by the attachment its accessory names.
function wornParts(model) {
  const out = [];
  const walk = (node, attach) => {
    const p = node.properties || {};
    // An Accessory declares its attachment as the single Attachment inside its Handle.
    let here = attach;
    const named = (n) => {
      if (n.className === "Attachment" && ATTACH[n.name]) here = ATTACH[n.name];
      (n.children || []).forEach(named);
    };
    if (node.className === "Accessory" || node.className === "Accoutrement") named(node);
    if (p.Position && p.Size && node.className !== "Attachment") {
      out.push({ name: node.name, size: p.Size, rot: p.Orientation || [0, 0, 0],
        colour: (p.Color && p.Color.Color3uint8) || [200, 200, 200], attach: here, local: p.Position });
    }
    (node.children || []).forEach((c) => walk(c, here));
  };
  walk(model, [0, 0, 0]);
  return out.map((q) => ({ ...q, pos: [0, 1, 2].map((i) => q.attach[i] + q.local[i]) }));
}

const VIEWS = {
  front: { hx: (p) => -p.pos[0], hw: (q) => q.size[0], depth: (q) => q.pos[2] },
  side: { hx: (p) => -p.pos[2], hw: (q) => q.size[2], depth: (q) => -Math.abs(q.pos[0]) },
};

function drawPanel(c, ox, oy, w, h, parts, view) {
  c.fill(ox, oy, ox + w, oy + h, () => [32, 37, 50]);
  const all = [...BODY.map((b) => ({ ...b, pos: b.pos, colour: b.skin ? SKIN : CLOTH, body: true })), ...parts];
  let lo = [Infinity, Infinity], hi = [-Infinity, -Infinity];
  for (const q of all) {
    const x = view.hx(q), hw = view.hw(q) / 2;
    lo = [Math.min(lo[0], x - hw), Math.min(lo[1], q.pos[1] - q.size[1] / 2)];
    hi = [Math.max(hi[0], x + hw), Math.max(hi[1], q.pos[1] + q.size[1] / 2)];
  }
  const pad = 10;
  const sc = Math.min((w - pad * 2) / (hi[0] - lo[0]), (h - pad * 2) / (hi[1] - lo[1]));
  const sx = (x) => ox + w / 2 + (x - (lo[0] + hi[0]) / 2) * sc;
  const sy = (y) => oy + h / 2 - (y - (lo[1] + hi[1]) / 2) * sc;
  // Body first, then the clothes over it, each back to front.
  const order = [...all].sort((a, b) => (a.body === b.body ? view.depth(b) - view.depth(a) : a.body ? -1 : 1));
  for (const q of order) {
    const pw = view.hw(q) * sc, ph = q.size[1] * sc;
    const x0 = sx(view.hx(q)) - pw / 2, y0 = sy(q.pos[1]) - ph / 2;
    for (let dy = 0; dy < ph; dy++)
      for (let dx = 0; dx < pw; dx++) {
        const px = Math.round(x0 + dx), py = Math.round(y0 + dy);
        if (px < ox || px >= ox + w || py < oy || py >= oy + h) continue;
        c.set(px, py, shade(q.colour, (q.body ? 1.0 : 1.12) - 0.28 * (dy / Math.max(1, ph))));
      }
  }
}

function render(keys, out) {
  const texUris = Object.fromEntries(Object.keys(TEXTURES).map((n) => [n, n]));
  const W = 200, H = 260, GAP = 8;
  const c = new Canvas(keys.length * (W * 2 + GAP) + GAP, H + GAP * 2);
  c.fill(0, 0, c.w, c.h, () => [18, 20, 28]);
  keys.forEach((k, i) => {
    const item = ITEMS.find((x) => x.key === k);
    if (!item) throw new Error("no item " + k);
    const parts = wornParts(item.model(texUris));
    const ox = GAP + i * (W * 2 + GAP);
    drawPanel(c, ox, GAP, W, H, parts, VIEWS.front);
    drawPanel(c, ox + W, GAP, W, H, parts, VIEWS.side);
  });
  fs.writeFileSync(out, encode(c.px, c.w, c.h));
  return keys.length;
}

const [, , which, out] = process.argv;
if (!which) {
  console.error("usage: node scripts/preview-outfit.js <key|all> <out.png>");
  process.exit(1);
}
const keys = which === "all"
  ? ["goldpants", "blackpants", "goldcoat", "mariajacket", "goldshoes"]
  : which.split(",");
const n = render(keys, out || "outfit.png");
console.log(`${n} item(s) -> ${out || "outfit.png"}   (each shown front then side)`);
