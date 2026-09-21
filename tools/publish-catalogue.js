// Publishes scripts/catalogue.js to PulseChain testnet v4, the way a creator would:
//
//   shared textures -> AssetStore   (one copy, referenced by every model that wears it)
//   thumbnail PNG   -> AssetStore   (so blobOf can find it from its hash alone)
//   Accessory model -> AssetStore
//   metadata JSON   -> AssetStore   (names the two above BY HASH -- see `bare` below)
//   register + setPrice -> UGC1155 / Marketplace, from the creator's own wallet
//
//   node scripts/publish-catalogue.js                 # publish or update everything
//   node scripts/publish-catalogue.js --only tophat   # just one
//   node scripts/publish-catalogue.js --preview out/  # draw the art, publish nothing
//
// Token ids live in catalogue.943.json, so a second run calls setUri on the tokens that
// already exist. The registry is ownerless -- no admin, no burn -- so a duplicate mint
// cannot be undone, and the manifest is what prevents one.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");
const { ITEMS, TEXTURES, thumbnail, textureImage } = require("./catalogue");
const { EMBLEMS, emblemImage } = require("./capes");

const ROOT = path.join(__dirname, "..");
const RPC = process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com";
const CHAIN_ID = 943;
const MANIFEST = path.join(ROOT, "catalogue.943.json");

// Required inside main(), once CHAIN and ADDRESSES_FILE are set -- it reads both on load.
let assets;

/**
 * `bare` is the content hash alone, for a field whose whole job is to name an asset: a
 * document's `model` and `thumbnail`. Which chain, store and blob hold the bytes is a fact
 * about the deployment, not about the hat, and AssetStore.blobOf answers it from the hash --
 * with the mime on the blob beside them.
 *
 * `content` keeps the pblockz:// scheme, for a hash that has to survive inside a property
 * string -- a Decal's Texture -- where a reader scanning for an asset will not recognise 64
 * loose characters of hex.
 */
const bare = (uri) => assets.parseUri(uri).contentHash;
const content = (uri) => "pblockz://" + assets.parseUri(uri).contentHash.slice(2);

const arg = (name) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : null;
};

function loadManifest() {
  if (!fs.existsSync(MANIFEST)) return { chainId: CHAIN_ID, items: {}, textures: {}, blobs: {} };
  const m = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  m.blobs = m.blobs || {};
  return m;
}

function saveManifest(m) {
  fs.writeFileSync(MANIFEST, JSON.stringify(m, null, 2) + "\n");
}

/**
 * Stores bytes unless the manifest already holds this slot at this hash. Everything is
 * content-addressed, so identical art resolves to the same pblockz:// hash and storing it
 * again costs a write and changes nothing.
 */
async function store(manifest, slot, bytes, opts, assets) {
  const hash = ethers.keccak256(bytes).slice(2);
  const known = manifest.blobs[slot];
  // Same bytes AND kept the same way: a calldata blob is cheaper but findable only through
  // the transaction that carried it, so it cannot answer a document that names it by hash.
  const asKept = opts.viaCalldata ? "tx=" : "chain=";
  if (known && known.includes(hash) && known.includes(asKept)) return { uri: known, reused: true };
  const stored = opts.viaCalldata
    ? await assets.storeBytesAsCalldata(bytes, { mime: opts.mime, signer: opts.signer })
    : await assets.storeBytes(bytes, { mime: opts.mime, signer: opts.signer });
  manifest.blobs[slot] = stored.uri;
  return { uri: stored.uri, reused: false };
}

/** --preview: draw everything to PNGs so the art can be checked before it costs gas. */
function preview(dir) {
  fs.mkdirSync(dir, { recursive: true });
  for (const key of Object.keys(TEXTURES)) {
    const png = textureImage(key);
    fs.writeFileSync(path.join(dir, `texture-${key}.png`), png);
    console.log(`texture ${key.padEnd(10)} ${String(png.length).padStart(6)} bytes`);
  }
  for (const key of Object.keys(EMBLEMS)) {
    const { png, fromFile } = emblemImage(key);
    fs.writeFileSync(path.join(dir, `emblem-${key}.png`), png);
    console.log(`emblem  ${key.padEnd(10)} ${String(png.length).padStart(6)} bytes${fromFile ? "  (from scripts/logos/)" : ""}`);
  }
  for (const item of ITEMS) {
    const png = thumbnail(item);
    fs.writeFileSync(path.join(dir, `thumb-${item.key}.png`), png);
    const fake = new Proxy({}, { get: () => "pblockz://" + "0".repeat(64) });
    const model = JSON.stringify(item.model(fake));
    fs.writeFileSync(path.join(dir, `model-${item.key}.json`), model);
    console.log(`item    ${item.key.padEnd(10)} thumb ${String(png.length).padStart(6)} bytes, model ${String(model.length).padStart(6)} bytes`);
  }
  console.log(`\nwrote ${dir}`);
}

