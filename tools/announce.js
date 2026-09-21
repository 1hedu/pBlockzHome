// Posts an announcement, from the owner's key.
//
//   node scripts/announce.js "Space fishing is open. Cast off the edge of the map."
//   node scripts/announce.js --file announcement.txt [--as PLAYER_KEY]
//   node scripts/announce.js --pin 0        keep announcement #0 up, above the newest
//   node scripts/announce.js --unpin        take the pinned one down
//
// The newest announcement shows in every player's chat, replacing the one before, with the pinned
// one above it; the Hall of Records keeps them all. Address: addresses.943.json. Key: .env.testnet.
// The contract has no delete or edit -- --unpin only takes the pin off; correct a post by posting
// again.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");

async function main() {
  const args = process.argv.slice(2);
  const pick = (name) => { const i = args.indexOf(name); if (i < 0) return null; const v = args[i + 1]; args.splice(i, 2); return v; };
  const keyName = pick("--as") || "DEPLOYER_KEY";
  const file = pick("--file");
  const pinAt = args.indexOf("--pin");
  const pin = pinAt >= 0 ? args.splice(pinAt, 2)[1] : null;
  const unpinAt = args.indexOf("--unpin");
  const unpin = unpinAt >= 0 && args.splice(unpinAt, 1).length > 0;
  const text = (file ? fs.readFileSync(file, "utf8") : args.join(" ")).trim();
  if (pin !== null && !/^\d+$/.test(pin)) throw new Error("usage: node scripts/announce.js --pin <announcement number>");
  if (!text && pin === null && !unpin) {
    console.error('usage: node scripts/announce.js "what to say" | --pin <n> | --unpin');
    process.exit(1);
  }
  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const addrs = JSON.parse(fs.readFileSync(path.join(ROOT, "addresses.943.json"), "utf8"));
  if (!addrs.Announcements) throw new Error("Announcements is not deployed (scripts/deploy-announcements.js)");
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  if (!env[keyName]) throw new Error(`.env.testnet has no ${keyName}`);
  const owner = new ethers.Wallet(env[keyName], provider);
  const art = JSON.parse(fs.readFileSync(path.join(ROOT, "artifacts", "Announcements.json"), "utf8"));
  const c = new ethers.Contract(addrs.Announcements, art.abi, owner);
  if (unpin) {
    await (await c.unpin()).wait();
    console.log("unpinned");
  } else if (pin !== null) {
    await (await c.pin(BigInt(pin))).wait();
    console.log(`pinned #${pin}: ${(await c.announcement(BigInt(pin)))[0]}`);
  } else {
    const tx = await c.announce(text);
    await tx.wait();
    console.log(`announced (#${(await c.count()) - 1n}): ${text}`);
  }
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
