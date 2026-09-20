// The demo catalogue: every wearable this project puts on PulseChain, as geometry plus a
// painted thumbnail. Nothing here is a file on disk; scripts/publish-catalogue.js publishes.
//
// Items are drawn in worn space, whose origin is the point on the body the accessory hangs
// from; accessory() derives the Attachment offset from that. The engine (pulseblockz_world.cpp,
// the `p.worn` branch) places the Handle at limbOffset * limbAttachment * handleAttachment^-1
// and every other part keeps its offset from the Handle, so only the Attachment's position
// relative to the parts matters. One Accessory follows one limb; anything that bends at a
// joint is several, see outfit().
//
// Worn-space origins, R6 rig (rbx_runtime.cpp, kR6Points):
//   HatAttachment              top of the head
//   NeckAttachment             top of the torso, which is 2 x 2 x 1
//   BodyBackAttachment         centre of the torso's back face
//   WaistCenterAttachment      bottom of the torso, where the 1 x 2 x 1 legs start
//   Left/RightGripAttachment   the bottom of the arm, i.e. the hand
//   Left/RightFootAttachment   the bottom of that leg, i.e. the ankle
const fs = require("fs");
const path = require("path");
const { Canvas, noise, mix, ramp, shade, blit, decode } = require("./png");
const { EMBLEMS, emblemImage, W: EMBLEM_W, H: EMBLEM_H } = require("./capes");

// ---- palette -------------------------------------------------------------------------
const HAT_FELT = [34, 34, 42];
const HAT_RIBBON = [12, 12, 16];   // a black of its own, under the felt's, so the band shows
const HAT_BRIM = [30, 30, 38];
const GOLD = [214, 172, 66];
const GOLD_DEEP = [168, 126, 38];
// Louis: everything but the bill, and the ground the monogram texture prints on.
const LEATHER = [120, 82, 46];
const LEATHER_DEEP = [86, 56, 30];
const COPPER = [198, 116, 60];
const TUX_BLACK = [26, 26, 32];
const TUX_SATIN = [14, 14, 18];
const SHIRT = [238, 238, 232];
const PEG = [57, 255, 20];
const PEG_DEEP = [36, 196, 14];
const STEEL = [176, 178, 188];
const GOLD_NEON = [255, 205, 70];
const WIZARD_FELT = [42, 38, 104];
const GOLD_NEON_DEEP = [226, 168, 30];
const HAIR = [166, 143, 108];
const HAIR_LIT = [196, 175, 138];
const HAIR_DEEP = [138, 117, 86];
const GOLD_SEQUIN = [206, 162, 58];
const BLACK_SEQUIN = [30, 30, 34];
const SILVER_SEQUIN = [188, 192, 200];
const DRESS_BLACK = [16, 16, 20];
const SHOE_BLACK = [30, 30, 34];
const SOLE_RED = [196, 16, 40];
// Spoonie's rim as SubtractAsync made it (tests/bake_spoonie_rim.gd). Read at load, so a
// missing file fails before publishing starts.
const SPOONIE_RIM = JSON.parse(fs.readFileSync(path.join(__dirname, "models", "spoonie-rim.json"), "utf8"));
// Behind BFS 9000's shelf tile, whose picture is a photograph.
const BFS_RED = [104, 12, 22];
const SPOONIE_YELLOW = [232, 196, 52];   // Spoonie's tile background
const STEEL_SPOON = [198, 202, 210];
// Separate meshes so they can turn. Front is -Z and right is +X, hence the names, which
// Pets.luau matches by prefix.
const ROMA_WHEELS = ["WheelFL", "WheelFR", "WheelRL", "WheelRR"];

// The prepared file behind each pet asset name, for the thumbnails and
// scripts/render-pet.js, which draw the real meshes rather than bounding boxes.
const MESH_FILES = {
  steven: { mesh: "steven-face.obj", skull: "steven-skull.obj", face: "steven-face.png",
            bodyL: "wing-bodyL.obj", bodyR: "wing-bodyR.obj",
            rimL: "wing-rimL.obj", rimR: "wing-rimR.obj" },
  spoonie: { mesh: "spoonie.obj" },
  pup: { mesh: "pup.obj", colors: "pup-colors.png" },
  roma: Object.assign({ body: "roma-body.obj", colors: "roma-colors.png" },
    Object.fromEntries(ROMA_WHEELS.map((n) => [n.toLowerCase(), `roma-${n.toLowerCase()}.obj`]))),
};

const WING = [206, 236, 255];
const WING_RIM = [232, 214, 255];
const GLOW = [150, 96, 245];

/** The PulseBlockz sweep, the same stops the engine's skin shader uses (pulseblockz_world.cpp). */
const PULSE_STOPS = [
  { t: 0.00, c: [255, 20, 51] }, { t: 0.20, c: [255, 15, 161] }, { t: 0.40, c: [179, 31, 255] },
  { t: 0.58, c: [99, 51, 255] }, { t: 0.76, c: [31, 120, 255] }, { t: 1.00, c: [20, 230, 255] },
];

// ---- model helpers --------------------------------------------------------------------
/**
 * A MeshPart. `mesh` and `texture` are pblockz:// URIs the host swaps for local files, as it
 * does for a Decal. The engine fits the mesh to Size and picks its loader by file extension.
 */
function meshPart(name, pos, size, mesh, opts = {}) {
  const props = {
    Position: pos, Size: size, MeshId: mesh,
    Material: opts.material || "SmoothPlastic",
    Color: { Color3uint8: opts.color || [255, 255, 255] },
    CanCollide: false, Massless: true, DoubleSided: opts.doubleSided !== false,
  };
  if (opts.texture) props.TextureID = opts.texture;
  if (opts.orientation) props.Orientation = opts.orientation;
  if (opts.transparency) props.Transparency = opts.transparency;
  const node = { className: "MeshPart", name, properties: props };
  if (opts.children) node.children = opts.children;
  return node;
}

/** A part, positioned in worn space. */
function part(name, pos, size, opts = {}) {
  const props = {
    Position: pos, Size: size,
    Material: opts.material || "SmoothPlastic",
    Color: { Color3uint8: opts.color || [200, 200, 200] },
    CanCollide: false, Massless: true,
  };
  if (opts.shape) props.Shape = opts.shape;
  if (opts.orientation) props.Orientation = opts.orientation;
  if (opts.reflectance) props.Reflectance = opts.reflectance;
  if (opts.transparency) props.Transparency = opts.transparency;
  const node = { className: "Part", name, properties: props };
  if (opts.children) node.children = opts.children;
  return node;
}

/**
 * A SpecialMesh. MeshType "Sphere" stretches to fill the part's box on every axis, where
 * Shape = Ball is a true sphere, in Roblox as here.
 */
function specialMesh(meshType) {
  return { className: "SpecialMesh", name: "Mesh", properties: { MeshType: meshType } };
}

/** A UnionOperation. `made` is what UnionAsync / SubtractAsync returned, carried as MeshData. */
function unionPart(name, pos, made, opts = {}) {
  const props = {
    Position: pos, Size: made.size, MeshData: made.meshData,
    Material: opts.material || "SmoothPlastic",
    Color: { Color3uint8: opts.color || [200, 200, 200] },
    CanCollide: false, Massless: true, UsePartColor: true,
  };
  if (opts.reflectance) props.Reflectance = opts.reflectance;
  if (opts.orientation) props.Orientation = opts.orientation;
  return { className: "UnionOperation", name, properties: props };
}

/** A whole image stretched across one face. */
function decal(face, texture, opts = {}) {
  const props = { Face: face, Texture: texture };
  if (opts.transparency) props.Transparency = opts.transparency;
  if (opts.color) props.Color3 = { Color3uint8: opts.color };
  return { className: "Decal", name: "Decal" + face, properties: props };
}

/** The same image repeated every `studs` studs across a face. */
function texture(face, tex, studs = 1) {
  return {
    className: "Texture", name: "Texture" + face,
    properties: { Face: face, Texture: tex, StudsPerTileU: studs, StudsPerTileV: studs },
  };
}

/** A twinkle on the part it is in. The engine gives it a fixed look, so only colour is set. */
function sparkles(color) {
  return { className: "Sparkles", name: "Sparkle", properties: { SparkleColor: { Color3uint8: color } } };
}

/**
 * The braziers' flame emitter, with no Color or Texture: src/shared/Flames.luau fills those
 * in at run time from the item's `Flame` attribute, and a fire of several colours becomes
 * several emitters. Squash stretches each particle along its travel, making a tongue.
 */
function flame(scale = 1) {
  const n = (kp) => ({ NumberSequence: { keypoints: kp.map(([t, v]) => ({ time: t, value: v })) } });
  return {
    className: "ParticleEmitter", name: "Flame",
    properties: {
      Rate: 110,
      Size: n([[0, 0.26 * scale], [0.3, 0.62 * scale], [1, 0.07 * scale]]),
      Transparency: n([[0, 0.55], [0.55, 0.7], [1, 1]]),
      Lifetime: { NumberRange: [0.26, 0.44] },
      Speed: { NumberRange: [2.2, 3.6] },
      Acceleration: [0, 5, 0],
      Drag: 1.2,
      SpreadAngle: [16, 16],
      EmissionDirection: "Top",
      LightEmission: 0.35,
      Brightness: 1,
      LockedToPart: false,
      Squash: n([[0, 1], [0.5, 2.1], [1, 2.7]]),
    },
  };
}

/** A PointLight to put inside a part. */
function glow(color, brightness, range) {
  return {
    className: "PointLight", name: "Glow",
    properties: { Color: { Color3uint8: color }, Brightness: brightness, Range: range },
  };
}

/**
 * Neon without a bloom halo. The kit draws Neon at 1.6 times its colour so a place's
 * BloomEffect finds it first (kNeonHdr in pulseblockz_world.cpp); pre-scaling by the inverse
 * keeps a small part -- a peg, a watch marker -- under the threshold and still emissive.
 */
function flatNeon(rgb) {
  return shade(rgb, 0.6);
}

/** A PointLight on an invisible part, where there is no part to put one in. */
function glowPart(colour, brightness = 2, range = 12, at = [0, 0, -2.1]) {
  return part("Glow", at, [0.2, 0.2, 0.2], {
    transparency: 1, children: [glow(colour, brightness, range)],
  });
}

/** A box's four side faces. */
const AROUND = ["Front", "Back", "Left", "Right"];

/**
 * `parts[0]` becomes the Handle and the rest are welded to it. Positions are worn space; the
 * Attachment is derived so that worn-space (0, 0, 0) lands on the body's attachment point.
 */
function accessory(name, attachment, parts, opts = {}) {
  // A worn Handle is placed by its attachment alone and its own Orientation discarded, as on
  // Roblox, while siblings are placed relative to the Handle including that orientation. So a
  // turned first part gets an unturned speck at the same position to be the Handle instead.
  if (parts[0].properties.Orientation) {
    const at = parts[0].properties.Position;
    parts = [part("Anchor", at, [0.05, 0.05, 0.05], { transparency: 1 }), ...parts];
  }
  const handle = parts[0];
  const at = handle.properties.Position;
  const handleNode = { ...handle, name: "Handle" };
  handleNode.children = [
    // Worn space's origin, relative to the Handle's own centre.
    { className: "Attachment", name: attachment, properties: { Position: [-at[0], -at[1], -at[2]] } },
    ...(handle.children || []),
  ];
  const rest = parts.slice(1);
  const node = {
    // The loader names children by `name`; the host reads the root's `Name` property.
    className: "Accessory", name,
    properties: { Name: name },
    children: [
      handleNode,
      ...rest,
      ...rest.map((p) => ({
        className: "WeldConstraint", name: p.name + "Weld",
        properties: { Part0: "Handle", Part1: p.name },
      })),
    ],
  };
  // Attributes on the item itself: the torches name which fire they burn this way.
  if (opts.attributes) node.attributes = opts.attributes;
  return node;
}

