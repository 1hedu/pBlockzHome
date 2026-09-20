-- The pointing hand, in place of the operating system's arrow.
--
-- Final Fantasy VII does not draw an arrow: it draws a white gloved hand with one finger out,
-- sitting beside whatever it is choosing. The town borrows that game's panels and its font
-- already, and the cursor was the last thing on screen still wearing its own clothes.
--
-- It lives with the town rather than with the program that opens the town. The launcher used to
-- draw it and hand it to Godot, which meant the hand appeared when the town was opened by the
-- one app that had the art and nowhere else: a player who joined the server, or opened the
-- published town in the Player, got the arrow. MouseIcon is the property for this and every
-- client honours it, so the hand travels with the place, like the font and the sounds.
--
-- Roblox puts the hotspot at the middle of the picture and offers no property for it, so the
-- picture is padded: the fingertip sits at the centre and the rest of the hand hangs off it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local folder = ReplicatedStorage:WaitForChild("PlaceAssets", 30)
local cursor = folder and folder:WaitForChild("Cursor", 25)
if not cursor or cursor.Value == "" then
	warn("cursor: the place's own pointer never arrived; the arrow stays")
	return
end
UserInputService.MouseIcon = cursor.Value
