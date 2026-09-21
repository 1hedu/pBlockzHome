-- Notifications the town sends you: "You got a Dysnomia Rod", and the like.
--
-- Roblox's own corner card, StarterGui:SetCore("SendNotification"). Only a LocalScript can call
-- SetCore, so the server says what to show down the Notify remote and this shows it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

ReplicatedStorage:WaitForChild("Notify").OnClientEvent:Connect(function(card)
	if type(card) ~= "table" or type(card.Title) ~= "string" or type(card.Text) ~= "string" then return end
	local ok, err = pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = card.Title,
			Text = card.Text,
			Icon = type(card.Icon) == "string" and card.Icon or nil,
			Duration = tonumber(card.Duration) or 5,
		})
	end)
	if not ok then warn("notify: " .. tostring(err)) end
end)