/** Several accessories worn as one thing: a limb each, for anything that bends at a joint. */
function outfit(name, accessories) {
  // A weld's Part0/Part1 is a path from the root of the model being loaded, so bare "Handle"
  // is wrong once the Accessory is a child of a Model: re-point each through its own name.
  const scoped = accessories.map((acc) => ({
    ...acc,
    children: (acc.children || []).map((c) =>
      c.className === "WeldConstraint"
        ? { ...c, properties: { Part0: acc.name + "/" + c.properties.Part0,
                                Part1: acc.name + "/" + c.properties.Part1 } }
        : c),
  }));
  return { className: "Model", name, properties: { Name: name }, children: scoped };
}

// ---- shared textures -------------------------------------------------------------------
// Published once and referenced by URI, so two items wearing one pattern share its bytes.
/** Overlapping discs, each catching the light a little differently. */
function sequinTexture(base) {
  return { w: 64, h: 64, mime: "image/png", paint(c) {
    c.rect(0, 0, 64, 64, shade(base, 0.55));
    for (let row = 0; row < 9; row++)
      for (let col = 0; col < 9; col++) {
        const cx = col * 8 + (row % 2 ? 4 : 0), cy = row * 8;
        const lit = noise(col, row, 11);
        // The top of the range is a white spark, whatever the base colour.
        const face = lit > 0.88 ? [255, 244, 228] : shade(base, 0.75 + lit * 0.75);
        c.ellipse(cx, cy, 4.2, 4.2, shade(face, 0.7));
        c.ellipse(cx, cy, 3.2, 3.2, face);
        c.set(cx - 1, cy - 1, shade(face, 1.35));
      }
  } };
}

const TEXTURES = {
  // PULSE_STOPS baked to a PNG, so a part can wear the ramp the skin shader draws.
  pulse: { w: 128, h: 128, mime: "image/png", paint(c) {
    c.fill(0, 0, c.w, c.h, (x, y, u, v) => {
      // 45 degrees, matching the logo and the skin shader.
      const t = (u + (1 - v)) / 2;
      // Blocks rather than per-pixel grain: fine noise defeats PNG compression and pushes
      // the image towards AssetStore's 24,575-byte chunk limit.
      return shade(ramp(PULSE_STOPS, t), 0.94 + 0.12 * noise(x >> 4, y >> 4, 7));
    });
  } },

  // The duck's leather: a four-petal flower and a diamond on a pebbled ground.
  monogram: { w: 64, h: 64, mime: "image/png", paint(c) {
    c.fill(0, 0, 64, 64, (x, y) => shade(LEATHER, 0.9 + 0.2 * noise(x, y, 3)));
    const petal = (cx, cy, col) => {
      c.ellipse(cx, cy - 4, 3, 4.5, col); c.ellipse(cx, cy + 4, 3, 4.5, col);
      c.ellipse(cx - 4, cy, 4.5, 3, col); c.ellipse(cx + 4, cy, 4.5, 3, col);
      c.ellipse(cx, cy, 2.4, 2.4, GOLD);
    };
    petal(16, 16, GOLD_DEEP);
    petal(48, 48, GOLD_DEEP);
    const diamond = (cx, cy) => {
      for (let dy = -5; dy <= 5; dy++) {
        const w = 5 - Math.abs(dy);
        for (let dx = -w; dx <= w; dx++) c.set(cx + dx, cy + dy, GOLD_DEEP);
      }
    };
    diamond(48, 16);
    diamond(16, 48);
  } },

  sequin: sequinTexture(COPPER),
  // One baked texture per metal: a part colour multiplies the texture, so a copper one
  // cannot be made to read as gold.
  sequinGold: sequinTexture(GOLD_SEQUIN),
  sequinBlack: sequinTexture(BLACK_SEQUIN),
  sequinSilver: sequinTexture(SILVER_SEQUIN),
};

// ---- thumbnail helpers -------------------------------------------------------------------
const S = 64;   // every thumbnail is 64 x 64 on transparent

/** A vertical light-to-dark wash, so a flat colour reads as a rounded object. */
function lit(col) {
  return (x, y, u) => shade(col, 1.18 - 0.42 * u);
}

/** A sequinned surface: the metal underneath, the discs over it. */
function sequinned(base, tex, reflectance = 0.45) {
  // Top as well as the four walls: an untextured face falls back to the flat base colour,
  // and shoulders and shoe-tops are looked down on. The bottom is never seen.
  return { color: base, material: "Foil", reflectance,
    children: AROUND.concat("Top").map((f) => texture(f, tex, 0.55)) };
}

/** Sequinned trousers in any finish. Returns a one-item array, to spread into ITEMS. */
function glitterPants(key, name, base, texName, blurb) {
  return [{
    key, name, kind: "accessory", slot: "legs", blurb,
    uses: [texName],
    model: (tex) => {
      const skin = sequinned(base, tex[texName]);
      const dark = sequinned(shade(base, 0.72), tex[texName], 0.5);
      // The rig's legs are a stud wide and touch in the middle, so trousers over them read
      // as one slab: the dark inseam down each inner face draws the line between them.
      // One box from hip to ankle reads as a skirt, so each leg is four tapering segments,
      // with the dark turn-up and knee band breaking the drop where a knee would be.
      const leg = (side) => {
        const inner = side === "Left" ? 0.5 : -0.5;      // toward the middle of the body
        return accessory(key + side, side + "FootAttachment", [
          part("Turnup", [0, 0.13, 0], [1.06, 0.26, 1.08], dark),
          part("Calf", [0, 0.6, 0], [1.05, 0.72, 1.05], skin),
          part("Knee", [0, 1.04, 0], [1.09, 0.18, 1.09], dark),
          part("Thigh", [0, 1.52, 0], [1.14, 0.82, 1.12], skin),
          part("Inseam", [inner * 0.56, 0.9, 0], [0.08, 1.6, 1.02],
            { color: shade(base, 0.35), material: "Fabric" }),
        ]);
      };
      return outfit(key, [
        leg("Left"),
        leg("Right"),
        accessory(key + "Waist", "WaistCenterAttachment", [
          part("Seat", [0, -0.1, 0.02], [2.2, 0.5, 1.18], skin),
          part("Waistband", [0, 0.2, 0], [2.24, 0.3, 1.2], dark),
          part("Buckle", [0, 0.2, -0.6], [0.28, 0.24, 0.06],
            { color: shade(base, 1.5), material: "Metal", reflectance: 0.6 }),
        ]),
      ]);
    },
    thumb(c) {
      for (const x of [14, 34])
        c.fill(x, 12, x + 16, 56, (px, py, u, v) => shade(base, 1.12 - 0.32 * v));
      c.fill(12, 8, 52, 18, (px, py, u, v) => shade(base, 0.92 - 0.2 * v));
      for (let i = 0; i < 150; i++) {
        const px = 12 + Math.floor(noise(i, 1, 3) * 40);
        const py = 8 + Math.floor(noise(i, 2, 4) * 48);
        if (px > 30 && px < 34 && py > 18) continue;
        c.set(px, py, noise(i, 3, 5) > 0.78 ? [255, 248, 232] : shade(base, 1.45));
      }
    },
  }];
}

/** A sequinned coat: open over a black shirt or zipped, hooded or not. */
function glitterCoat(key, name, base, texName, blurb, opts = {}) {
  return [{
    key, name, kind: "accessory", slot: "chest", blurb,
    uses: [texName],
    model: (tex) => {
      const skin = sequinned(base, tex[texName], 0.5);
      const body = [
        part("Back", [0, -1.0, 0.34], [2.08, 2.04, 0.42], skin),
        part("SideLeft", [-0.95, -1.0, 0.0], [0.2, 2.04, 0.72], skin),
        part("SideRight", [0.95, -1.0, 0.0], [0.2, 2.04, 0.72], skin),
        // Close the strip the back and front panels leave open across the top of the torso.
        // Two pads, not one yoke: y 0 is the top of the torso and a yoke would meet the head.
        part("ShoulderLeft", [-0.705, -0.09, 0], [0.71, 0.22, 1.12], skin),
        part("ShoulderRight", [0.705, -0.09, 0], [0.71, 0.22, 1.12], skin),
      ];
      if (opts.open) {
        body.push(part("PanelLeft", [-0.66, -1.0, -0.36], [0.76, 2.04, 0.38], skin));
        body.push(part("PanelRight", [0.66, -1.0, -0.36], [0.76, 2.04, 0.38], skin));
        // The torso's front face is at z -0.5; a shirt behind it shows the body in the gap.
        body.push(part("Shirt", [0, -1.0, -0.57], [0.64, 2.0, 0.16], { color: DRESS_BLACK, material: "Fabric" }));
      } else {
        body.push(part("Front", [0, -1.0, -0.36], [2.08, 2.04, 0.38], skin));
        body.push(part("Zip", [0, -1.0, -0.57], [0.1, 1.94, 0.06],
          { color: shade(base, 0.5), material: "Metal", reflectance: 0.5 }));
        body.push(part("Pull", [0, -0.2, -0.6], [0.14, 0.2, 0.08],
          { color: shade(base, 1.4), material: "Metal", reflectance: 0.7 }));
      }
      if (opts.hood) {
        // Down, on the shoulders behind the neck.
        body.push(part("Hood", [0, 0.06, 0.42], [1.32, 0.72, 0.6], skin));
        body.push(part("HoodLip", [0, 0.34, 0.2], [1.18, 0.24, 0.3],
          sequinned(shade(base, 0.8), tex[texName], 0.5)));
      }
      const pieces = [accessory(key, "NeckAttachment", body)];
      // Cuffs, one per arm: a sleeve hung on the torso would not bend at the elbow.
      for (const side of ["Left", "Right"]) {
        const cuff = opts.blackCuffs
          ? { color: DRESS_BLACK, material: "Fabric" }
          : sequinned(shade(base, 0.8), tex[texName], 0.5);
        pieces.push(accessory(key + "Cuff" + side, side + "GripAttachment", [
          // 1.16 clears the tee's sleeve at 1.08, and the watch strap goes over both. The arm
          // is 2.3 studs up from the grip, so 0.58 leaves the bottom three tenths as a hand.
          part("Cuff", [0, 0.58, 0], [1.16, 0.44, 1.16], cuff),
          // Past the top of the arm, two studs up from the hand, or its top face is left bare.
          part("Sleeve", [0, 1.60, 0], [1.12, 1.62, 1.12], skin),
        ]));
      }
      return outfit(key, pieces);
    },
    thumb(c) {
      c.fill(12, 10, 52, 56, (x, y, u, v) => shade(base, 1.1 - 0.3 * v));
      if (opts.open) {
        c.fill(27, 12, 37, 56, lit(DRESS_BLACK));                 // the shirt in the gap
        c.rect(24, 10, 27, 56, shade(base, 0.7));
        c.rect(37, 10, 40, 56, shade(base, 0.7));
      } else {
        c.rect(31, 10, 33, 56, shade(base, 0.5));                 // the zip, done up
        c.rect(30, 30, 34, 35, shade(base, 1.5));                 // its pull
      }
      if (opts.hood) c.fill(20, 4, 44, 14, (x, y, u, v) => shade(base, 0.95 - 0.2 * v));
      const cuffCol = opts.blackCuffs ? DRESS_BLACK : shade(base, 0.8);
      c.fill(12, 46, 20, 56, lit(cuffCol));
      c.fill(44, 46, 52, 56, lit(cuffCol));
      for (let i = 0; i < 170; i++) {
        const x = 12 + Math.floor(noise(i, 1, 13) * 40);
        const y = 6 + Math.floor(noise(i, 2, 14) * 50);
        if (x > 26 && x < 38) continue;
        c.set(x, y, noise(i, 3, 15) > 0.78 ? [255, 248, 232] : shade(base, 1.45));
      }
    },
  }];
}

