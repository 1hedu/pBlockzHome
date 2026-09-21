// Deploys the Duelling flag and writes its address into addresses.943.json.
//
//   node scripts/compile.js && node scripts/deploy-duelling.js
//
// One bit per address: whether you are up for a fight, carried to every town. See
// contracts/Duelling.sol.
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");
const ADDR_FILE = path.join(ROOT, "addresses.943.json");

async function main() {
  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  const deployer = new ethers.NonceManager(new ethers.Wallet(env.DEPLOYER_KEY, provider));
  const addrs = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));

  if (addrs.Duelling && !process.argv.includes("--redeploy")) {
    console.log("already deployed at", addrs.Duelling, "(--redeploy to replace)");
    return;
  }
  const art = JSON.parse(fs.readFileSync(path.join(ROOT, "artifacts", "Duelling.json"), "utf8"));
  const c = await new ethers.ContractFactory(art.abi, art.bytecode, deployer).deploy();
  await c.waitForDeployment();
  addrs.Duelling = await c.getAddress();
  fs.writeFileSync(ADDR_FILE, JSON.stringify(addrs, null, 2) + "\n");
  console.log("Duelling", addrs.Duelling);

  // The default decides everything: an address that has never transacted must read as in, or
  // joining a fight would cost a new player gas.
  const me = await deployer.getAddress();
  const fresh = ethers.Wallet.createRandom().address;
  console.log("an address that has never touched this:", (await c.fighting(fresh)) ? "in, as it should be" : "OUT -- WRONG");
  await (await c.setFighting(false)).wait();
  console.log("after opting out                      :", (await c.fighting(me)) ? "in -- WRONG" : "out, as asked");
  await (await c.setFighting(true)).wait();
  console.log("and back in                           :", (await c.fighting(me)) ? "in" : "out -- WRONG");
  const many = await c.fightingMany([me, fresh]);
  console.log("read for a crowd in one call          :", many.length === 2 && many[0] && many[1] ? "ok" : "WRONG");
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
