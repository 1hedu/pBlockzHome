// Turns the PulseChain tree GLB into the mesh the town prop is built from.
//
//   node scripts/prep-tree.js <path to Pulsechain_Tree_Full_Roblox.glb>
//
// Output goes on chain, so vertices are rounded to DP and welded on the way through. No
// normals are written: the engine derives them from the winding, and carrying the GLB's own
// across would need the inverse transpose of the node transform to survive a non-uniform scale.
const fs = require("fs");
const path = require("path");
const { Canvas, decode, encode, blit } = require("./png");

const OUT = path.join(__dirname, "models");
const TEX = 256;
const DP = 3;

/// A .glb is a 12-byte header then chunks of [u32 length][u32 kind][body] padded to 4.
/// Kind 0x4e4f534a is "JSON", 0x004e4942 is "BIN".
function readGlb(bytes) {
  if (bytes.readUInt32LE(0) !== 0x46546c67) throw new Error("not a glb");
  let at = 12, json = null, bin = null;
  while (at < bytes.length) {
    const len = bytes.readUInt32LE(at), kind = bytes.readUInt32LE(at + 4);
    const body = bytes.subarray(at + 8, at + 8 + len);
    if (kind === 0x4e4f534a) json = JSON.parse(body.toString("utf8"));
    else if (kind === 0x004e4942) bin = body;
    at += 8 + len + ((4 - (len % 4)) % 4);
  }
  if (!json) throw new Error("no json chunk");
  return { json, bin };
}

const COMPONENT = {
  5120: ["readInt8", 1], 5121: ["readUInt8", 1], 5122: ["readInt16LE", 2],
  5123: ["readUInt16LE", 2], 5125: ["readUInt32LE", 4], 5126: ["readFloatLE", 4],
};
const COUNT = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 };

function readAccessor(g, bin, index) {
  const acc = g.accessors[index];
  const [reader, size] = COMPONENT[acc.componentType];
  const n = COUNT[acc.type];
  const view = g.bufferViews[acc.bufferView];
  const base = (view.byteOffset || 0) + (acc.byteOffset || 0);
  const stride = view.byteStride || n * size;
  const out = [];
  for (let i = 0; i < acc.count; i++) {
    const at = base + i * stride;
    if (n === 1) out.push(bin[reader](at));
    else {
      const v = [];
      for (let k = 0; k < n; k++) v.push(bin[reader](at + k * size));
      out.push(v);
    }
  }
  return out;
}

/// Column-major 4x4, glTF's layout: rotation is a quaternion in (x, y, z, w) order.
function nodeMatrix(node) {
  if (node.matrix) return node.matrix.slice();
  const t = node.translation || [0, 0, 0];
  const [x, y, z, w] = node.rotation || [0, 0, 0, 1];
  const s = node.scale || [1, 1, 1];
  const m = [
    1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0,
    2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0,
    2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0,
    0, 0, 0, 1,
  ];
  for (let c = 0; c < 3; c++) for (let k = 0; k < 3; k++) m[c * 4 + k] *= s[c];
  m[12] = t[0]; m[13] = t[1]; m[14] = t[2];
  return m;
}
const mul = (a, b) => {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++)
    for (let k = 0; k < 4; k++) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return o;
};
const xform = (m, p) => [
  m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
  m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
  m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14],
];

const src = process.argv[2];
if (!src) {
  console.error("usage: node scripts/prep-tree.js <Pulsechain_Tree_Full_Roblox.glb>");
  process.exit(1);
}
fs.mkdirSync(OUT, { recursive: true });
const { json: g, bin } = readGlb(fs.readFileSync(src));

