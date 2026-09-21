-- The contracts this town uses, named once.
--
-- A place declares which contracts it trusts. That is the whole point of the move off the
-- client's eighteen hardcoded actions: a place whose contracts were chosen by whoever
-- packaged its client would be a place whose rules somebody else can change.
--
-- Named HERE rather than in each desk because the first pass put the address in the shop,
-- the wardrobe and the tailor separately, and three copies of one address is three chances
-- to move two of them. Same reason Weapons.luau and Theme.luau exist: this codebase has
-- already been bitten by the same value living in more than one file.
--
-- Changing any of these means republishing the place, and that is correct rather than
-- unfortunate -- a place that silently followed a contract somewhere else would be a place
-- whose rules somebody else can change, which is the thing being avoided.
local Contracts = {
	-- Who holds what, and the holdings ladder that gates claiming.
	Inventory = "0x20e1bE50Fb0FB2e3716a721D6051d91151617f2a",

	-- One bit per address: whether you are up for a fight. Ownerless, and it follows you
	-- to any town that reads the same contract.
	Duelling = "0xf1320dddc0E6E6C33B4D034F321e976639be8E92",

	-- Ranked duel results, once both sides have agreed to one: sent by one team, signed by the
	-- other. Empty until it is deployed (scripts/deploy-duel-records.js), and until then the
	-- town keeps its results itself and says so.
	DuelRecords = "0x23b5490E158EAD5605aE6d19e1bCbC391DEDA810",

	-- Space fishing: every cast and every catch, decided on chain by a random number, and the one
	-- Everliving Fish token for whoever finds it first. Empty until it is deployed
	-- (scripts/deploy-fishing.js), and until then nobody can cast.
	Fishing = "0x5d8CB335B202e456b82113a92cBEb6508a5746Fc",

	-- What the town's owner announces: the newest shows in chat, in gold, and the Hall of Records keeps
	-- them all. Owned by whoever deploys it, and the only thing it lets them do is post. Empty until it
	-- is deployed (scripts/deploy-announcements.js).
	Announcements = "0x32e034124b043B573bf473cd8488dF10ef89DC75",

	-- The chain all of the above are on. A signature says which chain it is for, so a place
	-- asking for one has to say too.
	ChainId = 943,

	-- The catalogue: every asset anybody has registered, by id, each naming its own
	-- metadata by content hash. ERC-1155, so one id can be held by many people.
	Registry = "0xbD540C22F9FA1f070D0b85d8325baE809c3db40B",

	-- What is on the shelf and at what price, in whichever tokens its owner accepts.
	Marketplace = "0x9f1A5C5d8328C863EDcDef8416745391A3Ef2968",

	-- Where the bytes themselves live. The client has one of these too, as the store it
	-- writes to by default -- but a read is addressed by the uri, which names its own
	-- store, so this is only here because inventoryOf answers with hashes rather than
	-- uris and something has to say which store to look them up in.
	AssetStore = "0x0f9D08e13BE2345856026615d05F7251F07efAfA",

	-- Where a gift goes. The account that publishes this town, so a donation is checkable
	-- against the thing it is thanking rather than a string on a sign.
	Donations = "0xC8CD89650f12b8b565ba89307e072C10579F6AA6",

	-- Multicall3, at the address it has on every chain it is deployed to. Read for the chain's
	-- live height and base fee (getBlockNumber, getBasefee): a wallet publishes those only when
	-- something else about it changed.
	Multicall3 = "0xcA11bde05977b3631167028862bE2a173976CA11",
}

-- A local chain's addresses, for playing what is not deployed yet: scripts/dev-chain.js writes
-- ContractsDev beside this while it runs, and removes it when it stops. It is gitignored, and the
-- experience publisher will not run while it exists, so a published town never carries one.
local dev = script.Parent:FindFirstChild("ContractsDev")
if dev then
	local ok, overrides = pcall(require, dev)
	if ok and type(overrides) == "table" then
		for name, address in pairs(overrides) do Contracts[name] = address end
	end
end

return Contracts
