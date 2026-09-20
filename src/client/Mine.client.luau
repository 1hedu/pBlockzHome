-- This player's own wallet, handed to the desks so they can show it back to them.
--
-- Their balances, tokens, pools and history are read by their own machine from their own wallet
-- (Wallet.gd publishes them into this player's tree as ReplicatedStorage.Chain's "Wallet"
-- attribute). The town's desks need them to say "you have 12 PLS" -- so this passes them along,
-- to the server and nowhere else, for that one player's panels.
--
-- Shown, never believed. Nothing the town decides rests on it: who holds what is read by the
-- server from the game's own contracts, and every write is checked by the chain.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local remote = ReplicatedStorage:WaitForChild("MineRemote", 60)
local chain = ReplicatedStorage:WaitForChild("Chain", 60)
if not remote or not chain then return end

local sent = nil

local function send(force)
	local raw = chain:GetAttribute("Wallet")
	if type(raw) ~= "string" or raw == "" then return end
	if raw == sent and not force then return end
	sent = raw
	remote:FireServer(raw)
end

chain:GetAttributeChangedSignal("Wallet"):Connect(function() send(false) end)
-- Signing in after the wallet first reported: the server only keeps a wallet's half beside the
-- address it signed in as, so say it again once that address is on the Player.
local me = Players.LocalPlayer
if me then
	me:GetAttributeChangedSignal("WalletAddress"):Connect(function() send(true) end)
end
send(true)
