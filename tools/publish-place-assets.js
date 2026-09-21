// Publishes a place's own assets -- font, sounds, sky -- and records each URI under its
// name in place-assets.json.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");

const ROOT = path.join(__dirname, "..");
const MANIFEST = path.join(ROOT, "luau", "gdextension", "demo2", "place-assets.json");

const MIMES = {
  ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp",
  ".wav": "audio/wav", ".ogg": "audio/ogg", ".mp3": "audio/mpeg",
  ".ttf": "font/ttf", ".otf": "font/otf", ".zip": "application/zip",
  ".glb": "model/gltf-binary", ".json": "application/json",
  // The client caches bytes under an extension derived from the mime and picks Godot's loader
  // from it; an unknown mime falls back to "png", so an .obj published as octet-stream lands
  // on disk as a .png nothing can open.
  ".obj": "model/obj",
};

async function main() {
  const args = process.argv.slice(2);
  const dry = args.includes("--dry");
  const pairs = args.filter((a) => a.includes("=")).map((a) => {
    const i = a.indexOf("=");
    return { name: a.slice(0, i), file: path.resolve(ROOT, a.slice(i + 1)) };
  });
  if (pairs.length === 0) {
    console.error("usage: publish-place-assets.js [--dry] <Name>=<file> [<Name>=<file> ...]");
    process.exit(2);
  }

  // Addresses and key come from the chain being published to, not from the shell.
  const env = Object.fromEntries(
    fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  process.env.CHAIN = "testnet";
  process.env.ADDRESSES_FILE = path.join(ROOT, "addresses.943.json");
  process.env.RPC_URL = process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com";
  const { storeBytes, parseUri } = require("./assets");
  const { provider } = require("../bridge/src/chain");
  const creator = new ethers.NonceManager(new ethers.Wallet(env.CREATOR_KEY, provider));

  const manifest = JSON.parse(fs.readFileSync(MANIFEST, "utf8"));
  console.log(`creator ${await creator.getAddress()}`);

  let published = 0, skipped = 0, total = 0;
  for (const { name, file } of pairs) {
    const bytes = fs.readFileSync(file);
    const hash = ethers.keccak256(bytes);
    total += bytes.length;

    // A matching content hash is the same bytes: republishing costs gas and leaves a
    // duplicate blob.
    const have = manifest[name];
    if (have) {
      let already = false;
      try { already = parseUri(have).contentHash.toLowerCase() === hash.toLowerCase(); } catch (e) {}
      if (already) {
        console.log(`  ${name.padEnd(12)} ${String(bytes.length).padStart(8)} bytes  unchanged`);
        skipped++;
        continue;
      }
    }

    const mime = MIMES[path.extname(file).toLowerCase()] || "application/octet-stream";
    if (dry) {
      console.log(`  ${name.padEnd(12)} ${String(bytes.length).padStart(8)} bytes  ${mime}  would publish`);
      continue;
    }
    const r = await storeBytes(bytes, { mime, signer: creator });
    manifest[name] = r.uri;
    console.log(`  ${name.padEnd(12)} ${String(bytes.length).padStart(8)} bytes  blob ${r.blobId}`);
    published++;
    // Written per asset: a run that dies halfway must not lose the URI of bytes already paid for.
    fs.writeFileSync(MANIFEST, JSON.stringify(manifest, null, 2) + "\n");
  }
  console.log(`${published} published, ${skipped} unchanged, ${(total / 1024).toFixed(0)}KB seen`);
}

main().catch((e) => { console.error(e.message || e); process.exit(1); });
