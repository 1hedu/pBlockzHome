// Deploys Announcements and writes its address into addresses.943.json.
//
//   node scripts/compile.js && node scripts/deploy-announcements.js [--as PLAYER_KEY]
//
// The deployer is the owner for good: only that key can post an announcement
// (scripts/announce.js), and the town shows its address in gold. DEPLOYER_KEY unless --as names
// another .env.testnet key. The address then goes into demo2's shared/Contracts.luau.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");
const ADDR_FILE = path.join(ROOT, "addresses.943.json");

async function main() {
  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  const at = process.argv.indexOf("--as");
  const keyName = at >= 0 ? process.argv[at + 1] : "DEPLOYER_KEY";
  if (!env[keyName]) throw new Error(`.env.testnet has no ${keyName}`);
  const deployer = new ethers.NonceManager(new ethers.Wallet(env[keyName], provider));
  const addrs = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  if (addrs.Announcements && !process.argv.includes("--redeploy")) {
    console.log("already deployed at", addrs.Announcements, "(--redeploy to replace)");
    return;
  }
  const art = JSON.parse(fs.readFileSync(path.join(ROOT, "artifacts", "Announcements.json"), "utf8"));
  const c = await new ethers.ContractFactory(art.abi, art.bytecode, deployer).deploy();
  await c.waitForDeployment();
  addrs.Announcements = await c.getAddress();
  fs.writeFileSync(ADDR_FILE, JSON.stringify(addrs, null, 2) + "\n");
  console.log("Announcements", addrs.Announcements, "owned by", await c.owner());
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
