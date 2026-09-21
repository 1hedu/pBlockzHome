// Emblems for a white cape, painted at the back face's aspect ratio rather than square so a
// round logo stays round, put on chain as one image and worn as a Decal. emblemImage publishes
// a ~3:4 PNG at scripts/logos/<key>.png in its place; transparency there reads as cape white.
const fs = require("fs"), path = require("path");
const { Canvas, noise, ramp, shade, text, textWidth, decode, blit } = require("./png");

// 132 x 174 = 0.759, matching the 1.9 x 2.5 back face
const W = 132, H = 174;
const CX = W / 2, CY = H / 2;

const PULSE_STOPS = [
  { t: 0.00, c: [255, 20, 51] }, { t: 0.20, c: [255, 15, 161] }, { t: 0.40, c: [179, 31, 255] },
  { t: 0.58, c: [99, 51, 255] }, { t: 0.76, c: [31, 120, 255] }, { t: 1.00, c: [20, 230, 255] },
];

// ---- drawing helpers ----------------------------------------------------------------
/**
 * Vertices left and right, flats top and bottom: the head orientation rbx_runtime.cpp
 * calls flat-topped, 2 wide across the corners and 1.73 tall across the flats.
 */
function inHex(x, y, cx, cy, r) {
  const dx = Math.abs(x - cx), dy = Math.abs(y - cy);
  return dy <= (r * Math.sqrt(3)) / 2 && dy <= Math.sqrt(3) * (r - dx);
}

function hexagon(c, cx, cy, r, colour) {
  c.fill(cx - r, cy - r, cx + r, cy + r, (x, y) =>
    inHex(x + 0.5, y + 0.5, cx, cy, r) ? (typeof colour === "function" ? colour(x, y) : colour) : null);
}

function hexRing(c, cx, cy, r, thickness, colour) {
  c.fill(cx - r, cy - r, cx + r, cy + r, (x, y) => {
    const px = x + 0.5, py = y + 0.5;
    if (!inHex(px, py, cx, cy, r) || inHex(px, py, cx, cy, r - thickness)) return null;
    return typeof colour === "function" ? colour(x, y) : colour;
  });
}

/** The PulseBlockz sweep: PULSE_STOPS up a box's diagonal, bottom-left to top-right. */
function sweep(x0, y0, x1, y1) {
  return (x, y) => ramp(PULSE_STOPS, ((x - x0) / (x1 - x0) + (1 - (y - y0) / (y1 - y0))) / 2);
}

/** A round-capped line `width` pixels thick. */
function bar(c, ax, ay, bx, by, width, colour) {
  const minX = Math.floor(Math.min(ax, bx) - width), maxX = Math.ceil(Math.max(ax, bx) + width);
  const minY = Math.floor(Math.min(ay, by) - width), maxY = Math.ceil(Math.max(ay, by) + width);
  const dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy;
  for (let y = minY; y <= maxY; y++)
    for (let x = minX; x <= maxX; x++) {
      const px = x + 0.5, py = y + 0.5;
      let t = len2 === 0 ? 0 : ((px - ax) * dx + (py - ay) * dy) / len2;
      t = Math.max(0, Math.min(1, t));
      const qx = ax + dx * t, qy = ay + dy * t;
      if (Math.hypot(px - qx, py - qy) <= width / 2)
        c.set(x, y, typeof colour === "function" ? colour(x, y) : colour);
    }
}

const HEART = [
  "0110110",
  "1111111",
  "1111111",
  "1111111",
  "0111110",
  "0011100",
  "0001000",
];

function heart(c, cx, cy, scale, colour) {
  const w = HEART[0].length * scale, h = HEART.length * scale;
  const x0 = cx - w / 2, y0 = cy - h / 2;
  const dark = shade(colour, 0.45);
  const on = (col, row) => row >= 0 && row < HEART.length && col >= 0 && col < HEART[0].length && HEART[row][col] === "1";
  for (let row = 0; row < HEART.length; row++)
    for (let col = 0; col < HEART[0].length; col++) {
      if (!on(col, row)) continue;
      const edge = !on(col - 1, row) || !on(col + 1, row) || !on(col, row - 1) || !on(col, row + 1);
      const glint = row === 1 && col === 1;
      const paint = edge ? dark : glint ? shade(colour, 1.5) : colour;
      c.rect(x0 + col * scale, y0 + row * scale, x0 + (col + 1) * scale, y0 + (row + 1) * scale, paint);
    }
}

