// Deploys Fishing and writes its address into addresses.943.json.
//
//   node scripts/compile.js && node scripts/deploy-fishing.js <random contract> <picture pblockz:// uri>
//
// <picture> is EverlivingFishThumb from demo2's place-assets.json, published. The discovery token's
// metadata is built on chain from those same bytes, read out of the AssetStore, so the uri must name
// its store and blob (?chain=943:<store>:<blob>).
//
// <random contract> is anything whose Random() answers a uint64 on this chain: atropaMath, or a copy.
// Fishing is only as unpredictable as it is. The address then goes into demo2's shared/Contracts.luau.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");
const ADDR_FILE = path.join(ROOT, "addresses.943.json");

async function main() {
  const [, , random, picture = ""] = process.argv;
  const where = picture.match(/[?&]chain=943:(0x[0-9a-fA-F]{40}):(\d+)/);
  if (!random || !ethers.isAddress(random) || !where) {
    console.error("usage: node scripts/deploy-fishing.js <random contract> <picture pblockz:// uri, with chain=943:<store>:<blob>>");
    process.exit(1);
  }
  const [store, blob] = [ethers.getAddress(where[1]), BigInt(where[2])];
  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  if ((await provider.getCode(random)) === "0x") {
    console.error(`nothing is deployed at ${random} on this chain`);
    process.exit(1);
  }
  const deployer = new ethers.NonceManager(new ethers.Wallet(env.DEPLOYER_KEY, provider));
  const addrs = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  if (addrs.Fishing && !process.argv.includes("--redeploy")) {
    console.log("already deployed at", addrs.Fishing, "(--redeploy to replace)");
    return;
  }
  const art = JSON.parse(fs.readFileSync(path.join(ROOT, "artifacts", "Fishing.json"), "utf8"));
  const c = await new ethers.ContractFactory(art.abi, art.bytecode, deployer).deploy(random, store, blob);
  await c.waitForDeployment();
  addrs.Fishing = await c.getAddress();
  fs.writeFileSync(ADDR_FILE, JSON.stringify(addrs, null, 2) + "\n");
  console.log("Fishing", addrs.Fishing, "drawing on", random, "; the token's picture is blob", blob.toString(), "in", store);
  console.log("discovered yet                         :", (await c.discovered()) ? "YES -- WRONG" : "no");
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