const P = [], T = [], F = [];
const walk = (index, parent) => {
  const node = g.nodes[index];
  const m = mul(parent, nodeMatrix(node));
  if (node.mesh !== undefined) {
    for (const prim of g.meshes[node.mesh].primitives) {
      if (prim.mode !== undefined && prim.mode !== 4) continue;
      const pos = readAccessor(g, bin, prim.attributes.POSITION);
      const uv = prim.attributes.TEXCOORD_0 !== undefined
        ? readAccessor(g, bin, prim.attributes.TEXCOORD_0) : null;
      const idx = prim.indices !== undefined ? readAccessor(g, bin, prim.indices)
        : pos.map((_, i) => i);
      const base = P.length;
      for (let i = 0; i < pos.length; i++) {
        P.push(xform(m, pos[i]));
        T.push(uv ? uv[i] : [0, 0]);
      }
      for (let i = 0; i + 2 < idx.length; i += 3) F.push([base + idx[i], base + idx[i + 1], base + idx[i + 2]]);
    }
  }
  for (const child of node.children || []) walk(child, m);
};
for (const n of g.scenes[g.scene || 0].nodes) walk(n, [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

// Origin at the base: centred in x and z, y = 0 at the lowest vertex, so the prop places by
// its foot.
const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
for (const p of P) for (let i = 0; i < 3; i++) {
  if (p[i] < lo[i]) lo[i] = p[i];
  if (p[i] > hi[i]) hi[i] = p[i];
}
const mid = [(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2];
for (const p of P) for (let i = 0; i < 3; i++) p[i] -= mid[i];

const round = (n) => {
  const s = n.toFixed(DP).replace(/\.?0+$/, "");
  return s === "" || s === "-" ? "0" : s;
};

// The exporter gives every face corner its own vertex; at DP decimals most collapse. Indices
// in vOf/tOf are 1-based, as an OBJ wants them.
const vKey = new Map(), tKey = new Map(), V2 = [], T2 = [], vOf = [], tOf = [];
for (let i = 0; i < P.length; i++) {
  const p = P[i].map(round), t = T[i].map(round);
  const pk = p.join(","), tk = t.join(",");
  if (!vKey.has(pk)) { V2.push(p); vKey.set(pk, V2.length); }
  if (!tKey.has(tk)) { T2.push(t); tKey.set(tk, T2.length); }
  vOf[i] = vKey.get(pk);
  tOf[i] = tKey.get(tk);
}

// Bark or leaf by which half of the colour map the face reads: wood grain on top, the five
// leaf colours below. glTF puts v = 0 at the top of the image, so bark is v < 0.5. Split at
// all because a material covers a whole MeshPart -- Neon canopy over a Wood trunk needs two.
// scripts/prep-roma.js cuts the same way, on a surface boundary rather than a texture seam.
const barkFace = (f) => {
  let v = 0;
  for (const i of f) v += +T[i][1];
  return v / f.length < 0.5;
};

/// Writes one OBJ from the given faces, re-indexed to carry only the vertices they use: OBJ
/// numbers vertices absolutely, so naming vertex 9,000 means shipping the 8,999 before it.
function writeObj(file, faces, note) {
  const out = [`# ${note}, from the GLB by scripts/prep-tree.js`,
    "mtllib tree.mtl", "usemtl TreeColors"];
  const vSeen = new Map(), tSeen = new Map(), vOut = [], tOut = [], fOut = [];
  let dropped = 0;
  for (const f of faces) {
    // Reversed: an OBJ is counter-clockwise, the engine calls a clockwise triangle the front.
    const c = f.slice().reverse();
    if (vOf[c[0]] === vOf[c[1]] || vOf[c[1]] === vOf[c[2]] || vOf[c[0]] === vOf[c[2]]) { dropped++; continue; }
    fOut.push(c.map((i) => {
      const vi = vOf[i], ti = tOf[i];
      if (!vSeen.has(vi)) { vOut.push(V2[vi - 1]); vSeen.set(vi, vOut.length); }
      if (!tSeen.has(ti)) { tOut.push(T2[ti - 1]); tSeen.set(ti, tOut.length); }
      return `${vSeen.get(vi)}/${tSeen.get(ti)}`;
    }).join(" "));
  }
  for (const v of vOut) out.push(`v ${v[0]} ${v[1]} ${v[2]}`);
  for (const t of tOut) out.push(`vt ${t[0]} ${(1 - +t[1]).toFixed(DP).replace(/\.?0+$/, "") || "0"}`);
  for (const f of fOut) out.push("f " + f);
  const text = out.join("\n") + "\n";
  fs.writeFileSync(path.join(OUT, file), text);
  // Node's console.log has no width specifiers -- "%-17s" prints literally -- so pad by hand.
  console.log("%s %s verts, %s tris%s, %s bytes", file.padEnd(17), String(vOut.length).padStart(5),
    String(fOut.length).padStart(5), dropped ? ` (${dropped} degenerate dropped)` : "",
    String(text.length).padStart(6));
  return { text, verts: vOut };
}

/// Size of a vertex set and where its middle sits in the whole tree's frame. A MeshPart fits
/// its mesh to Size about its own middle, so a canopy needs both: the tree's size would
/// stretch it over the trunk, the tree's origin would sit it on the ground.
function boxOf(verts) {
  const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity];
  for (const v of verts) for (let i = 0; i < 3; i++) {
    const n = +v[i];
    if (n < lo[i]) lo[i] = n;
    if (n > hi[i]) hi[i] = n;
  }
  return { size: [0, 1, 2].map((i) => +(hi[i] - lo[i]).toFixed(4)),
           mid: [0, 1, 2].map((i) => +((lo[i] + hi[i]) / 2).toFixed(4)) };
}

const whole = writeObj("tree.obj", F, "PulseChain tree");
const trunk = writeObj("tree-trunk.obj", F.filter(barkFace), "PulseChain tree, the trunk");
const canopy = writeObj("tree-canopy.obj", F.filter((f) => !barkFace(f)), "PulseChain tree, the canopy");
const text = whole.text;

// The colour map: the GLB's first image, resampled to TEX square.
const img = (g.images || [])[0];
let texBytes = 0;
if (img && img.bufferView !== undefined) {
  const view = g.bufferViews[img.bufferView];
  const raw = bin.subarray(view.byteOffset || 0, (view.byteOffset || 0) + view.byteLength);
  const decoded = decode(raw);
  const c = new Canvas(TEX, TEX);
  blit(c, decoded, 0, 0, TEX, TEX);
  const out = encode(c.px, c.w, c.h);
  fs.writeFileSync(path.join(OUT, "tree-colors.png"), out);
  texBytes = out.length;
  console.log("tree-colors.png %d -> %d bytes at %d square", raw.length, out.length, TEX);
}

const size = [hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]].map((n) => +n.toFixed(4));
fs.writeFileSync(path.join(OUT, "tree.json"), JSON.stringify({
  size,
  trunk: boxOf(trunk.verts),
  canopy: boxOf(canopy.verts),
}, null, 1) + "\n");

console.log("welded            %d verts -> %d", P.length, V2.length);
console.log("tree.json       %s studs", size.map((n) => n.toFixed(2)).join(" x "));
console.log("on chain        %d KB of mesh + %d KB of picture",
  Math.round(text.length / 1024), Math.round(texBytes / 1024));