// ---- the catalogue -------------------------------------------------------------------
// The nine fish colours in the town's order (demo2 shared/Fish.luau, which follows the
// Fishing contract's species). These RGBs must match that file.
const FISH_COLOURS = [
  ["Red", [214, 40, 44]], ["Magenta", [222, 44, 170]], ["Purple", [132, 58, 204]],
  ["Blue", [44, 96, 222]], ["Cyan", [36, 196, 214]], ["Yellow", [236, 204, 44]],
  ["Orange", [238, 128, 34]], ["Indigo", [72, 52, 160]], ["Green", [52, 172, 72]],
];
/** The fish colours plus white and black: what the plain clothes come in. */
const CLOTHES_COLOURS = [...FISH_COLOURS, ["White", [236, 236, 240]], ["Black", [30, 30, 36]]];
const keyOf = (colour) => colour.toLowerCase();

/** Nipple-pegs in a fish colour: the green pair's geometry, jaws glowing, spring in steel. */
function colourPegs([colour, rgb]) {
  const deep = shade(rgb, 0.72);
  return {
    key: "pegs_" + keyOf(colour),
    name: `${colour} Nipple-Pegs`,
    kind: "accessory",
    slot: "neck",
    blurb: `Not a necklace. They glow ${colour.toLowerCase()}.`,
    model: () => {
      const peg = (side) => {
        const x = side * 0.45;
        const y = 0.25;
        const name = side < 0 ? "Left" : "Right";
        return [
          part(`Jaw${name}Upper`, [x, y + 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(rgb), material: "Neon", orientation: [3, 0, 0],
            children: [glow(rgb, 0.7, 5)],
          }),
          part(`Jaw${name}Lower`, [x, y - 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(deep), material: "Neon", orientation: [-3, 0, 0],
          }),
          part(`Spring${name}`, [x, y, -0.13], [0.11, 0.16, 0.075], {
            color: STEEL, material: "Metal", reflectance: 0.5,
          }),
        ];
      };
      return accessory(`${colour}Clothespins`, "BodyFrontAttachment", [...peg(-1), ...peg(1)]);
    },
    thumb(c) {
      const peg = (cx) => {
        c.fill(cx - 9, 10, cx + 9, 52, (x, y, u, v) => {
          const dx = Math.abs(x + 0.5 - cx);
          const gap = 0.7 + 2.4 * v;
          if (dx < gap || dx > 6.5) return null;
          return shade(v > 0.5 ? rgb : deep, 1.1 - 0.22 * v);
        });
        c.fill(cx - 8, 24, cx + 8, 33, lit(STEEL));
        c.rect(cx - 8, 26, cx + 8, 27, shade(STEEL, 1.35));
        c.rect(cx - 8, 31, cx + 8, 32, shade(STEEL, 0.7));
      };
      peg(19);
      peg(45);
    },
  };
}

/** Sweatpants in a colour: a straight leg each and a waistband. */
function sweatpants([colour, rgb]) {
  const cloth = { color: rgb, material: "Fabric" };
  const band = { color: shade(rgb, 0.8), material: "Fabric" };
  const key = "sweats_" + keyOf(colour);
  return {
    key,
    name: `${colour} Sweatpants`,
    kind: "accessory",
    slot: "legs",
    blurb: "Sweatpants.",
    model: () => {
      // A piece per leg, from its own ankle, so each swings with the leg it is on.
      const leg = (side) => accessory(`Sweats${colour}${side}`, side + "FootAttachment", [
        part("Leg", [0, 0.98, 0], [1.08, 1.92, 1.08], cloth),
      ]);
      return outfit(`Sweats${colour}`, [
        leg("Left"),
        leg("Right"),
        accessory(`Sweats${colour}Waist`, "WaistCenterAttachment", [
          part("Waistband", [0, 0.06, 0], [2.16, 0.42, 1.14], band),
        ]),
      ]);
    },
    thumb(c) {
      c.fill(12, 14, 52, 62, (x, y, u, v) => shade(rgb, 1.08 - 0.25 * v));
      c.fill(10, 6, 54, 16, lit(shade(rgb, 0.8)));
      c.clear(30, 18, 34, 62);
    },
  };
}

/** yourfriend's athletic tee in a colour: a box over the torso and a short sleeve on each arm. */
function athleticTee([colour, rgb]) {
  const cloth = { color: rgb, material: "Fabric" };
  return {
    key: "tee_" + keyOf(colour),
    name: `yourfriend's ${colour} Synthetic Blend Athletic Tee`,
    kind: "accessory",
    slot: "shirt",
    blurb: "A synthetic blend athletic tee.",
    model: () => {
      const pieces = [accessory(`Tee${colour}`, "NeckAttachment", [
        // A hundredth proud of the 2 x 2 x 1 torso; more and it pushes through a jacket.
        part("Body", [0, -1.0, 0], [2.02, 2.0, 1.02], cloth),
      ])];
      // From the arm's own grip, so the sleeve moves with the arm.
      for (const side of ["Left", "Right"]) {
        pieces.push(accessory(`Tee${colour}Sleeve${side}`, side + "GripAttachment", [
          part("Sleeve", [0, 1.82, 0], [1.08, 0.98, 1.08], cloth),   // three tenths up: the grip is the end of a 2.3 arm
        ]));
      }
      return outfit(`Tee${colour}`, pieces);
    },
    thumb(c) {
      c.fill(18, 12, 46, 58, (x, y, u, v) => shade(rgb, 1.08 - 0.22 * v));
      c.fill(6, 12, 18, 28, lit(shade(rgb, 0.92)));
      c.fill(46, 12, 58, 28, lit(shade(rgb, 0.92)));
      c.rect(27, 10, 37, 15, shade(rgb, 0.6));
    },
  };
}

