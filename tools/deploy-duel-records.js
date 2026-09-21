// Deploys DuelRecords and writes its address into addresses.943.json.
//
//   node scripts/compile.js && node scripts/deploy-duel-records.js
//
// Where a ranked duel's result goes: sent by one team, signed by the other. See
// contracts/DuelRecords.sol. The address then goes into demo2's shared/Contracts.luau as
// DuelRecords, and the town offers "Put it on chain".
const { ethers } = require("ethers");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");
const ADDR_FILE = path.join(ROOT, "addresses.943.json");

const TYPES = { Result: [
  { name: "id", type: "bytes32" }, { name: "teamA", type: "address[]" }, { name: "teamB", type: "address[]" },
  { name: "killsA", type: "uint16[]" }, { name: "killsB", type: "uint16[]" }, { name: "limit", type: "uint16" },
  { name: "winner", type: "uint8" }, { name: "endedAt", type: "uint64" },
] };

async function main() {
  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  const deployer = new ethers.NonceManager(new ethers.Wallet(env.DEPLOYER_KEY, provider));
  const addrs = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));

  if (addrs.DuelRecords && !process.argv.includes("--redeploy")) {
    console.log("already deployed at", addrs.DuelRecords, "(--redeploy to replace)");
    return;
  }
  const art = JSON.parse(fs.readFileSync(path.join(ROOT, "artifacts", "DuelRecords.json"), "utf8"));
  const c = await new ethers.ContractFactory(art.abi, art.bytecode, deployer).deploy();
  await c.waitForDeployment();
  addrs.DuelRecords = await c.getAddress();
  fs.writeFileSync(ADDR_FILE, JSON.stringify(addrs, null, 2) + "\n");
  console.log("DuelRecords", addrs.DuelRecords);

  // The digest the contract computes must equal the one a wallet signs over TYPES, or no result
  // could ever be recorded. Checked as a read, against a throwaway result.
  const other = ethers.Wallet.createRandom();
  const me = await deployer.getAddress();
  const r = { id: ethers.id("deploy check"), teamA: [me], teamB: [other.address], killsA: [1], killsB: [0], limit: 1, winner: 1, endedAt: 1 };
  const domain = { name: "PulseBlockz Duels", version: "1", chainId: 943, verifyingContract: addrs.DuelRecords };
  const onChain = await c.digest(r.id, r.teamA, r.teamB, r.killsA, r.killsB, r.limit, r.winner, r.endedAt);
  console.log("digest agrees with a wallet's          :", onChain === ethers.TypedDataEncoder.hash(domain, TYPES, r) ? "yes" : "NO -- WRONG");
  console.log("a fresh id reads as not recorded       :", (await c.recorded(r.id)) ? "recorded -- WRONG" : "not recorded");
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
