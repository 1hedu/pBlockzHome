-- Who the town's owner is: the address that owns the Announcements contract, read off the chain.
--
-- The owner's nametag and chat name are gold, the gold their announcements are in, where everybody
-- else's nametag is purple (Overhead.client.luau, Chat.client.luau). Nobody can pass themselves off
-- as the owner: the colour follows an address the chain names, and a player's address is the one
-- their own wallet signed in with -- a name anybody can copy is not.
--
-- Client-side, read by each player's own machine like any public chain data. Nil until it has been
-- read, and nil where there is no Announcements contract.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TownOwner = {}

--- Gold: the owner's name, and the announcements they post.
TownOwner.COLOUR = Color3.fromRGB(255, 200, 60)
--- Purple: everybody else's name over their head.
TownOwner.EVERYONE = Color3.fromRGB(150, 76, 230)

--- Fired once the owner's address is known.
TownOwner.known = Instance.new("BindableEvent")

local address = nil
local reading = false

local function read()
	if reading or address or not RunService:IsClient() then return end
	reading = true
	task.spawn(function()
		local Contracts = require(ReplicatedStorage:WaitForChild("Contracts"))
		local OwnWallet = require(ReplicatedStorage:WaitForChild("OwnWallet"))
		while not address do
			if Contracts.Announcements and Contracts.Announcements ~= "" then
				local answer = OwnWallet.request({ action = "read", to = Contracts.Announcements, fn = "owner()",
					args = {}, returns = { "address" } }, 30)
				local who = answer and answer.ok and answer.words and answer.words[1]
				if type(who) == "string" and not who:match("^0x0+$") then
					address = who:lower()
					TownOwner.known:Fire(address)
					break
				end
			end
			task.wait(15)
		end
	end)
end

--- The owner's address, lowercased, or nil while not known.
function TownOwner.address()
	read()
	return address
end

--- Whether `player` is signed in as the town's owner.
function TownOwner.is(player)
	read()
	if not address or typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
	local signed = player:GetAttribute("WalletAddress")
	return type(signed) == "string" and signed:lower() == address
end

return TownOwner