const ITEMS = [
  {
    key: "tophat",
    name: "Top Hat",
    kind: "accessory",
    slot: "head",
    blurb: "Black silk, black grosgrain band.",
    model: () => accessory("TopHat", "HatAttachment", [
      // Sunk into the head, a hexagon narrowing upward: ~1.28 wide at the brim's height
      // against this 1.5, so the head stays hidden.
      part("Crown", [0, 0.45, 0], [1.5, 1.6, 1.5], { color: HAT_FELT, material: "Fabric" }),
      // SmoothPlastic against the crown's Fabric: the gloss is what reads as grosgrain.
      part("Band", [0, -0.10, 0], [1.64, 0.3, 1.64], { color: HAT_RIBBON, material: "SmoothPlastic", reflectance: 0.08 }),
      part("Brim", [0, -0.35, 0], [2.6, 0.2, 2.6], { color: HAT_BRIM, material: "Fabric" }),
    ]),
    thumb(c) {
      c.fill(19, 9, 45, 43, lit(HAT_FELT));           // crown
      c.fill(8, 43, 56, 51, lit(HAT_BRIM));           // brim
      c.fill(17, 33, 47, 43, lit(HAT_RIBBON));        // band
      c.rect(19, 9, 45, 11, shade(HAT_FELT, 1.4));
      c.rect(17, 33, 47, 34, shade(HAT_RIBBON, 2.2));
    },
  },

  {
    key: "wizardhat",
    name: "Wizard Hat",
    kind: "accessory",
    slot: "head",
    blurb: "A tall blue hat with stars on it.",
    // No cone primitive -- Shape is Ball, Block, Cylinder or Wedge -- so stacked cylinders
    // narrow to a point. A Cylinder's axis is X, so each ring is turned a quarter to stand
    // up and its Size is [height, diameter, diameter].
    model: () => {
      const felt = { color: WIZARD_FELT, material: "Fabric" };
      const up = { orientation: [0, 0, 90], material: "Fabric" };
      const RINGS = 7;
      const TOP = 3.1;            // how far the point is above the brim
      // The Top Hat's brim height, so the two hats sit alike on the head.
      const BRIM = -0.35;
      const BASE = BRIM + 0.34;   // where the cone starts, just above the band
      const ringWide = (i) => 1.72 * Math.pow(1 - i / RINGS, 0.78) + 0.1;
      const cone = [];
      for (let i = 0; i < RINGS; i++) {
        // ringWide's 0.78 exponent gives a belly rather than a straight-sided cone.
        const a = i / RINGS, b = (i + 1) / RINGS;
        const wide = ringWide(i);
        const h = (TOP / RINGS) * 1.02;   // a hair of overlap, or the seams show as gaps
        cone.push(part("Cone" + (i + 1), [0, BASE + (a + b) / 2 * TOP, 0], [h, wide, wide],
          { ...up, color: WIZARD_FELT, shape: "Cylinder" }));
      }
      // Neon cubes rolled 45 degrees to read as diamonds, scattered by the golden angle
      // (137.508 degrees) so they wrap the cone with no rows and no bare side. Each sits
      // proud of its ring's face, a known radius because the rings are cylinders.
      const STARS = 18;
      const stars = [];
      for (let k = 0; k < STARS; k++) {
        const f = (k + 0.5) / STARS;                 // 0 at the band, 1 near the point
        const y = BASE + TOP * (0.06 + 0.72 * f);
        const ring = Math.min(RINGS - 1, Math.floor((y - BASE) / TOP * RINGS));
        const size = 0.17 - 0.08 * f;
        const r = ringWide(ring) / 2 + size * 0.2;
        const turn = k * 137.508;
        const rad = turn * Math.PI / 180;
        stars.push(part("Star" + (k + 1),
          [+(r * Math.sin(rad)).toFixed(3), +y.toFixed(3), +(r * Math.cos(rad)).toFixed(3)],
          [+size.toFixed(3), +size.toFixed(3), +size.toFixed(3)],
          { color: GOLD_NEON, material: "Neon", orientation: [0, +(turn % 360).toFixed(1), 45] }));
      }
      return accessory("Wizard Hat", "HatAttachment", [
        part("Brim", [0, BRIM, 0], [0.16, 3.5, 3.5], { ...up, color: WIZARD_FELT, shape: "Cylinder" }),
        part("Band", [0, BRIM + 0.18, 0], [0.26, 1.96, 1.96], { orientation: [0, 0, 90], color: GOLD_DEEP,
          material: "SmoothPlastic", shape: "Cylinder" }),
        ...cone,
        ...stars,
      ]);
    },
    thumb(c) {
      // The triangle narrows the way the stacked discs do.
      for (let y = 8; y < 46; y++) {
        const v = (y - 8) / 38;                     // 0 at the point, 1 at the brim
        const half = Math.round(1 + 16 * Math.pow(v, 1.28));
        for (let x = 32 - half; x <= 32 + half; x++)
          c.set(x, y, shade(WIZARD_FELT, 1.35 - 0.45 * (Math.abs(x - 32) / (half + 0.001))));
      }
      c.fill(8, 46, 56, 51, (x, y, u, v) => shade(WIZARD_FELT, 1.15 - 0.3 * v));   // the brim
      c.fill(15, 43, 49, 46, lit(GOLD_DEEP));                                       // the band
      for (const [x, y, r] of [[33, 14, 1], [29, 20, 1], [36, 23, 1], [27, 29, 1], [34, 31, 2],
                               [40, 36, 1], [23, 38, 1], [30, 40, 1]])
        c.fill(x - r, y - r, x + r, y + r, lit(GOLD_NEON));
    },
  },

  {
    key: "duck",
    name: "Louis",
    kind: "accessory",
    slot: "offhand",
    blurb: "A monogrammed calf-leather duck. Carried, not worn.",
    uses: ["monogram"],
    model: (tex) => accessory("LeatherDuck", "LeftGripAttachment", [
      // Held by the scruff, low enough that the head clears the watch on the same wrist.
      part("Body", [0, -0.75, 0], [1.0, 0.8, 1.45], {
        color: LEATHER, material: "Fabric",
        children: AROUND.map((f) => texture(f, tex.monogram, 0.7)).concat(texture("Top", tex.monogram, 0.7)),
      }),
      part("Neck", [0, -0.28, -0.42], [0.42, 0.7, 0.42], { color: LEATHER, material: "Fabric" }),
      part("Head", [0, 0, -0.52], [0.56, 0.5, 0.6], { color: LEATHER, material: "Fabric" }),
      part("Bill", [0, -0.08, -0.92], [0.38, 0.14, 0.36], { color: [232, 150, 48], material: "SmoothPlastic" }),
      part("EyeLeft", [-0.19, 0.12, -0.74], [0.1, 0.1, 0.1], { color: [16, 12, 10] }),
      part("EyeRight", [0.19, 0.12, -0.74], [0.1, 0.1, 0.1], { color: [16, 12, 10] }),
      part("Tail", [0, -0.52, 0.82], [0.44, 0.34, 0.28], { color: LEATHER_DEEP, material: "Fabric" }),
    ]),
    thumb(c) {
      c.ellipse(31, 40, 20, 13, lit(LEATHER));            // body
      c.tri(46, 34, 58, 26, 50, 44, LEATHER_DEEP);        // tail
      c.ellipse(20, 22, 9, 9, lit(LEATHER));              // head
      c.rect(17, 27, 24, 36, shade(LEATHER, 1.0));        // neck
      c.rect(6, 21, 14, 25, [232, 150, 48]);              // bill
      c.ellipse(18, 19, 2, 2, [16, 12, 10]);              // eye
      // the monogram, twice
      for (const [mx, my] of [[27, 38], [38, 43]]) {
        c.ellipse(mx, my - 3, 2, 3, GOLD_DEEP); c.ellipse(mx, my + 3, 2, 3, GOLD_DEEP);
        c.ellipse(mx - 3, my, 3, 2, GOLD_DEEP); c.ellipse(mx + 3, my, 3, 2, GOLD_DEEP);
        c.ellipse(mx, my, 1.6, 1.6, GOLD);
      }
    },
  },

  {
    key: "rolex",
    name: "Rainbow Diamond Rolex",
    kind: "accessory",
    slot: "wrist",
    blurb: "Gold case, rainbow bezel, four stones. Worn on the left wrist.",
    uses: ["pulse"],
    model: (tex) => {
      // 0.8 sits just over the bloom threshold that flatNeon sits just under, so a stone
      // flares a little; its PointLight stays at 0.1, or the case flares with it.
      const stone = (name, pos, colour) => part(name, pos, [0.055, 0.1, 0.1], {
        color: shade(colour, 0.8), material: "Neon",
        children: [glow(colour, 0.1, 5)],
      });
      // The President bracelet: half-sunk cylinders on each face of the band, a wide polished
      // centre between two satin sides -- no centre on the left face (-X), where the head sits.
      const ROWS = [0.38, 0.52, 0.66], ROW = 0.13, FACE = 0.65;   // on the wrist, just above the hand of a 2.3 arm
      const polished = { color: GOLD, material: "Foil", reflectance: 0.7 };
      const satin = { color: GOLD_DEEP, material: "Metal", reflectance: 0.4 };
      const links = [];
      for (const y of ROWS) {
        for (const face of ["Front", "Back", "Left", "Right"]) {
          for (const [at, d, look] of [[-0.40, 0.20, satin], [0, 0.24, polished], [0.40, 0.20, satin]]) {
            if (face === "Left" && at === 0) continue;
            const alongX = face === "Front" || face === "Back";
            const out = face === "Front" || face === "Left" ? -FACE : FACE;
            links.push(part(`Link${face}${links.length}`, alongX ? [at, y, out] : [out, y, at], [ROW, d, d],
              { ...look, shape: "Cylinder", orientation: [0, 0, 90] }));
          }
        }
      }
      // Both grip attachments share the arms' frame, so on the left arm +X points in at the
      // body: the head is built out along -X, and a viewer facing the dial has +Z on their
      // right -- three o'clock.
      return accessory("RainbowRolex", "LeftGripAttachment", [
        // Four thin plates rather than a box, whose top and bottom would read as a shelf
        // under the wrist. Their inner faces sit a hundredth clear of a 1.16-wide cuff.
        part("BandFront", [0, 0.52, -0.62], [1.30, 0.44, 0.06], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
        part("BandBack", [0, 0.52, 0.62], [1.30, 0.44, 0.06], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
        part("BandLeft", [-0.62, 0.52, 0], [0.06, 0.44, 1.30], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
        part("BandRight", [0.62, 0.52, 0], [0.06, 0.44, 1.30], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
        ...links,
        // No Sparkles: with no sparkle texture the engine falls back to a round particle,
        // so the glint is the stones' own Neon and lights.
        part("Case", [-0.71, 0.52, 0], [0.12, 0.62, 0.62], {
          color: GOLD, material: "Foil", reflectance: 0.7,
        }),
        // The winding crown, at three o'clock: +Z.
        part("Crown", [-0.69, 0.52, 0.35], [0.13, 0.15, 0.09], { color: GOLD, material: "Foil", reflectance: 0.6 }),
        part("Bezel", [-0.775, 0.52, 0], [0.05, 0.66, 0.66], {
          color: [255, 255, 255], material: "SmoothPlastic", reflectance: 0.3,
          children: [decal("Right", tex.pulse)],
        }),
        part("Dial", [-0.81, 0.52, 0], [0.03, 0.44, 0.44], { color: [12, 14, 28], material: "Glass", reflectance: 0.5 }),
        part("MarkTop", [-0.826, 0.7, 0], [0.02, 0.07, 0.04], { color: flatNeon([250, 244, 214]), material: "Neon" }),
        part("MarkBottom", [-0.826, 0.34, 0], [0.02, 0.07, 0.04], { color: flatNeon([250, 244, 214]), material: "Neon" }),
        part("MarkFront", [-0.826, 0.52, -0.17], [0.02, 0.04, 0.07], { color: flatNeon([250, 244, 214]), material: "Neon" }),
        part("MarkBack", [-0.826, 0.52, 0.17], [0.02, 0.04, 0.07], { color: flatNeon([250, 244, 214]), material: "Neon" }),
        // A box points along the axis it is long in: the minute hand long in Y, up to
        // twelve, the hour hand long in Z, across to three.
        part("HandMinute", [-0.832, 0.61, 0], [0.02, 0.18, 0.03], { color: GOLD, material: "Foil", reflectance: 0.6 }),
        part("HandHour", [-0.832, 0.52, 0.065], [0.02, 0.03, 0.13], { color: GOLD, material: "Foil", reflectance: 0.6 }),
        part("Pin", [-0.836, 0.52, 0], [0.02, 0.05, 0.05], { color: GOLD, material: "Foil", reflectance: 0.7 }),
        stone("StoneTop", [-0.8, 0.81, 0], [255, 20, 51]),
        stone("StoneBack", [-0.8, 0.52, 0.28], [179, 31, 255]),
        stone("StoneBottom", [-0.8, 0.23, 0], [31, 120, 255]),
        stone("StoneFront", [-0.8, 0.52, -0.28], [20, 230, 255]),
      ]);
    },
    thumb(c) {
      // One strap, passing behind the case.
      for (const [y0, y1] of [[2, 20], [44, 62]]) {
        c.fill(24, y0, 40, y1, lit(GOLD_DEEP));
        for (let y = y0 + 2; y < y1; y += 4) c.rect(24, y, 40, y + 1, shade(GOLD_DEEP, 0.7));
      }
      c.ellipse(32, 32, 21, 21, lit(GOLD));                // case
      c.ellipse(32, 32, 18, 18, (x, y) => {                // rainbow bezel
        const a = Math.atan2(y + 0.5 - 32, x + 0.5 - 32);
        return ramp(PULSE_STOPS, (a + Math.PI) / (2 * Math.PI));
      });
      c.ellipse(32, 32, 12, 12, [14, 16, 30]);             // dial
      for (const [dx, dy, w, h] of [[0, -9, 1, 3], [0, 9, 1, 3], [-9, 0, 3, 1], [9, 0, 3, 1]])
        c.rect(32 + dx - w, 32 + dy - h, 32 + dx + w, 32 + dy + h, [250, 244, 214]);
      // Ten past ten.
      c.rect(30, 24, 32, 33, [225, 218, 190]);
      c.rect(32, 30, 39, 32, [225, 218, 190]);
      const stones = [[0, -18, [255, 20, 51]], [18, 0, [179, 31, 255]], [0, 18, [31, 120, 255]], [-18, 0, [20, 230, 255]]];
      for (const [dx, dy, colour] of stones) {
        c.ellipse(32 + dx, 32 + dy, 4, 4, shade(colour, 0.7));
        c.ellipse(32 + dx, 32 + dy, 2.6, 2.6, colour);
        c.ellipse(32 + dx, 32 + dy, 1.2, 1.2, [255, 255, 255]);
      }
      c.ellipse(32, 32, 2, 2, lit(GOLD));                  // the pin over the hands
    },
  },

  {
    key: "pants",
    name: "Copper Glitter Pants",
    kind: "accessory",
    slot: "legs",
    blurb: "Every sequin catches the light on its own.",
    uses: ["sequin"],
    model: (tex) => {
      const sequinned = { color: COPPER, material: "Foil", reflectance: 0.45,
        children: AROUND.map((f) => texture(f, tex.sequin, 0.55)) };
      // The rig's leg is 1 x 2 x 1 running up from the foot, and this spans all of it.
      const leg = (side) => accessory("SequinPants" + side, side + "FootAttachment", [
        part("Leg", [0, 0.98, 0], [1.08, 1.92, 1.08], sequinned),
      ]);
      return outfit("SequinPants", [
        leg("Left"),
        leg("Right"),
        // Over the top of both legs, so the hip joint has no seam to show through.
        accessory("SequinPantsWaist", "WaistCenterAttachment", [
          part("Waistband", [0, 0.06, 0], [2.16, 0.42, 1.14], {
            color: shade(COPPER, 0.7), material: "Foil", reflectance: 0.5,
            children: AROUND.map((f) => texture(f, tex.sequin, 0.55)),
          }),
        ]),
      ]);
    },
    thumb(c) {
      const sequins = (x0, y0, x1, y1) => c.fill(x0, y0, x1, y1, (x, y) => {
        const cx = Math.round(x / 5) * 5, cy = Math.round(y / 5) * 5;
        const d = Math.hypot(x - cx, y - cy), l = noise(cx, cy, 5);
        if (d > 2.4) return shade(COPPER, 0.5);
        return l > 0.87 ? [255, 246, 230] : shade(COPPER, 0.7 + l * 0.8);
      });
      sequins(12, 14, 52, 62);
      c.fill(10, 6, 54, 16, lit(shade(COPPER, 0.75)));      // waistband
      c.clear(30, 18, 34, 62);                              // the gap between the legs
    },
  },

  {
    key: "tuxpants",
    name: "Black Tux Trousers",
    kind: "accessory",
    slot: "legs",
    blurb: "The other half of the tux. Plain black, no sequins, no argument.",
    // The glitter trousers in Plastic, not SmoothPlastic: 0.85 rough against 0.25, so the
    // leg does not shine.
    model: () => {
      const cloth = { color: [16, 16, 19], material: "Plastic" };
      const leg = (side) => accessory("TuxTrouser" + side, side + "FootAttachment", [
        part("Leg", [0, 0.98, 0], [1.08, 1.92, 1.08], cloth),
      ]);
      return outfit("TuxTrousers", [
        leg("Left"),
        leg("Right"),
        accessory("TuxTrousersWaist", "WaistCenterAttachment", [
          part("Waistband", [0, 0.06, 0], [2.16, 0.42, 1.14], { color: [10, 10, 12], material: "Plastic" }),
        ]),
      ]);
    },
    thumb(c) {
      c.fill(12, 14, 52, 62, lit([22, 22, 26]));
      c.fill(10, 6, 54, 16, lit([14, 14, 17]));             // waistband
      // the satin stripe down each outside seam
      c.rect(15, 16, 17, 62, [44, 44, 52]);
      c.rect(47, 16, 49, 62, [44, 44, 52]);
      c.clear(30, 18, 34, 62);                              // the gap between the legs
    },
  },

  {
    key: "pegs",
    name: "Green Nipple-Pegs",
    kind: "accessory",
    slot: "neck",
    blurb: "Not a necklace. They glow.",
    // No Shirt class in this runtime (no r.add("Shirt") in rbx_instance), so chest items
    // hang off the torso's BodyFrontAttachment.
    model: () => {
      const peg = (side) => {
        const x = side * 0.45;
        const y = 0.25;                 // mid-chest on a torso that runs -1 to 1
        const name = side < 0 ? "Left" : "Right";
        return [
          part(`Jaw${name}Upper`, [x, y + 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(PEG), material: "Neon", orientation: [3, 0, 0],
            children: [glow(PEG, 0.7, 5)],
          }),
          part(`Jaw${name}Lower`, [x, y - 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(PEG_DEEP), material: "Neon", orientation: [-3, 0, 0],
          }),
          part(`Spring${name}`, [x, y, -0.13], [0.11, 0.16, 0.075], {
            color: STEEL, material: "Metal", reflectance: 0.5,
          }),
        ];
      };
      return accessory("Clothespins", "BodyFrontAttachment", [...peg(-1), ...peg(1)]);
    },
    thumb(c) {
      // Drawn side on
      const peg = (cx) => {
        c.fill(cx - 9, 10, cx + 9, 52, (x, y, u, v) => {
          const dx = Math.abs(x + 0.5 - cx);
          const gap = 0.7 + 2.4 * v;           // the jaws open toward the tip
          if (dx < gap || dx > 6.5) return null;
          return shade(v > 0.5 ? PEG : PEG_DEEP, 1.1 - 0.22 * v);
        });
        c.fill(cx - 8, 24, cx + 8, 33, lit(STEEL));
        c.rect(cx - 8, 26, cx + 8, 27, shade(STEEL, 1.35));
        c.rect(cx - 8, 31, cx + 8, 32, shade(STEEL, 0.7));
      };
      peg(19);
      peg(45);
    },
  },

  {
    key: "goldpegs",
    name: "Gold Nipple-Pegs",
    kind: "accessory",
    slot: "neck",
    blurb: "The same idea, in glowing gold.",
    // The green pair's geometry in a different metal.
    model: () => {
      const peg = (side) => {
        const x = side * 0.45;
        const y = 0.25;                 // mid-chest on a torso that runs -1 to 1
        const name = side < 0 ? "Left" : "Right";
        return [
          part(`Jaw${name}Upper`, [x, y + 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(GOLD_NEON), material: "Neon", orientation: [3, 0, 0],
            children: [glow(GOLD_NEON, 0.8, 5)],
          }),
          part(`Jaw${name}Lower`, [x, y - 0.045, -0.17], [0.09, 0.07, 0.34], {
            color: flatNeon(GOLD_NEON_DEEP), material: "Neon", orientation: [-3, 0, 0],
          }),
          // Foil, not Neon: the spring is the one piece that does not glow.
          part(`Spring${name}`, [x, y, -0.13], [0.11, 0.16, 0.075], {
            color: GOLD_DEEP, material: "Foil", reflectance: 0.6,
          }),
        ];
      };
      return accessory("GoldClothespins", "BodyFrontAttachment", [...peg(-1), ...peg(1)]);
    },
    thumb(c) {
      // Drawn side on, like the green pair
      const peg = (cx) => {
        c.fill(cx - 9, 10, cx + 9, 52, (x, y, u, v) => {
          const dx = Math.abs(x + 0.5 - cx);
          const gap = 0.7 + 2.4 * v;           // the jaws open toward the tip
          if (dx < gap || dx > 6.5) return null;
          return shade(v > 0.5 ? GOLD_NEON : GOLD_NEON_DEEP, 1.1 - 0.22 * v);
        });
        c.fill(cx - 8, 24, cx + 8, 33, lit(GOLD_DEEP));
        c.rect(cx - 8, 26, cx + 8, 27, shade(GOLD_NEON, 1.35));
        c.rect(cx - 8, 31, cx + 8, 32, shade(GOLD_DEEP, 0.7));
      };
      peg(19);
      peg(45);
    },
  },

  // Every fish colour but green, which the pair above already covers.
  ...FISH_COLOURS.filter(([colour]) => colour !== "Green").map(colourPegs),

  ...CLOTHES_COLOURS.map(sweatpants),
  ...CLOTHES_COLOURS.map(athleticTee),

  {
    key: "wig",
    name: "Maria Wig",
    kind: "accessory",
    slot: "head",
    blurb: "Combed across from a side parting, high at the brow, past the jaw.",
    // The head hangs below worn space's origin: a hexagon from y 0 down to -1.73, two studs
    // across at its widest (y -0.87) and one at the crown. A combover, so each layer below
    // the crown sits further back, leaving the forehead bare.
    model: () => {
      const parts = [
        // First, so it is the Handle: centred and unrotated, where the comb carries a roll
        // and a turned Handle would throw every sibling the other way.
        part("CapUpper", [0, -0.26, 0.14], [1.42, 0.24, 0.84], { color: HAIR, material: "Fabric" }),
        // The long side of the parting, on the scalp rather than in it: the head runs down
        // from y 0. Reaches the back of the skull (z +0.50) and down to meet CapUpper, or a
        // bald stripe opens across the back of the crown.
        part("Comb", [0.16, 0.00, 0.06], [0.90, 0.30, 1.06], {
          color: HAIR_LIT, material: "Fabric", orientation: [0, 0, 3],
        }),
        // The short side of the parting.
        part("PartLeft", [-0.46, -0.01, 0.06], [0.34, 0.28, 1.06], {
          color: HAIR_LIT, material: "Fabric", orientation: [0, 0, -2],
        }),
        // The hairline, high across the top third of the face so the brow stays clear, and
        // asymmetric -- to y -0.45 on the long side, -0.29 on the short -- so it slants.
        part("HairlineLong", [0.20, -0.22, -0.50], [1.10, 0.46, 0.10], {
          color: HAIR_LIT, material: "Fabric", orientation: [0, 0, 8],
        }),
        part("HairlineShort", [-0.52, -0.14, -0.50], [0.40, 0.30, 0.10], {
          color: HAIR_LIT, material: "Fabric", orientation: [0, 0, -5],
        }),
        // Down the outer third of the forehead to brow height, leaving x -0.45 to 0.45
        // clear. One temple only, on the side the hair is combed towards.
        part("TempleRight", [0.68, -0.55, -0.50], [0.30, 0.78, 0.10], {
          color: HAIR, material: "Fabric", orientation: [0, 0, 8],
        }),
        part("CapMid", [0, -0.50, 0.26], [1.72, 0.26, 0.76], { color: HAIR, material: "Fabric" }),
        part("CapWide", [0, -0.78, 0.34], [2.02, 0.32, 0.68], { color: HAIR_DEEP, material: "Fabric" }),
        // The length, to the shoulder. Its front edge stays back of z -0.30, or it lies
        // along the cheek instead.
        part("SideLeft", [-0.94, -1.66, 0.32], [0.32, 1.94, 0.86], { color: HAIR, material: "Fabric" }),
        part("SideRight", [0.94, -1.66, 0.32], [0.32, 1.94, 0.86], { color: HAIR, material: "Fabric" }),
        part("Back", [0, -1.66, 0.60], [1.80, 1.94, 0.30], { color: HAIR_DEEP, material: "Fabric" }),
      ];
      return accessory("Wig", "HatAttachment", parts);
    },
    // The model itself (scripts/model-view.js), so the shelf cannot disagree with the
    // geometry.
    thumb(c) {
      const view = require("./model-view");
      view.draw(c, this.model({}), { view: "front", pad: 5 });
    },
  },

  {
    key: "cane",
    name: "Gold-Topped Cane",
    kind: "accessory",
    slot: "mainhand",
    blurb: "Ebony shaft, gold knob. Carried in the right hand.",
    model: () => accessory("Cane", "RightGripAttachment", [
      // Sized so the ferrule stops just above the ground from a 2.3-stud arm; longer and
      // the tip goes through the floor.
      part("Shaft", [0, -0.70, 0], [0.15, 1.7, 0.15], { color: [18, 18, 22], material: "SmoothPlastic", reflectance: 0.15 }),
      part("Knob", [0, 0.28, 0], [0.34, 0.34, 0.34], { color: GOLD, material: "Foil", reflectance: 0.6, shape: "Ball" }),
      part("Collar", [0, 0.06, 0], [0.21, 0.13, 0.21], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
      part("Ferrule", [0, -1.5, 0], [0.18, 0.16, 0.18], { color: GOLD_DEEP, material: "Foil", reflectance: 0.5 }),
    ]),
    thumb(c) {
      c.fill(29, 12, 35, 58, lit([18, 18, 22]));
      c.rect(30, 12, 31, 58, [64, 64, 74]);
      c.ellipse(32, 10, 8, 8, lit(GOLD));                   // knob
      c.ellipse(30, 7, 2.5, 2.5, [255, 240, 190]);
      c.fill(28, 17, 36, 21, lit(GOLD_DEEP));               // collar
      c.fill(28, 55, 36, 60, lit(GOLD_DEEP));               // ferrule
    },
  },

  {
    key: "tux",
    name: "Cut-off Black Tux",
    kind: "accessory",
    slot: "chest",
    blurb: "Satin lapels, white dress shirt, bow tie.",
    model: () => accessory("Tux", "NeckAttachment", [
      part("Jacket", [0, -1.0, 0], [2.08, 2.04, 1.1], { color: TUX_BLACK, material: "Fabric" }),
      part("ShirtFront", [0, -0.78, -0.58], [0.62, 1.16, 0.06], { color: SHIRT, material: "SmoothPlastic" }),
      part("LapelLeft", [-0.44, -0.66, -0.585], [0.32, 1.0, 0.05], { color: TUX_SATIN, material: "SmoothPlastic", reflectance: 0.12 }),
      part("LapelRight", [0.44, -0.66, -0.585], [0.32, 1.0, 0.05], { color: TUX_SATIN, material: "SmoothPlastic", reflectance: 0.12 }),
      part("BowTie", [0, -0.2, -0.6], [0.5, 0.19, 0.09], { color: TUX_SATIN, material: "SmoothPlastic", reflectance: 0.12 }),
      part("BowKnot", [0, -0.2, -0.62], [0.12, 0.13, 0.06], { color: [8, 8, 12], material: "SmoothPlastic" }),
      part("ButtonUpper", [0, -1.05, -0.62], [0.09, 0.09, 0.05], { color: [10, 10, 14] }),
      part("ButtonLower", [0, -1.32, -0.62], [0.09, 0.09, 0.05], { color: [10, 10, 14] }),
    ]),
    thumb(c) {
      c.fill(8, 8, 56, 60, lit(TUX_BLACK));                 // jacket
      c.fill(27, 10, 37, 58, lit(SHIRT));                   // shirt front
      // Lapels, lighter here than the model's near-black, or the tile is one black square.
      c.tri(27, 10, 27, 42, 15, 13, [62, 62, 74]);
      c.tri(37, 10, 37, 42, 49, 13, [62, 62, 74]);
      // bow tie, on the white shirt
      c.tri(32, 24, 24, 19, 24, 29, [10, 10, 14]);
      c.tri(32, 24, 40, 19, 40, 29, [10, 10, 14]);
      c.rect(30, 21, 34, 27, [8, 8, 12]);                   // its knot
      c.ellipse(32, 40, 2, 2, [24, 24, 30]);                // buttons
      c.ellipse(32, 48, 2, 2, [24, 24, 30]);
    },
  },

  // ---- the glitter wardrobe -------------------------------------------------------------
  ...glitterPants("goldpants", "Gold Glitter Trousers", GOLD_SEQUIN, "sequinGold",
    "Gold sequins, ankle to hip."),
  ...glitterPants("blackpants", "Maria Glitter Pants", BLACK_SEQUIN, "sequinBlack",
    "Black sequins. They glint white, which is most of what makes them sequins."),

  ...glitterCoat("goldcoat", "Gold Glitter Suit Coat", GOLD_SEQUIN, "sequinGold",
    "Worn open over a black dress shirt.", { hood: false, blackCuffs: false, open: true }),
  ...glitterCoat("mariajacket", "Maria Glitter Jacket", SILVER_SEQUIN, "sequinSilver",
    "Platinum sequins, zipped, hood down, black at the cuffs.", { hood: true, blackCuffs: true, open: false }),

  {
    key: "goldshoes",
    name: "Gold Glitter Dress Shoes",
    kind: "accessory",
    slot: "feet",
    blurb: "The first thing in the shop that goes on your feet.",
    uses: ["sequinGold"],
    // Carried by the item rather than shared: nothing else wants a flat red square.
    images: { soleRed: () => solidImage(SOLE_RED) },
    // Worn space starts at the ankle, so the shoe hangs below it and reaches forward.
    model: (tex) => outfit("GoldShoes", ["Left", "Right"].map((side) =>
      accessory("GoldShoe" + side, side + "FootAttachment", [
        // The rig has no feet: the leg stops at y 0 and stands there. The red is a decal on
        // the Bottom face, which has no sides to wrap round into a rim, and the sole is
        // inset inside the shoe and reaches below y 0, or it z-fights the leg's own bottom.
        part("Sole", [0, 0.02, -0.08], [1.06, 0.16, 1.36],
          Object.assign(sequinned(GOLD_SEQUIN, tex.sequinGold, 0.45),
            { children: [decal("Bottom", tex.soleRed)] })),
        part("Shoe", [0, 0.3, -0.08], [1.1, 0.42, 1.4], sequinned(GOLD_SEQUIN, tex.sequinGold, 0.5)),
        // Past the leg, or the shoe reads as an ankle cuff.
        part("Toe", [0, 0.18, -0.78], [0.94, 0.3, 0.42], sequinned(GOLD_SEQUIN, tex.sequinGold, 0.6)),
        part("Heel", [0, 0.14, 0.5], [0.96, 0.3, 0.28], sequinned(GOLD_SEQUIN, tex.sequinGold, 0.55)),
      ]))),
    thumb(c) {
      // Drawn side on
      c.fill(8, 34, 54, 48, (x, y, u, v) => shade(GOLD_SEQUIN, 1.15 - 0.3 * v));
      c.fill(6, 46, 56, 52, lit(SOLE_RED));
      c.fill(38, 30, 52, 40, (x, y, u, v) => shade(GOLD_SEQUIN, 1.2 - 0.3 * v));
      for (let i = 0; i < 60; i++) {
        const x = 8 + Math.floor(noise(i, 1, 7) * 46);
        const y = 32 + Math.floor(noise(i, 2, 8) * 14);
        c.set(x, y, noise(i, 3, 9) > 0.7 ? [255, 246, 226] : shade(GOLD_SEQUIN, 1.5));
      }
    },
  },

  {
    key: "blackshoes",
    name: "Black Dress Shoes",
    kind: "accessory",
    slot: "feet",
    blurb: "The same shoe with the party taken out of it. Goes with everything.",
    // The gold pair's geometry, unglittered.
    model: () => outfit("BlackShoes", ["Left", "Right"].map((side) =>
      accessory("BlackShoe" + side, side + "FootAttachment", [
        // Below the leg's end at y 0, like the gold pair's.
        part("Sole", [0, 0.02, -0.1], [1.14, 0.18, 1.52], { color: [10, 10, 12], material: "SmoothPlastic" }),
        // Plastic, not SmoothPlastic: 0.85 rough rather than 0.25.
        part("Shoe", [0, 0.3, -0.08], [1.1, 0.42, 1.4], { color: SHOE_BLACK, material: "Plastic" }),
        part("Toe", [0, 0.18, -0.78], [0.94, 0.3, 0.42], { color: SHOE_BLACK, material: "Plastic" }),
        part("Heel", [0, 0.14, 0.5], [0.96, 0.3, 0.28], { color: [10, 10, 12], material: "SmoothPlastic" }),
      ]))),
    thumb(c) {
      // Drawn side on, like the gold pair
      c.fill(8, 34, 54, 48, (x, y, u, v) => shade(SHOE_BLACK, 1.5 - 0.5 * v));
      c.fill(6, 46, 56, 52, lit([10, 10, 12]));
      c.fill(38, 30, 52, 40, (x, y, u, v) => shade(SHOE_BLACK, 1.6 - 0.5 * v));
      c.rect(8, 34, 54, 35, shade(SHOE_BLACK, 2.1));
    },
  },

  {
    key: "crudespoon",
    name: "Spoonie",
    // The key is the publisher's content address (item:<key>:<name>), so changing it to
    // follow the name orphans every asset in the manifest and republishes this as a new
    // slot. `previously` is the name a local preview installs it under.
    previously: "Crude Spoon",
    kind: "accessory",
    slot: "mainhand",
    blurb: "A spoon. That is the whole item.",
    // The arm is a stud wide, so anything built along its own axis ends up inside it.
    model: () => {
      const held = { color: STEEL_SPOON, material: "Metal", reflectance: 0.45 };
      // Built along -Z, the way the character faces and the way a rod closed in the fist
      // runs, rather than rotated onto it: an Orientation spins each box about its own
      // centre and leaves the offsets staggered. The butt runs back to z 0.62, an eighth
      // proud of the arm's rear face at 0.5, so the hand reads as closed round the stem.
      return accessory("Spoonie", "RightGripAttachment", [
        part("Butt", [0, 0, 0.51], [0.11, 0.17, 0.22], {
          color: shade(STEEL_SPOON, 0.62), material: "Metal",
        }),
        // "Stem", not "Handle": accessory() renames the first part to Handle, and a second
        // part of that name leaves the engine picking between the two by hash order.
        part("Stem", [0, 0, -0.25], [0.06, 0.1, 1.34], held),
        // No part has a hole, so the rim is an oval less a smaller oval by SubtractAsync;
        // tests/bake_spoonie_rim.gd bakes it to models/spoonie-rim.json. A union scales its
        // geometry to its Size, which is how each oval is stretched where a Part's round
        // shape cannot be; the hole is its own oval rather than the rim scaled down, so the
        // rim stays 0.04 wide at the tip as well as at the sides.
        //
        // The dish is a SpecialMesh cylinder turned to lie along its thickness, 0.002 thick
        // with its back face 0.001 inside the rim's +X face so the two never share a plane,
        // and a touch wider than the hole so its edge tucks under the rim.
        part("Bowl", [0.033, 0, -1.17], [0.28, 0.002, 0.44],
          { ...held, orientation: [0, 0, 90], children: [specialMesh("Cylinder")] }),
        unionPart("Lip", [0, 0, -1.17], SPOONIE_RIM, {
          color: shade(STEEL_SPOON, 1.2), material: "Metal", reflectance: 0.6,
        }),
      ]);
    },
    thumb(c) {
      c.rect(0, 0, c.w, c.h, SPOONIE_YELLOW);
      c.ellipse(32, 19, 9, 11, (x, y, u, v) => shade(STEEL_SPOON, 1.45 - 0.3 * v));    // the rim
      c.ellipse(32, 19, 7.6, 9.6, (x, y, u, v) => shade(STEEL_SPOON, 0.8 + 0.2 * v));  // the dish
      c.fill(30, 30, 34, 52, (x, y, u, v) => shade(STEEL_SPOON, 1.16 - 0.3 * v));      // the stem
      c.fill(28, 50, 36, 57, lit(shade(STEEL_SPOON, 0.8)));                            // the butt
      c.rect(31, 30, 32, 52, shade(STEEL_SPOON, 1.5));
    },
  },

  {
    key: "spoonie",
    name: "BFS 9000",
    // The key does not follow the name; see "crudespoon" above.
    previously: "Spoonie",
    kind: "accessory",
    slot: "mainhand",
    blurb: "A two-handed spoon. Cuts the figure eight.",
    // scripts/prep-spoonie.js decimates the mesh to 1,400 triangles, turns it to face the
    // way it is carried, and writes models/spoonie.obj.
    assets: {
      mesh: () => ({
        bytes: fs.readFileSync(path.join(__dirname, "models", "spoonie.obj")),
        mime: "model/obj",
      }),
    },
    model: (uris) => {
      const M = JSON.parse(fs.readFileSync(path.join(__dirname, "models", "spoonie.json"), "utf8"));
      // Where the fist closes on the shaft. A MeshPart is placed by its middle, so the part
      // sits forward of the grip by however far the grip is back along the mesh. A fraction
      // of the shaft, so a length change in prep-spoonie.js keeps the hand in one place.
      const GRIP = M.size[2] * 0.26;
      return accessory("BFS 9000", "RightGripAttachment", [
        // SmoothPlastic, not Metal: Metal on a MeshPart is almost all reflection, and comes
        // out near-black with nothing to reflect.
        meshPart("Shaft", [0, 0, -GRIP], M.size, uris.mesh, {
          color: STEEL_SPOON, material: "SmoothPlastic", reflectance: 0.18,
        }),
      ]);
    },
    // The photograph rather than a render: a 1,400-triangle mesh at 64 pixels is a smear.
    thumb(c) {
      const src = decode(fs.readFileSync(path.join(__dirname, "logos", "spoonie.png")));
      // Cropped to whatever differs from the wall behind it. The wall is lit from a corner,
      // so one background colour would count its lighter side as subject: fit a plane per
      // channel to the border pixels and judge each pixel against the wall where it stands.
      const ring = [];
      for (let x = 0; x < src.w; x += 3)
        for (const y of [0, 1, 2, src.h - 3, src.h - 2, src.h - 1]) {
          const i = (y * src.w + x) * 4;
          ring.push([x, y, src.px[i], src.px[i + 1], src.px[i + 2]]);
        }
      for (let y = 3; y < src.h - 3; y += 3)
        for (const x of [0, 1, 2, src.w - 3, src.w - 2, src.w - 1]) {
          const i = (y * src.w + x) * 4;
          ring.push([x, y, src.px[i], src.px[i + 1], src.px[i + 2]]);
        }
      const plane = [0, 1, 2].map((k) => {   // least squares: v = a + b x + c y
        let sx = 0, sy = 0, sv = 0, sxx = 0, syy = 0, sxy = 0, sxv = 0, syv = 0;
        const n = ring.length;
        for (const r of ring) { const x = r[0], y = r[1], v = r[2 + k]; sx += x; sy += y; sv += v; sxx += x * x; syy += y * y; sxy += x * y; sxv += x * v; syv += y * v; }
        const mx = sx / n, my = sy / n, mv = sv / n;
        const cxx = sxx - n * mx * mx, cyy = syy - n * my * my, cxy = sxy - n * mx * my, cxv = sxv - n * mx * mv, cyv = syv - n * my * mv;
        const det = cxx * cyy - cxy * cxy || 1;
        const b = (cxv * cyy - cyv * cxy) / det, c = (cyv * cxx - cxv * cxy) / det;
        return [mv - b * mx - c * my, b, c];
      });
      const wall = (x, y, k) => plane[k][0] + plane[k][1] * x + plane[k][2] * y;
      let lo = [1e9, 1e9], hi = [-1, -1];
      // The threshold alone passes stray patches of the lit corner, so the subject is the
      // largest connected blob and nothing else.
      const isSubject = new Uint8Array(src.w * src.h);
      for (let y = 0; y < src.h; y++)
        for (let x = 0; x < src.w; x++) {
          const i = (y * src.w + x) * 4;
          const d = Math.max(Math.abs(src.px[i] - wall(x, y, 0)), Math.abs(src.px[i + 1] - wall(x, y, 1)), Math.abs(src.px[i + 2] - wall(x, y, 2)));
          isSubject[y * src.w + x] = d > 22 ? 1 : 0;
        }
      const label = new Int32Array(src.w * src.h);
      let best = 0, bestSize = 0, next = 0;
      const stack = [];
      for (let start = 0; start < isSubject.length; start++) {
        if (!isSubject[start] || label[start]) continue;
        const id = ++next; let size = 0;
        stack.push(start); label[start] = id;
        while (stack.length) {
          const p = stack.pop(); size++;
          const x = p % src.w, y = (p - x) / src.w;
          for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
            const nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= src.w || ny >= src.h) continue;
            const q = ny * src.w + nx;
            if (isSubject[q] && !label[q]) { label[q] = id; stack.push(q); }
          }
        }
        if (size > bestSize) { bestSize = size; best = id; }
      }
      lo = [1e9, 1e9]; hi = [-1, -1];
      for (let y = 0; y < src.h; y++)
        for (let x = 0; x < src.w; x++)
          if (label[y * src.w + x] === best) {
            lo = [Math.min(lo[0], x), Math.min(lo[1], y)];
            hi = [Math.max(hi[0], x), Math.max(hi[1], y)];
          }
      // blit() scales a whole image, so the crop is taken first and handed over as one.
      const cw = hi[0] - lo[0] + 1, ch = hi[1] - lo[1] + 1;
      const cut = { w: cw, h: ch, px: new Uint8Array(cw * ch * 4) };
      for (let y = 0; y < ch; y++)
        for (let x = 0; x < cw; x++) {
          const from = ((lo[1] + y) * src.w + lo[0] + x) * 4, to = (y * cw + x) * 4;
          for (let k = 0; k < 4; k++) cut.px[to + k] = src.px[from + k];
          // Alpha 0 outside the blob rather than red, so blit's averaging leaves the edge
          // soft against the red instead of stepped.
          if (label[(lo[1] + y) * src.w + lo[0] + x] !== best) cut.px[to + 3] = 0;
        }
      c.rect(0, 0, c.w, c.h, BFS_RED);
      const scale = Math.min((c.w - 2) / cw, (c.h - 2) / ch);
      const w = Math.round(cw * scale), h = Math.round(ch * scale);
      blit(c, cut, Math.round((c.w - w) / 2), Math.round((c.h - h) / 2), w, h);
    },
  },

  // ---- torches ------------------------------------------------------------------------
  // One per fire the braziers burn: the item names its fire in a `Flame` attribute and
  // src/shared/Flames.luau holds the colours, multiplying them through a white sprite, so
  // another torch is a row in the table below and no new art. Spoon.server.luau gives a
  // torch the crude spoon's thrust, played back slower.
  ...[
    // key      name          fire      light          tile
    // light: the fire's first colour, for the PointLight, copied because Flames.luau is Luau
    // and a published model has to carry its own paint.
    // tile: the stop the shelf's tile draws its flame with, where a fire of several colours
    // makes the first one wrong.
    ["plstorch",  "PLS Torch",  "pulse",  [255, 10, 60], [150, 20, 245]],
    ["plsxtorch", "PLSX Torch", "pulsex", [0, 255, 60],  [255, 0, 32]],
    ["hextorch",  "HEX Torch",  "hex",    [255, 140, 0]],
    ["prvxtorch", "PRVX Torch", "provex", [250, 80, 4]],
    ["inctorch",  "INC Torch",  "inc",    [0, 255, 30]],
  ].map(([key, name, fire, light, tile]) => ({
    key,
    name,
    kind: "accessory",
    slot: "mainhand",
    blurb: `A ${name.split(" ")[0]} torch. Sets what it touches alight.`,
    model: () => accessory(name, "RightGripAttachment", [
      // Runs back to z 0.6, proud of the arm's rear face at 0.5, so the butt clears the fist.
      part("Haft", [0, 0, -0.42], [0.24, 0.24, 2.1], {
        color: [92, 62, 38], material: "Wood",
      }),
      part("Ferrule", [0, 0, -1.4], [0.32, 0.32, 0.2], {
        color: [150, 152, 160], material: "Metal", reflectance: 0.4,
      }),
      // The bundle, charred rather than coloured, so the fire is the only bright part.
      part("Head", [0, 0, -1.86], [0.5, 0.5, 0.72], {
        color: [26, 24, 24], material: "Slate",
      }),
      // Its own invisible part, so the tongues start at the top of the bundle, not inside it.
      part("Fire", [0, 0.14, -2.12], [0.3, 0.3, 0.3], {
        transparency: 1, children: [flame(1.3), glow(light, 2.4, 14)],
      }),
    ], { attributes: { Flame: fire } }),
    thumb(c) {
      const paint = tile || light;
      c.fill(29, 34, 35, 60, (x, y, u, v) => shade([92, 62, 38], 1.15 - 0.35 * v));  // the haft
      c.fill(27, 31, 37, 35, lit(shade([150, 152, 160], 1.1)));                      // the ferrule
      c.fill(26, 22, 38, 32, lit([26, 24, 24]));                                     // the bundle
      // A tongue narrowing to a point, brightest along its centre line.
      for (let y = 2; y < 26; y++) {
        const v = (y - 2) / 24;                       // 0 at the tip, 1 at the bundle
        const half = Math.round(1 + 7 * Math.pow(v, 0.7));
        for (let x = 32 - half; x <= 32 + half; x++) {
          const across = Math.abs(x - 32) / (half + 0.001);
          c.set(x, y, shade(paint, 1.5 - 0.55 * across));
        }
      }
      c.rect(31, 34, 32, 58, shade([92, 62, 38], 1.5));
    },
  })),

  // ---- candles ------------------------------------------------------------------------
  // One swing each: land a blow and the item is spent. Two-handed, and Spoon.server.luau
  // shares BFS 9000's keyframes for the swing rather than copying them.
  ...[
    // key           name            stick          flame            wick
    ["redcandle",   "Red Candle",   [214, 30, 44],  [255, 96, 74],   [26, 24, 24]],
    ["greencandle", "Green Candle", [40, 196, 74],  [150, 255, 126], [26, 24, 24]],
  ].map(([key, name, stick, fire, wickColour]) => ({
    key,
    name,
    kind: "accessory",
    slot: "mainhand",
    blurb: name === "Red Candle"
      ? "Two hearts off whoever it lands on. Then it is gone."
      : "Two hearts back into whoever it lands on. Then it is gone.",
    model: () => {
      const neon = (colour) => ({ color: colour, material: "Neon" });
      // Built along -Z out of the fist, like every other held item. The off hand takes the
      // shaft 0.85 forward of the grip.
      return accessory(name, "RightGripAttachment", [
        // The butt stands proud of the arm's rear face at z 0.5.
        part("Shaft", [0, 0, -1.8], [0.52, 0.52, 4.8], neon(stick)),
        // Charred: the one part that is not lit.
        part("Wick", [0, 0, -4.32], [0.12, 0.12, 0.3], { color: wickColour, material: "Slate" }),
        // Three Neon balls off the wick, not the shared flame() emitter the torches use: the
        // fire is a fixed shape that never flickers, and the item stays one solid colour.
        part("Flame1", [0, 0, -4.62], [0.52, 0.52, 0.52], { ...neon(fire), shape: "Ball" }),
        part("Flame2", [0, 0, -4.95], [0.34, 0.34, 0.34], { ...neon(fire), shape: "Ball" }),
        part("Flame3", [0, 0, -5.18], [0.19, 0.19, 0.19], { ...neon(fire), shape: "Ball" }),
        glowPart(fire, 2.4, 16, [0, 0, -4.7]),
      ]);
    },
    thumb(c) {
      c.fill(27, 24, 37, 58, (x, y, u, v) => shade(stick, 1.2 - 0.4 * v));   // the candle
      c.rect(30, 24, 31, 57, shade(stick, 1.6));
      c.fill(31, 19, 33, 25, lit(wickColour));                               // the wick
      for (let y = 4; y < 20; y++) {
        const v = (y - 4) / 16;
        const half = Math.round(1 + 5 * Math.pow(v, 0.6));
        for (let x = 32 - half; x <= 32 + half; x++) {
          const across = Math.abs(x - 32) / (half + 0.001);
          c.set(x, y, shade(fire, 1.55 - 0.5 * across));
        }
      }
    },
  })),

  // ---- pets ---------------------------------------------------------------------------
  // Models rather than Accessories: a pet stands in the world instead of welded to a limb.
  // Meshes and textures go on chain like any other asset, and the host caches them to files
  // the engine can load. scripts/prep-pets.js prepares the meshes.
  {
    key: "pup",
    name: "Pup",
    kind: "pet",
    slot: "pet",
    blurb: "PLSPUP, at your heel. Follows you around and gets in the way.",
    // One mesh and one atlas, which carries the face, eyes and brows (scripts/prep-pup.js).
    assets: {
      mesh: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "pup.obj")),
                     mime: "model/obj" }),
      colors: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "pup-colors.png")),
                       mime: "image/png" }),
    },
    model: (tex) => {
      const M = JSON.parse(fs.readFileSync(path.join(__dirname, "models", "pup.json"), "utf8"));
      // 3.25 is a fixed divisor, not this mesh's height -- pup.json has size[1] 3.213, and
      // substituting it resizes the pet.
      const S = 1.56 / 3.25;
      return {
        className: "Model", name: "Pup", properties: { Name: "Pup" },
        children: [
          meshPart("Body", M.mid.map((v) => +(v * S).toFixed(4)), M.size.map((v) => +(v * S).toFixed(4)),
            tex.mesh, {
              // Plastic is 0.85 rough where SmoothPlastic is 0.25, which on a rounded
              // low-poly animal reads as latex.
              texture: tex.colors, material: "Plastic",
            }),
        ],
      };
    },
    // The dog off the PLSPUP badge, already cut out of its disc, ring and banner.
    thumb(c) {
      const src = decode(fs.readFileSync(path.join(__dirname, "logos", "pupdog.png")));
      const scale = Math.min(c.w / src.w, c.h / src.h);
      const w = Math.round(src.w * scale), h = Math.round(src.h * scale);
      blit(c, src, Math.round((c.w - w) / 2), Math.round((c.h - h) / 2), w, h);
    },
  },

  {
    key: "roma",
    name: "White Roma",
    kind: "pet",
    slot: "pet",
    blurb: "Follows you at a crawl, which is the only speed there is room for.",
    // scripts/prep-roma.js cuts the wheels out of the one supplied object: a part turns
    // about its own middle, and a wheel left in the body would turn about the car's. One
    // picture for all five, since every piece keeps its own UVs.
    assets: Object.assign({
      body: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "roma-body.obj")),
                     mime: "model/obj" }),
      colors: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "roma-colors.png")),
                       mime: "image/png" }),
    }, Object.fromEntries(ROMA_WHEELS.map((n) => [n.toLowerCase(), () => ({
      bytes: fs.readFileSync(path.join(__dirname, "models", `roma-${n.toLowerCase()}.obj`)),
      mime: "model/obj",
    })]))),
    model: (tex) => {
      const M = JSON.parse(fs.readFileSync(path.join(__dirname, "models", "roma.json"), "utf8"));
      // 3.9 studs long, about the height of its driver, not the real ratio.
      const S = 3.90 / M.whole.size[2];
      // Offsets from the middle of the whole car: a MeshPart is fitted to Size about its
      // own middle, so the pieces would otherwise stack at the origin.
      const at = (m) => m.mid.map((v, i) => +((v - M.whole.mid[i]) * S).toFixed(4));
      const of = (m) => m.size.map((v) => +(v * S).toFixed(4));
      const skin = { texture: tex.colors, material: "SmoothPlastic" };
      return {
        className: "Model", name: "White Roma", properties: { Name: "White Roma" },
        children: [
          // "Chassis" is load-bearing: the pet runtime picks a gait from a model's part
          // names, as "Wing" means it flies. The mesh arrives Y-up with its front on -Z,
          // which is what a model here wants.
          meshPart("Chassis", at(M.body), of(M.body), tex.body, skin),
        ].concat(M.wheels.map((w) =>
          // Discs on the X axis, so X is the axle and Pets.luau turns them about it.
          meshPart(w.name, at(w), of(w), tex[w.name.toLowerCase()], skin))),
      };
    },
    // The supplied render.
    thumb(c) {
      const src = decode(fs.readFileSync(path.join(__dirname, "logos", "roma-preview.png")));
      const scale = Math.min(c.w / src.w, c.h / src.h);
      const w = Math.round(src.w * scale), h = Math.round(src.h * scale);
      blit(c, src, Math.round((c.w - w) / 2), Math.round((c.h - h) / 2), w, h);
    },
  },

  {
    key: "steven",
    name: "Familiar",
    kind: "pet",
    slot: "pet",
    blurb: "A head with wings. Hovers over your shoulder and says nothing.",
    assets: {
      mesh: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "steven-face.obj")),
                     mime: "model/obj" }),
      skull: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "steven-skull.obj")),
                      mime: "model/obj" }),
      face: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "steven-face.png")),
                     mime: "image/png" }),
      // One mesh per wing per layer: the two wings mirror to flap.
      bodyL: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "wing-bodyL.obj")),
                      mime: "model/obj" }),
      bodyR: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "wing-bodyR.obj")),
                      mime: "model/obj" }),
      rimL: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "wing-rimL.obj")),
                     mime: "model/obj" }),
      rimR: () => ({ bytes: fs.readFileSync(path.join(__dirname, "models", "wing-rimR.obj")),
                     mime: "model/obj" }),
    },
    model: (tex) => {
      // Measurements taken off the prepared meshes by scripts/prep-pets.js.
      const M = JSON.parse(fs.readFileSync(path.join(__dirname, "models", "steven.json"), "utf8"));
      const S_HEAD = 1.24;                             // how tall the head is worn
      const S = S_HEAD / M.face.size[1];
      const scaled = (size, k) => size.map((n) => +(n * k).toFixed(4));
      const off = (a, b, k) => [0, 1, 2].map((i) => +((a.mid[i] - b.mid[i]) * k).toFixed(4));

      // The wings keep the supplied fairy model's own spacing and placement: that model's
      // head is 2 units tall, so this scale and each mesh's own centre put them where it
      // does.
      const WING_SCALE = S_HEAD / 2.0;
      // Named WingL / WingR so Pets.luau finds them and swings each side the opposite way.
      const wingPart = (name, m, mesh, colour, clear) =>
        meshPart(name, m.mid.map((n) => +(n * WING_SCALE).toFixed(4)),
          m.size.map((n) => +(n * WING_SCALE).toFixed(4)), mesh, {
            // Not Neon: under the town's bloom a Neon wing is a white flare.
            color: colour, material: "SmoothPlastic", transparency: clear,
          });

      return {
        className: "Model", name: "Familiar", properties: { Name: "Familiar" },
        children: [
          // The back of the skull has no UVs, so it takes a flat colour. Each half is sized
          // from its own measurements at one scale and offset by the gap between the two
          // centres: sized alike, the 0.19-deep shell stretches to 0.66 and sinks into the
          // face.
          meshPart("Skull", off(M.skull, M.face, S), scaled(M.skull.size, S), tex.skull, {
            // Matte, as the pup is.
            color: [58, 44, 36], material: "Plastic",
          }),
          meshPart("Head", [0, 0, 0], scaled(M.face.size, S), tex.mesh, {
            texture: tex.face, material: "Plastic",
            children: [
              // A light rather than glow baked into the texture, so it carries onto
              // whatever the pet floats past.
              { className: "PointLight", name: "Glow", properties: {
                Color: { Color3uint8: GLOW }, Brightness: 1.6, Range: 9 } },
              // Smoke out of the open underside. On an Attachment because an emitter takes
              // its place from whatever it hangs on, and the head's own centre is inside
              // the skull.
              {
                className: "Attachment", name: "NeckVent",
                properties: { Position: [0, -0.5, 0.04] },
                children: [
                  {
                    className: "ParticleEmitter", name: "NeckSmoke",
                    properties: {
                      // LightEmission 1, or it reads as a grey puff tinted violet.
                      Color: { ColorSequence: [0.34, 0.09, 0.92] },
                      LightEmission: 1,
                      // Sized to the opening, about a fifth of the head across.
                      Size: { NumberSequence: [0.22, 0.46] },
                      Transparency: { NumberSequence: [0.25, 1] },
                      Lifetime: { NumberRange: [0.6, 1.1] },
                      Rate: 24,
                      Speed: { NumberRange: [0.3, 0.8] },
                      SpreadAngle: [25, 25],
                      EmissionDirection: "Bottom",
                      // Drag over acceleration, so the smoke hangs in the hole rather than
                      // trailing behind a pet that keeps moving.
                      Drag: 2,
                      Acceleration: [0, -0.6, 0],
                      LockedToPart: true,
                    },
                  },
                ],
              },
            ],
          }),
          // A membrane and a lit rim, per side.
          wingPart("WingL", M.wing_bodyL, tex.bodyL, WING, 0.34),
          wingPart("WingR", M.wing_bodyR, tex.bodyR, WING, 0.34),
          wingPart("WingLRim", M.wing_rimL, tex.rimL, WING_RIM, 0.1),
          wingPart("WingRRim", M.wing_rimR, tex.rimR, WING_RIM, 0.1),
        ],
      };
    },
    // The model itself, through the renderer scripts/render-pet.js uses.
    thumb(c) {
      const view = require("./mesh-view");
      const uris = Object.fromEntries(Object.keys(this.assets).map((n) => [n, n]));
      // back: true is a half turn about the vertical, not a mirror: the model faces the way
      // the game faces, which is away from this camera.
      view.draw(c, this.model(uris), MESH_FILES.steven, { pad: 2, back: true });
    },
  },

];

