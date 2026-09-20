-- A desk asking this player's wallet for something.
--
-- The server holds no key. When a desk wants a player to buy, send, publish, swap or set a flag,
-- it asks that one player (Ledger.askPlayer), and the ask arrives here -- on their machine, and
-- nobody else's. It goes to their own wallet (OwnWallet), which puts it in front of them to
-- confirm and pays for it, and the answer goes back to the desk that asked.
--
-- The desk decides what to ask for; the player's wallet decides whether it happens, from what the
-- chain says rather than from what the desk said. A desk can ask; it cannot sign.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local OwnWallet = require(ReplicatedStorage:WaitForChild("OwnWallet"))
local remote = ReplicatedStorage:WaitForChild("WalletRemote", 60)
if not remote then return end

remote.OnClientEvent:Connect(function(n, request)
	if type(request) ~= "table" then return end
	task.spawn(function()
		local answer = OwnWallet.request(request)
		remote:FireServer(n, answer or { ok = false, message = "Your wallet didn't answer." })
	end)
end)