// ---- the emblems ---------------------------------------------------------------------
// `confident` marks a shape this repo actually knows, such as the PulseChain hexagon the
// engine already draws for a head. The rest are third-party marks, drawn from memory unless
// a note above the key gives a source.
const EMBLEMS = {
  pulse: {
    name: "Pulse Cape", confident: true,
    blurb: "The PulseChain hexagon, with the sweep this engine paints its characters in.",
    paint(c) {
      const r = 52;
      hexagon(c, CX, CY, r, sweep(CX - r, CY - r, CX + r, CY + r));
      // The heartbeat trace
      const y = CY, pts = [[CX - 40, y], [CX - 18, y], [CX - 10, y - 22], [CX + 2, y + 20], [CX + 12, y], [CX + 40, y]];
      for (let i = 0; i < pts.length - 1; i++) bar(c, pts[i][0], pts[i][1], pts[i + 1][0], pts[i + 1][1], 7, [255, 255, 255]);
    },
  },

  pulsex: {
    name: "PulseX Cape", confident: false,
    blurb: "An X in the PulseChain sweep.",
    paint(c) {
      const r = 46;
      bar(c, CX - r, CY - r, CX + r, CY + r, 22, sweep(CX - r, CY - r, CX + r, CY + r));
      bar(c, CX + r, CY - r, CX - r, CY + r, 22, sweep(CX - r, CY - r, CX + r, CY + r));
    },
  },

  hex: {
    name: "HEX Cape", confident: false,
    blurb: "Nested hexagons in pink and violet.",
    paint(c) {
      const stops = [{ t: 0, c: [255, 60, 170] }, { t: 1, c: [120, 40, 220] }];
      const tint = (r) => (x, y) => ramp(stops, (y - (CY - r)) / (2 * r));
      hexRing(c, CX, CY, 54, 13, tint(54));
      hexRing(c, CX, CY, 36, 12, tint(36));
      hexagon(c, CX, CY, 17, tint(17));
    },
  },

  inc: {
    name: "INC Cape", confident: false,
    blurb: "The wordmark, in green.",
    paint(c) {
      const word = "INC", scale = 6;
      const w = textWidth(word, scale);
      text(c, word, CX - w / 2, CY - (7 * scale) / 2, scale, [22, 160, 92]);
      bar(c, CX - w / 2, CY + 30, CX + w / 2, CY + 30, 7, [22, 160, 92]);
    },
  },

  pdai: {
    name: "pDAI Cape", confident: false,
    blurb: "The stablecoin diamond, in amber.",
    paint(c) {
      const gold = [245, 172, 55];
      // A diamond, 1.25 times taller than wide
      const inDiamond = (x, y, r) => Math.abs(x - CX) / r + Math.abs(y - CY) / (r * 1.25) <= 1;
      c.fill(CX - 56, CY - 68, CX + 56, CY + 68, (x, y) => {
        const px = x + 0.5, py = y + 0.5;
        if (!inDiamond(px, py, 50)) return null;
        const ring = !inDiamond(px, py, 34);
        // The bars are tested inside this fill, not drawn with bar(), so the diamond clips them
        const onBar = Math.abs(py - (CY - 13)) <= 5.5 || Math.abs(py - (CY + 13)) <= 5.5;
        return ring || onBar ? gold : null;
      });
    },
  },

  provex: {
    name: "ProveX Cape", confident: true,
    blurb: "The shield, off provex.com.",
    // scripts/logos/provex.png ships, so this drawing runs only if that file is removed.
    paint(c) {
      const r = 50;
      c.ellipse(CX, CY, r, r, [26, 22, 48]);
      c.ellipse(CX, CY, r - 6, r - 6, [16, 14, 32]);
      bar(c, CX - 24, CY - 24, CX + 24, CY + 24, 13, sweep(CX - r, CY - r, CX + r, CY + r));
      bar(c, CX + 24, CY - 24, CX - 24, CY + 24, 13, sweep(CX - r, CY - r, CX + r, CY + r));
      c.fill(CX - r, CY - r, CX + r, CY + r, (x, y) => {
        const d = Math.hypot(x + 0.5 - CX, y + 0.5 - CY);
        return d < r && d > r - 5 ? [232, 232, 244] : null;
      });
    },
  },

  // Traced from a screenshot of the mark, not from memory.
  coexist: {
    name: "Coexist Cape", confident: false,
    blurb: "Seven colours, one shape.",
    paint(c) {
      const r = 52;
      const wedges = [
        [242, 146, 52], [226, 74, 62], [176, 62, 152], [72, 92, 202],
        [52, 164, 192], [82, 182, 114], [242, 202, 74],
      ];
      const arms = wedges.length;
      c.fill(CX - r - 1, CY - r - 1, CX + r + 1, CY + r + 1, (x, y) => {
        const dx = x + 0.5 - CX, dy = y + 0.5 - CY;
        const d = Math.hypot(dx, dy);
        if (d > r) return null;
        const t = d / r;
        let a = Math.atan2(dy, dx) + Math.PI * 0.5;          // an arm pointing up
        if (a < 0) a += Math.PI * 2;
        const step = (Math.PI * 2) / arms;
        const i = Math.floor(a / step);
        const off = Math.abs((a % step) - step / 2);          // angle to the nearest arm
        // Arms widest at the centre, drawn to a point at the rim: the white star is the
        // figure and the wedges fill the gaps. Even-width arms give a wheel with spokes.
        if (off < step * 0.5 * (1.0 - 0.82 * t) || d < r * 0.2) return [248, 248, 252];
        return shade(wedges[i % arms], 1.06 - 0.2 * t);
      });
    },
  },

  // Art from DexScreener's CDN; PulseX's token host carries no image for PLSPUP.
  plspup: {
    name: "PLSPUP Cape", confident: true,
    blurb: "The dog, on a starfield.",
    paint(c) {
      // Only reached if logos/plspup.png is missing
      const r = 52;
      c.fill(14, 35, 118, 139, (x, y) => {
        const dx = x + 0.5 - 66, dy = y + 0.5 - 87;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d > r) return null;
        return mix([64, 72, 168], [128, 78, 172], (dy + r) / (2 * r));
      });
    },
  },

  orange: {
    name: "Tang Cape", confident: true,
    blurb: "An orange. No further explanation offered.",
    paint(c) {
      const skin = [244, 140, 32];
      c.ellipse(CX, CY + 8, 46, 44, (x, y, u, v) => shade(skin, 1.16 - 0.34 * ((u + v) / 2)));
      // Peel dimples
      for (let i = 0; i < 260; i++) {
        const a = noise(i, 1, 3) * Math.PI * 2, d = Math.sqrt(noise(i, 2, 4)) * 42;
        c.set(CX + Math.cos(a) * d, CY + 8 + Math.sin(a) * d * 0.95, shade(skin, 0.86));
      }
      c.ellipse(CX - 16, CY - 10, 11, 8, [255, 206, 140, 150]);   // a highlight
      c.rect(CX - 3, CY - 44, CX + 3, CY - 32, [126, 84, 34]);    // stem
      c.ellipse(CX + 20, CY - 42, 18, 10, [64, 156, 66]);         // leaf
      c.ellipse(CX + 20, CY - 42, 15, 7, [86, 186, 84]);
    },
  },

  n414: {
    name: "414 Cape", confident: true,
    blurb: "Four one four.",
    paint(c) {
      const word = "414", scale = 9;
      const w = textWidth(word, scale);
      text(c, word, CX - w / 2, CY - (7 * scale) / 2, scale, [28, 30, 38]);
    },
  },

  hearts: {
    name: "yourfriend Cape", confident: true,
    blurb: "Four containers, in a line.",
    // The cape is a trapezoid, 1.9 studs at the shoulders and 2.2 at the hem, so a row
    // of four only fits down low.
    paint(c) {
      const colours = [[228, 48, 48], [238, 200, 44], [66, 190, 76], [56, 200, 220]];
      const scale = 4, step = 32;
      const x0 = CX - (step * (colours.length - 1)) / 2;
      const y = H - 30;
      colours.forEach((colour, i) => heart(c, x0 + i * step, y, scale, colour));
    },
  },
};