// ---- capes ---------------------------------------------------------------------------
// One white cape per emblem. The emblem is the item's own asset, since no two capes share.
const CAPE_CLOTH = [242, 242, 246];

for (const [key, emblem] of Object.entries(EMBLEMS)) {
  ITEMS.push({
    key: "cape_" + key,
    name: emblem.name,
    kind: "accessory",
    slot: "back",
    blurb: emblem.blurb,
    // Published with the item and handed back as `tex.emblem`.
    images: { emblem: () => emblemImage(key).png },
    model: (tex) => accessory(emblem.name.replace(/[^A-Za-z0-9]/g, ""), "BodyBackAttachment", [
      // BodyBackAttachment is the middle of the back, so the cloth is pushed up until its
      // top edge is level with the top of a 2-high torso: -0.25 plus half of 2.5. The taper
      // is two leaning strips, set in by 0.02 so no corner passes the cape's edge. The
      // emblem goes on Back only; Front faces the body.
      part("Cape", [0, -0.25, 0.14], [1.9, 2.5, 0.08], {
        color: CAPE_CLOTH, material: "Fabric",
        children: [decal("Back", tex.emblem)],
      }),
      part("EdgeLeft", [-0.93, -0.25, 0.14], [0.16, 2.28, 0.07], {
        color: CAPE_CLOTH, material: "Fabric", orientation: [0, 0, -5],
      }),
      part("EdgeRight", [0.93, -0.25, 0.14], [0.16, 2.28, 0.07], {
        color: CAPE_CLOTH, material: "Fabric", orientation: [0, 0, 5],
      }),
    ]),
    thumb(c) {
      c.fill(8, 6, 56, 60, (x, y) => {
        const t = (y - 6) / 54;                       // 0 at the shoulders, 1 at the hem
        const half = 14 + 7 * t;
        return Math.abs(x + 0.5 - 32) <= half ? shade(CAPE_CLOTH, 1.02 - 0.2 * t) : null;
      });
      // Decoded from the PNG that goes on chain, so a logo dropped into scripts/logos
      // reaches the tile too.
      const art = decode(emblemImage(key).png);
      blit(c, art, 11, 12, 42, 47);
    },
  });
}