async function main() {
  // --preview with no directory would otherwise fall through and publish everything.
  if (process.argv.includes("--preview") && !arg("--preview")) {
    throw new Error("--preview needs somewhere to draw to, e.g. --preview out/ "
      + "(without it this would have published everything)");
  }
  const previewDir = arg("--preview");
  if (previewDir) return preview(previewDir);

  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  process.env.CHAIN = "testnet";
  process.env.ADDRESSES_FILE = path.join(ROOT, "addresses.943.json");
  assets = require("./assets");
  const { contracts } = require("../bridge/src/chain");
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(RPC, CHAIN_ID, { staticNetwork: true }));
  const creator = new ethers.NonceManager(new ethers.Wallet(env.CREATOR_KEY, provider));
  const addr = await creator.getAddress();
  console.log("creator", addr, ethers.formatEther(await provider.getBalance(addr)), "tPLS\n");

  const manifest = loadManifest();
  const only = arg("--only");
  const wanted = only ? ITEMS.filter((i) => i.key === only) : ITEMS;
  if (wanted.length === 0) throw new Error(`no catalogue item named "${only}"`);

  // 1. the shared textures.
  const shared = {};
  for (const key of Object.keys(TEXTURES)) {
    const png = textureImage(key);
    const kept = await store(manifest, `texture:${key}`, png, { mime: TEXTURES[key].mime, signer: creator }, assets);
    shared[key] = content(kept.uri);
    manifest.textures[key] = kept.uri;
    console.log(`texture ${key.padEnd(10)} ${String(png.length).padStart(6)} bytes${kept.reused ? "  (unchanged)" : ""}`);
  }
  saveManifest(manifest);

  // 2. each item.
  for (const item of wanted) {
    console.log(`
--- ${item.name} (${item.key})`);
    const tex = { ...shared };

    // Images belonging to this item alone, such as a cape's emblem.
    for (const [name, make] of Object.entries(item.images || {})) {
      const art = make();
      const kept = await store(manifest, `item:${item.key}:${name}`, art, { mime: "image/png", signer: creator }, assets);
      tex[name] = content(kept.uri);
      console.log(`  ${name.padEnd(9)} ${String(art.length).padStart(6)} bytes${kept.reused ? "  (unchanged)" : ""}`);
    }

    // Anything that is not a PNG, mostly meshes. The maker gives the mime: the host caches the
    // blob under a filename whose extension comes from that mime, and Godot picks its loader
    // from the extension, so a .glb filed as image/png never loads.
    for (const [name, make] of Object.entries(item.assets || {})) {
      const a = make();
      const kept = await store(manifest, `item:${item.key}:${name}`, a.bytes, { mime: a.mime, signer: creator }, assets);
      tex[name] = content(kept.uri);
      console.log(`  ${name.padEnd(9)} ${String(a.bytes.length).padStart(6)} bytes  ${a.mime}${kept.reused ? "  (unchanged)" : ""}`);
    }

    const png = thumbnail(item);
    const thumb = await store(manifest, `item:${item.key}:thumb`, png,
      { mime: "image/png", signer: creator }, assets);
    console.log(`  thumbnail ${String(png.length).padStart(6)} bytes${thumb.reused ? "  (unchanged)" : ""}`);

    const modelBytes = Buffer.from(JSON.stringify(item.model(tex)));
    const model = await store(manifest, `item:${item.key}:model`, modelBytes,
      { mime: "application/json", signer: creator }, assets);
    console.log(`  model     ${String(modelBytes.length).padStart(6)} bytes${model.reused ? "  (unchanged)" : ""}`);

    // `tier` is declared here, not derived from the price: Inventory.add folds it into the
    // item's id, so it is part of the thing rather than a label beside it.
    const meta = Buffer.from(JSON.stringify({
      name: item.name, kind: item.kind, slot: item.slot, blurb: item.blurb,
      tier: item.tier, tier_pls: item.tierPls,
      license: "CC0-1.0", attribution: "", source: "scripts/catalogue.js",
      model: bare(model.uri), thumbnail: bare(thumb.uri),
    }));
    const metaBlob = await store(manifest, `item:${item.key}:meta`, meta,
      { mime: "application/json", signer: creator }, assets);
    console.log(`  metadata  ${String(meta.length).padStart(6)} bytes${metaBlob.reused ? "  (unchanged)" : ""}`);

    const known = manifest.items[item.key];
    let id;
    if (known && known.id != null) {
      id = BigInt(known.id);
      if (known.uri !== metaBlob.uri) {
        await (await contracts.ugc.connect(creator).setUri(id, metaBlob.uri)).wait();
        console.log(`  updated token #${id}`);
      } else {
        console.log(`  token #${id} already points here`);
      }
    } else {
      id = await contracts.ugc.nextId();
      await (await contracts.ugc.connect(creator).register(metaBlob.uri, 0, 500)).wait();
      console.log(`  registered token #${id}`);
    }

    manifest.items[item.key] = { id: Number(id), name: item.name, uri: metaBlob.uri };
    saveManifest(manifest);
  }


  console.log(`\n${wanted.length} item(s) live. Token ids are in catalogue.943.json.`);
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
