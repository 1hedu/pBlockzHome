// atropaMath's random number on this chain, for Fishing to draw on: the three libraries RNG links
// (atropaMath the library, Conjecture, Dynamic), RNG, and atropaMath itself. None are on testnet v4.
//
//   node scripts/deploy-atropa.js --dry     rebuild from mainnet's verified source and check it; send nothing
//   node scripts/deploy-atropa.js           then deploy them from DEPLOYER_KEY
//
// The source is never copied into this repository: it carries no licence of its own. Each run fetches
// the mainnet explorer's verified record, rebuilds it with the compiler it was verified with, and
// compares every piece against mainnet's deployed code; a mismatch sends nothing. The one edit is
// atropaMath's hard-coded RNG address. The deployer owns RNG and atropaMath (both Ownable), which
// gates nothing beyond transferring or renouncing ownership.
const { ethers } = require("ethers");
const solc = require("solc");
const fs = require("fs"), path = require("path");
const { applyFeeOverrides } = require("../bridge/src/fees");

const ROOT = path.join(__dirname, "..");
const ADDR_FILE = path.join(ROOT, "addresses.943.json");
const MAINNET_RPC = "https://rpc.pulsechain.com";
const EXPLORER = "https://api.scan.pulsechain.com/api/v2/";
const COMPILER = "v0.8.21+commit.d9974bed";
const MAINNET_RNG = "0xa96BcbeD7F01de6CEEd14fC86d90F21a36dE2143";
const MAINNET_MATH = "0xB680F0cc810317933F234f67EB6A9E923407f05D";   // atropaMath 1.1

/// Runtime code without its trailing CBOR metadata, whose length is the last two bytes.
function stripMeta(hex) {
  const h = hex.replace(/^0x/, "").toLowerCase();
  return h.slice(0, h.length - (parseInt(h.slice(-4), 16) + 2) * 2);
}

async function explorer(route) {
  const res = await fetch(EXPLORER + route);
  if (!res.ok) throw new Error(`the explorer did not answer ${route} (${res.status})`);
  return res.json();
}

async function verifiedSource(address) {
  const j = await explorer("smart-contracts/" + address);
  if (!j.is_verified || typeof j.source_code !== "string") throw new Error(`${address} is not verified on the explorer`);
  if (j.compiler_version !== COMPILER) throw new Error(`${address} was verified with ${j.compiler_version}, not ${COMPILER}`);
  const o = j.compiler_settings && j.compiler_settings.optimizer;
  if (o && o.enabled) throw new Error(`${address} was verified with the optimizer on; this rebuilds with it off`);
  return { source: j.source_code, extra: (j.additional_sources || []).map((a) => a.source_code) };
}

/// What a file declares, as the name after contract/library/interface.
const declaredIn = (src) => (src.match(/\b(?:abstract\s+contract|contract|library|interface)\s+(\w+)/g) || [])
  .map((d) => d.split(/\s+/).pop());

/// Every path a file imports, and the names it asked for by name.
function importsOf(src) {
  const out = [];
  for (const m of src.matchAll(/import\s+(?:\{([^}]*)\}\s+from\s+)?"([^"]+)"\s*;/g))
    out.push({ names: (m[1] || "").split(",").map((n) => n.trim().split(/\s+as\s+/)[0]).filter(Boolean), path: m[2] });
  return out;
}

/// A relative import resolved against the file that asked for it; anything else is left alone,
/// so "@openzeppelin/..." stays the key solc will look for.
function resolve(from, path) {
  if (!path.startsWith(".")) return path;
  const parts = from.split("/").slice(0, -1);
  for (const bit of path.split("/")) {
    if (bit === ".") continue;
    else if (bit === "..") parts.pop();
    else parts.push(bit);
  }
  return parts.join("/");
}