// A white edge around anything too dark to see: thumbnails are painted on transparency and
// shown against the shop panel's dark blue gradient. The edge pixels are collected first and
// painted after, or the outline feeds on itself and grows a second ring.
const DARK = 70;         // luma out of 255; below this it vanishes against the panel
const EDGE = [255, 255, 255];

function outlineDark(c) {
  const { w, h, px } = c;
  const at = (x, y) => (y * w + x) * 4;
  const darkHere = (x, y) => {
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    const i = at(x, y);
    if (px[i + 3] < 128) return false;
    return px[i] * 0.299 + px[i + 1] * 0.587 + px[i + 2] * 0.114 < DARK;
  };
  const edge = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (px[at(x, y) + 3] >= 128) continue;        // only paint into empty space
      if (darkHere(x - 1, y) || darkHere(x + 1, y) || darkHere(x, y - 1) || darkHere(x, y + 1) ||
          darkHere(x - 1, y - 1) || darkHere(x + 1, y - 1) ||
          darkHere(x - 1, y + 1) || darkHere(x + 1, y + 1)) edge.push(at(x, y));
    }
  }
  for (const i of edge) {
    px[i] = EDGE[0]; px[i + 1] = EDGE[1]; px[i + 2] = EDGE[2]; px[i + 3] = 255;
  }
  return edge.length;
}

