// Draws an accessory's geometry, so it can be looked at before it costs gas.
//
//   node scripts/preview-model.js wig out.png
//
// The catalogue's thumbnails are hand-drawn, so they say nothing about whether the model is
// right. This projects the actual parts, at their actual positions, against the head they
// hang off: orthographic, every part an axis-aligned block drawn back to front, orientation
// applied as a shear on the silhouette -- enough for a few degrees of lean and no more.
const fs = require("fs");
const path = require("path");
const { Canvas, encode, shade } = require("./png");
const { ITEMS } = require("./catalogue");

const PX = 74;                    // pixels per stud
const SKIN = [214, 176, 140];
const BG = [24, 28, 38];

/// The R6 head in worn space for a hat: the origin is the top of the skull, the head hangs
/// below it, and the profile is a hexagon, one stud across at the crown and two at its widest.
const HEAD = { top: 0, bottom: -1.73, widestY: -0.87, crown: 0.5, widest: 1.0, depth: 0.5 };

function headHalfWidth(y) {
  if (y > HEAD.top || y < HEAD.bottom) return 0;
  if (y >= HEAD.widestY) {
    const t = (HEAD.top - y) / (HEAD.top - HEAD.widestY);
    return HEAD.crown + (HEAD.widest - HEAD.crown) * t;
  }
  const t = (y - HEAD.bottom) / (HEAD.widestY - HEAD.bottom);
  return HEAD.crown + (HEAD.widest - HEAD.crown) * t;
}

function colourOf(node) {
  const c = node.properties && node.properties.Color;
  if (c && Array.isArray(c.Color3uint8)) return c.Color3uint8;
  return [200, 200, 200];
}

/// Every node with a Position and a Size, flattened out of the accessory's tree.
function partsOf(model) {
  const out = [];
  const walk = (n) => {
    const p = n.properties || {};
    if (p.Position && p.Size) out.push({ name: n.name, pos: p.Position, size: p.Size,
      rot: p.Orientation || [0, 0, 0], colour: colourOf(n) });
    (n.children || []).forEach(walk);
  };
  walk(model);
  return out;
}

function render(key, file) {
  const item = ITEMS.find((i) => i.key === key);
  if (!item) throw new Error(`no catalogue item "${key}"`);
  const model = item.model(new Proxy({}, { get: () => "x" }));
  const parts = partsOf(model);

  const VW = 230, VH = 240, GAP = 14;
  const c = new Canvas(VW * 2 + GAP * 3, VH + GAP * 2);
  c.fill(0, 0, c.w, c.h, () => BG);

  // Face on, and from the left.
  const panels = [
    { ox: GAP, label: "front", hx: (p) => p.pos[0], hw: (p) => p.size[0], key: (p) => p.pos[2] },
    { ox: GAP * 2 + VW, label: "side", hx: (p) => -p.pos[2], hw: (p) => p.size[2], key: (p) => -Math.abs(p.pos[0]) },
  ];

  for (const panel of panels) {
    const cx = panel.ox + VW / 2;
    const cy = GAP + 46;
    c.fill(panel.ox, GAP, panel.ox + VW, GAP + VH, () => [32, 37, 50]);

    // The head first, so anything drawn over it is hair in front of the skull.
    for (let py = 0; py < VH; py++) {
      const y = -(py - (cy - GAP)) / PX;
      let half;
      if (panel.label === "front") half = headHalfWidth(y);
      else half = (y <= HEAD.top && y >= HEAD.bottom) ? HEAD.depth : 0;
      if (half <= 0) continue;
      for (let px = -Math.round(half * PX); px <= Math.round(half * PX); px++) {
        c.set(cx + px, GAP + py, shade(SKIN, 1.0));
      }
    }

    // Parts, furthest away first. The head occludes: a part that does not reach in front of
    // the face plane is drawn only where it sticks out past the head's outline, so hair down
    // the back does not paint over the face.
    const order = [...parts].sort((a, b) => panel.key(b) - panel.key(a));
    for (const p of order) {
      const w = panel.hw(p) * PX, h = p.size[1] * PX;
      const x0 = cx + (panel.hx(p) * PX) - w / 2;
      const y0 = cy + (-p.pos[1] * PX) - h / 2;
      const lean = (panel.label === "front" ? (p.rot[2] || 0) : 0) * Math.PI / 180;
      const inFront = panel.label === "front"
        ? (p.pos[2] - p.size[2] / 2) < -HEAD.depth + 0.001
        : true;
      for (let dy = 0; dy < h; dy++) {
        const shift = Math.tan(lean) * (dy - h / 2);
        for (let dx = 0; dx < w; dx++) {
          const px = Math.round(x0 + dx + shift), py = Math.round(y0 + dy);
          if (px < panel.ox || px >= panel.ox + VW || py < GAP || py >= GAP + VH) continue;
          if (!inFront) {
            const y = -(py - GAP - (cy - GAP)) / PX;
            const half = headHalfWidth(y) * PX;
            if (Math.abs(px - cx) < half) continue;      // hidden behind the skull
          }
          // Shaded down the block so overlapping layers stay legible.
          c.set(px, py, shade(p.colour, 1.06 - 0.22 * (dy / Math.max(1, h))));
        }
      }
    }

  }

  fs.writeFileSync(file, encode(c.px, c.w, c.h));
  return { parts: parts.length, file };
}

const [, , key, out] = process.argv;
if (!key) {
  console.error("usage: node scripts/preview-model.js <item key> [out.png]");
  process.exit(1);
}
const file = out || path.join(__dirname, "..", `${key}-preview.png`);
const r = render(key, file);
console.log(`${key}: ${r.parts} parts -> ${r.file}   (left: front, right: from the left)`);