/// The standard-json sources for a verified record. The explorer files its extra sources under
/// names it made up ("/_1", "/"), so each import is matched to the file that declares what the
/// import asked for -- by the names in its braces, else by the basename. Wrong guesses cannot
/// pass unnoticed: the rebuilt runtime code is compared against mainnet's before anything is
/// sent, and a file put in the wrong place does not compile at all.
function assemble(name, record) {
  const sources = { [name]: { content: record.source } };
  const spare = record.extra.slice();
  const queue = [[name, record.source]];
  while (queue.length) {
    const [file, src] = queue.shift();
    for (const imp of importsOf(src)) {
      const want = resolve(file, imp.path);
      if (sources[want]) continue;
      const wanted = imp.names.length ? imp.names : [want.split("/").pop().replace(/\.sol$/, "")];
      let at = spare.findIndex((s) => declaredIn(s).some((d) => wanted.includes(d)));
      // A file of nothing but constants -- addresses.sol is one -- declares no contract to match
      // on, so it is found by elimination, and only while exactly one such file is left.
      if (at < 0) {
        const bare = spare.map((s, i) => [s, i]).filter(([s]) => declaredIn(s).length === 0);
        if (bare.length !== 1) throw new Error(`${file} imports ${imp.path} and no verified source declares ${wanted.join(", ")}`);
        at = bare[0][1];
      }
      const [taken] = spare.splice(at, 1);
      sources[want] = { content: taken };
      queue.push([want, taken]);
    }
  }
  return sources;
}

function compile(compiler, file, sources) {
  const input = {
    language: "Solidity",
    sources,
    settings: { optimizer: { enabled: false, runs: 200 }, evmVersion: "shanghai",
      outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "evm.bytecode.linkReferences",
        "evm.deployedBytecode.object", "evm.deployedBytecode.linkReferences"] } } },
  };
  const out = JSON.parse(compiler.compile(JSON.stringify(input)));
  const errors = (out.errors || []).filter((e) => e.severity === "error");
  if (errors.length) throw new Error(errors.map((e) => e.formattedMessage).join("\n"));
  return out.contracts[file];
}

/// Writes library addresses into code at the offsets the compiler listed, keyed by library name.
function link(code, refs, addresses) {
  let out = code;
  for (const [lib, places] of Object.entries(refs || {})) {
    const addr = addresses[lib];
    if (!addr) throw new Error(`no address for library ${lib}`);
    for (const { start, length } of places) {
      out = out.slice(0, start * 2) + addr.replace(/^0x/, "").toLowerCase() + out.slice((start + length) * 2);
    }
  }
  return out;
}
const refsOf = (linkReferences, file) => (linkReferences || {})[file] || {};

/// Libraries in the order they can be deployed: each after the ones it links.
function order(contracts, file, names) {
  const done = [], seen = new Set();
  const visit = (n) => {
    if (seen.has(n)) return;
    seen.add(n);
    for (const dep of Object.keys(refsOf(contracts[n].evm.bytecode.linkReferences, file))) visit(dep);
    done.push(n);
  };
  names.forEach(visit);
  return done;
}