// An emblem's ink, not its file, is scaled into this box and centred, so art with its own
// margin and edge-to-edge art come out the same size.
const EMBLEM_BOX_W = 100;      // of 132 -- ~3/4, the size art with its own margin already ships at
const EMBLEM_BOX_H = 118;      // of 174

/// The bounding box of the ink: alpha above 16, so a faint halo is not content.
function contentBox(img) {
  let x0 = img.w, y0 = img.h, x1 = -1, y1 = -1;
  for (let y = 0; y < img.h; y++)
    for (let x = 0; x < img.w; x++)
      if (img.px[(y * img.w + x) * 4 + 3] > 16) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
  return x1 < 0 ? null : { x0, y0, w: x1 - x0 + 1, h: y1 - y0 + 1 };
}

function emblemImage(key) {
  const file = path.join(__dirname, "logos", key + ".png");
  if (fs.existsSync(file)) {
    const src = decode(fs.readFileSync(file));
    const box = contentBox(src);
    if (!box) return { png: fs.readFileSync(file), fromFile: true };
    const scale = Math.min(EMBLEM_BOX_W / box.w, EMBLEM_BOX_H / box.h);
    const dw = Math.max(1, Math.round(box.w * scale));
    const dh = Math.max(1, Math.round(box.h * scale));
    // blit scales the whole source, so the content is copied out before it is scaled.
    const tight = new Canvas(box.w, box.h);
    for (let y = 0; y < box.h; y++)
      for (let x = 0; x < box.w; x++) {
        const i = ((y + box.y0) * src.w + (x + box.x0)) * 4;
        if (src.px[i + 3] > 0) tight.set(x, y, [src.px[i], src.px[i + 1], src.px[i + 2], src.px[i + 3]]);
      }
    const c = new Canvas(W, H);
    blit(c, tight, Math.round((W - dw) / 2), Math.round((H - dh) / 2), dw, dh);
    return { png: c.toPNG(), fromFile: true };
  }
  const c = new Canvas(W, H);
  EMBLEMS[key].paint(c);
  return { png: c.toPNG(), fromFile: false };
}

module.exports = { EMBLEMS, emblemImage, W, H, heart, hexagon, sweep, PULSE_STOPS };