/** Paints one item's 64px thumbnail. */
function thumbnail(item) {
  const c = new Canvas(S);
  item.thumb(c);
  outlineDark(c);
  return c.toPNG();
}

/** A flat square of one colour. */
function solidImage(color, size = 8) {
  const c = new Canvas(size, size);
  c.rect(0, 0, size, size, color);
  return c.toPNG();
}

/** Paints one shared texture from TEXTURES. */
function textureImage(key) {
  const t = TEXTURES[key];
  const c = new Canvas(t.w, t.h);
  t.paint(c);
  return c.toPNG();
}

// ---- the holdings ladder ---------------------------------------------------------------
// The rung an item is claimed at, written as the PLS it takes to stand there rather than as
// an index 0..5: contracts/Inventory.sol gates `add` on msg.sender.balance against these
// numbers, which is a holding and not a payment. scripts/deploy-inventory.js deploys RUNGS.
const RUNGS = [5, 10, 20, 30, 40, 50];

const TIERS = {
  cape_pulse: 5, cape_pulsex: 5, cape_hex: 5, cape_inc: 5, cape_pdai: 5,
  cape_provex: 5, cape_coexist: 5, cape_plspup: 5, cape_orange: 5, cape_n414: 5,
  cape_hearts: 5,

  crudespoon: 10, plstorch: 10, plsxtorch: 10, hextorch: 10, prvxtorch: 10,
  inctorch: 10, pegs: 10, wizardhat: 10,

  spoonie: 20, tophat: 20, pants: 20, blackshoes: 20, tuxpants: 20,

  redcandle: 30, greencandle: 30, pup: 30, goldpegs: 30, tux: 30, duck: 30,
  // The Maria set, on one rung so it is claimed as a set.
  wig: 30, blackpants: 30, mariajacket: 30,

  steven: 40, goldshoes: 40, cane: 40,

  roma: 50, goldcoat: 50, goldpants: 50, rolex: 50,

  // The colours: pegs with the green pair, plain clothes at the first rung.
  ...Object.fromEntries(FISH_COLOURS.filter(([c]) => c !== "Green").map(([c]) => ["pegs_" + keyOf(c), 10])),
  ...Object.fromEntries(CLOTHES_COLOURS.map(([c]) => ["sweats_" + keyOf(c), 5])),
  ...Object.fromEntries(CLOTHES_COLOURS.map(([c]) => ["tee_" + keyOf(c), 5])),
};

for (const item of ITEMS) {
  const pls = TIERS[item.key];
  if (pls === undefined) throw new Error(`catalogue: ${item.key} has no rung`);
  item.tierPls = pls;
  item.tier = RUNGS.indexOf(pls);
  if (item.tier < 0) throw new Error(`catalogue: ${item.key} wants ${pls} PLS, which is not a rung`);
}

module.exports = {
  MESH_FILES, ITEMS, TEXTURES, PULSE_STOPS, RUNGS, TIERS,
  thumbnail, textureImage, accessory, part, decal, texture };