async function main() {
  const dry = process.argv.includes("--dry");
  const mainnet = new ethers.JsonRpcProvider(MAINNET_RPC);
  const compiler = await new Promise((resolve, reject) =>
    solc.loadRemoteVersion(COMPILER, (err, c) => (err ? reject(err) : resolve(c))));

  const rngRecord = await verifiedSource(MAINNET_RNG);
  const mathRecord = await verifiedSource(MAINNET_MATH);
  const rngFile = compile(compiler, "RNG.sol", assemble("RNG.sol", rngRecord));
  const rngRefs = refsOf(rngFile.RNG.evm.bytecode.linkReferences, "RNG.sol");
  const libs = order(rngFile, "RNG.sol", Object.keys(rngRefs));

  // Which address mainnet's RNG was linked against per library, read out of its creation calldata.
  const created = await explorer("addresses/" + MAINNET_RNG);
  const creation = await mainnet.getTransaction(created.creation_tx_hash);
  const input = creation.data.replace(/^0x/, "");
  const mainnetLib = {};
  for (const [lib, places] of Object.entries(rngRefs)) {
    const at = places.map(({ start }) => "0x" + input.slice(start * 2, (start + 20) * 2));
    if (new Set(at).size !== 1) throw new Error(`mainnet RNG links ${lib} at more than one address`);
    mainnetLib[lib] = ethers.getAddress(at[0]);
  }

  let allSame = true;
  for (const lib of libs) {
    const c = rngFile[lib];
    const onChain = stripMeta(await mainnet.getCode(mainnetLib[lib]));
    // A library's deployed code carries its own address (the call guard); zero it to compare.
    const own = mainnetLib[lib].slice(2).toLowerCase();
    const mine = stripMeta(link(c.evm.deployedBytecode.object, refsOf(c.evm.deployedBytecode.linkReferences, "RNG.sol"), mainnetLib));
    const same = mine === onChain.replace(own, "0".repeat(40));
    console.log(`library ${lib.padEnd(11)} rebuilt == mainnet ${mainnetLib[lib]}: ${same}`);
    allSame = allSame && same;
  }
  const rngSame = stripMeta(link(rngFile.RNG.evm.deployedBytecode.object,
    refsOf(rngFile.RNG.evm.deployedBytecode.linkReferences, "RNG.sol"), mainnetLib)) === stripMeta(await mainnet.getCode(MAINNET_RNG));
  const mathFile = compile(compiler, "atropaMath.sol", assemble("atropaMath.sol", mathRecord));
  const mathSame = stripMeta(mathFile.atropaMath.evm.deployedBytecode.object) === stripMeta(await mainnet.getCode(MAINNET_MATH));
  console.log(`RNG                 rebuilt == mainnet: ${rngSame}`);
  console.log(`atropaMath          rebuilt == mainnet: ${mathSame}`);
  if (!allSame || !rngSame || !mathSame) throw new Error("the rebuild does not match mainnet; nothing sent");

  const hardcoded = `RNG(${MAINNET_RNG})`;
  if (mathRecord.source.split(hardcoded).length !== 2) throw new Error(`expected exactly one ${hardcoded} in atropaMath's source`);
  if (dry) {
    console.log(`\n--dry: nothing sent. Would deploy ${libs.join(", ")}, RNG, then atropaMath with its RNG address changed.`);
    return;
  }

  const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, ".env.testnet"), "utf8").trim().split("\n").map((l) => l.split("=")));
  const provider = applyFeeOverrides(new ethers.JsonRpcProvider(process.env.RPC_URL || "https://rpc.v4.testnet.pulsechain.com", 943, { staticNetwork: true }));
  const deployer = new ethers.NonceManager(new ethers.Wallet(env.DEPLOYER_KEY.trim(), provider));
  const addrs = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  if (addrs.atropaMath && !process.argv.includes("--redeploy")) {
    console.log("already deployed: atropaMath", addrs.atropaMath, "(--redeploy to replace)");
    return;
  }
  console.log("\ndeployer", await deployer.getAddress());

  const here = {};
  for (const lib of libs) {
    const c = rngFile[lib];
    const code = "0x" + link(c.evm.bytecode.object, refsOf(c.evm.bytecode.linkReferences, "RNG.sol"), here);
    const d = await new ethers.ContractFactory([], code, deployer).deploy();
    await d.waitForDeployment();
    here[lib] = await d.getAddress();
    console.log(`library ${lib.padEnd(11)}`, here[lib]);
  }
  const rngCode = "0x" + link(rngFile.RNG.evm.bytecode.object, rngRefs, here);
  const rngC = await new ethers.ContractFactory(rngFile.RNG.abi, rngCode, deployer).deploy();
  await rngC.waitForDeployment();
  const rngAddr = await rngC.getAddress();
  console.log("RNG                ", rngAddr);

  const ours = compile(compiler, "atropaMath.sol",
    assemble("atropaMath.sol", { ...mathRecord, source: mathRecord.source.replace(hardcoded, `RNG(${ethers.getAddress(rngAddr)})`) })).atropaMath;
  const mathC = await new ethers.ContractFactory(ours.abi, "0x" + ours.evm.bytecode.object, deployer).deploy();
  await mathC.waitForDeployment();
  const mathAddr = await mathC.getAddress();
  console.log("atropaMath         ", mathAddr);

  // Random() is a transaction (it mints and steps the generator), so sample it with eth_call.
  const sample = await provider.call({ to: mathAddr, data: mathC.interface.encodeFunctionData("Random", []) });
  console.log("Random() as a call answers:", mathC.interface.decodeFunctionResult("Random", sample)[0].toString());

  addrs.atropaLibraries = here;
  addrs.RNG = rngAddr;
  addrs.atropaMath = mathAddr;
  fs.writeFileSync(ADDR_FILE, JSON.stringify(addrs, null, 2) + "\n");
  console.log("\nwritten to addresses.943.json. Next: node scripts/deploy-fishing.js", mathAddr, "<EverlivingFishThumb uri>");
}

main().catch((e) => { console.error(e.shortMessage || e.message || e); process.exit(1); });
