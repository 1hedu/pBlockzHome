-- /w and /whisper: one line to one person.
--
-- ---- how Roblox does this --------------------------------------------------------------
-- With a TextChannel, and nothing else. A TextChannel delivers a message to the players
-- whose TextSource is in it and to nobody else -- that is the whole of what a channel is --
-- so a whisper is a channel with exactly two people in it. The general chat is the same
-- machinery with everyone in it.
--
-- So there is no private message here, no second wire, and nothing that has to be filtered
-- on the way out. The one thing this script owns is which channel a given pair share, and
-- making it the first time they speak.
--
-- ---- why a RemoteFunction and not a command handler --------------------------------------
-- A TextChatCommand's Triggered fires on both sides, and typing does not make a channel: a
-- client cannot add a TextSource (AddUserAsync is a server call) and the server cannot speak
-- in a channel (SendAsync is a client call). Which is exactly Roblox's division and is
-- right -- a server that could put words in a channel could put them in your mouth.
--
-- So the two halves do what only they can. The client parses the line and sends it; the
-- server hands it the channel to send it on, and makes it if this pair have not spoken.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

-- Shared with /squelch on the client, so typing the same name at both is answered the same
-- way. Two copies of "who did they mean" is the kind of thing that drifts quietly.
local Whom = require(ReplicatedStorage:WaitForChild("Whom"))

local channels = TextChatService:WaitForChild("TextChannels")
local commands = TextChatService:WaitForChild("TextChatCommands")

--- The channel two players share, by their user ids.
---
--- Sorted, so the pair name the same channel whichever of them speaks first -- otherwise the
--- second one to open a conversation opens a second conversation.
---
--- Named RBXWhisper... because that is what Roblox calls its own: the chat window knows to
--- draw a message from a channel with that prefix as a whisper rather than as something
--- everybody heard, and a place that later drops this script for the built-in one keeps the
--- same look.
local function nameFor(a: number, b: number): string
	local lo, hi = math.min(a, b), math.max(a, b)
	return ("RBXWhisper:%d_%d"):format(lo, hi)
end

-- What the client asks for: the channel to whisper to somebody on.
--
-- A function rather than an event because the client has nothing to send until it has the
-- answer, and a channel that arrives a frame after the message was typed is a message that
-- went nowhere.
local ask = Instance.new("RemoteFunction")
ask.Name = "WhisperChannel"
ask.Parent = ReplicatedStorage

ask.OnServerInvoke = function(player, typed)
	if type(typed) ~= "string" or typed == "" then return nil, "Whisper to whom?" end
	local them, why = Whom.find(typed)
	if not them then return nil, why end
	-- Talking to yourself is not refused with an error, it is just pointed out. A refusal
	-- reads as a fault in the game; this reads as a joke you made.
	if them == player then return nil, "You are right here." end

	local id = nameFor(player.UserId, them.UserId)
	local channel = channels:FindFirstChild(id)
	if not channel then
		channel = Instance.new("TextChannel")
		channel.Name = id
		channel.Parent = channels
	end
	-- Both, every time, and AddUserAsync is happy to be asked twice: a respawn leaves the
	-- channel alone but a player who left and came back has no TextSource in it any more.
	channel:AddUserAsync(player.UserId)
	channel:AddUserAsync(them.UserId)
	return channel, them.DisplayName
end

-- The command itself, made on the server so that it replicates and so that every client's
-- copy of it fires when that client types the word.
--
-- Nothing is connected to Triggered here. The server has nothing to do with a whisper
-- beyond handing out the channel: reading the line on this side as well would be a second
-- place that has to agree about how to parse it.
local cmd = Instance.new("TextChatCommand")
cmd.Name = "WhisperCommand"
cmd.PrimaryAlias = "/w"
cmd.SecondaryAlias = "/whisper"
cmd.Parent = commands

-- Channels nobody is in any more. A pair who both leave would otherwise leave their channel
-- behind for the life of the server, and a town that has been up all day would be carrying a
-- channel for every pair who ever spoke.
Players.PlayerRemoving:Connect(function()
	-- Next frame: this fires before the player's TextSources are taken out of their
	-- channels, so counting now counts the one who is leaving.
	task.defer(function()
		for _, channel in ipairs(channels:GetChildren()) do
			if channel:IsA("TextChannel") and channel.Name:match("^RBXWhisper") then
				local live = 0
				for _, s in ipairs(channel:GetChildren()) do
					if s:IsA("TextSource") then live += 1 end
				end
				if live == 0 then channel:Destroy() end
			end
		end
	end)
end)
