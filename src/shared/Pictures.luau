-- A picture named by its uri.
--
-- A thumbnail is bytes on the chain, named by their hash: `pblockz://<hash>?...`. The engine takes
-- that as a content id the way it takes an rbxassetid://: fetched on the machine that draws it,
-- through that machine's own wallet, and drawn when the bytes are here. So a label is simply
-- pointed at the uri. This module once fetched each uri through the wallet by hand and pointed
-- the label at the file, from the days the server sent its own file paths; it stays as the one
-- place that says a picture is shown by its uri, and as the seam should that ever change again.
local Pictures = {}

function Pictures.show(label, picture)
	label.Image = type(picture) == "string" and picture or ""
end

return Pictures
