# What still needs a pair of eyes

Things that are written, reviewed, and **not proven**, because proving them needs a window.

Headless has no viewport. A GUI built there has no extent — `AbsoluteSize` comes back
`0, 0` — so no click lands on anything, and there is nothing to photograph. A check written
against that passes whether or not the feature exists, which is worse than no check: it
reports success on a run that never exercised the thing. So these are listed rather than
tested badly.

Run any of them with a window — the same command without `--headless`:

```
cd luau/gdextension/demo2
& "C:\tools\godot\Godot_v4.3-stable_win64.exe" "--path" "." "-s" "res://tests/<name>.gd"
```

---

## Waiting on a look

| What | How to tell it works | Why headless cannot |
|---|---|---|
| **The intro** (`intro_test.gd`) | Card, black, rocket, town, in that order, and the loading bar in the dark | It takes screenshots |
| **The Wizard Hat** | It is still worn on its side, and the fix will not show until the item is republished — the one on chain predates it. See below. | The asset is stale, not the code |
| **Nipple-pegs, both sets** | Same stale asset as the hat: three degrees of turn, probably invisible either way, but it goes with the same republish | The asset is stale, not the code |
| **The four side-on NPCs** | Mira, Ozz, Sal and Fen: arms attached to the body, not floating 0.55 studs off it | as above |
| **The tailor** | Draw a cape, publish it: five prompts, then it is in your wardrobe and looks like the drawing. The encoder is now the place's, so this exercises Png.luau in anger. | Drawing needs a mouse, and publishing needs five real signatures |
| **The cane's cast** (`cast_shot.gd`, `hold=6` for a full charge) | Hold the button: the arm goes up, and once it is up VanishingBlocks plays six times slow as it charges; let go and nothing fires -- the charge is kept -- and the next click throws it with MegaBuster, deeper and slower the more was kept: a plain click is the clip as it is, a full charge six times lower. The orb grows with it, up to four times across. Walk while holding and the arm comes down and the charge and its sound pause; stop and they carry on. A full charge strobes red, magenta, purple, blue, cyan until it is thrown (`hold=7.5` photographs it). The speeds, sizes and damage are tested (`cast_test`, `cast_hit_test`); whether a 6x-slow VanishingBlocks and a 6x-down MegaBuster sound good is for ears. | Headless has a dummy audio driver |
| **The space fishing leaderboard** (`fish_board_shot.gd`) | Funmaster Mike's "Space Fishing Leaderboard": ten rows, a side-on fish in its bubble helmet by each colour and the top three beside it; the top row a "?" until the Everliving Fish is found, then its picture and who found it. The shot stands in a made-up catch, since no Fishing contract is deployed; the rod hand-off is `fishing_rod_test`. | It photographs the panel |
| **Fish and the rod in the bag** (`bag_fish_shot.gd`) | Every fish and the rod show as their model -- in the bag, the hand sockets, the action bar, and under the pointer while dragged -- since the town's own things have no thumbnail (`ModelPicture.luau`). | It photographs the panel |
| **The WoW controls** (`Controls.client.luau`) | Walk with WASD as before. Right-drag: the camera turns and he faces where it looks, A / D stepping sideways. Ctrl + right-drag: the camera looks around on its own while he keeps his facing, W / S walking along it and A / D turning him. Press or let go of Ctrl mid-drag and it switches there and then. `facing_test` drives all of it with synthetic events and reads the server; whether it feels like WoW needs hands on a mouse. | Real mouse and keyboard |
| **Sound effects** | Put a `ReverbSoundEffect` on a Sound and play it: it should sound reverbed. The wiring is tested (bus, order, teardown); the *sound* is not. | Headless has a dummy audio driver — nothing is audible |
| **`TremoloSoundEffect`** | The volume should wobble at `Frequency` Hz, dropping by `Depth`. Ours — Godot ships none. Built and tested; the wobble needs ears. | Headless has a dummy audio driver |
| **The Screener's search** | Type in the box at Ozz's counter; the list narrows as you type and the subtitle counts matches | GUI |
| **Bots** | `bots.ps1` — nine dummies in a row and a Runner walking a circle. Hit them. | The point is to fight them |
| **The Engram** | Take one from Bex (Show me what I've done → Take Engram *n*): three prompts, then a translucent PulseChain badge in your off hand with a heartbeat lit across it. Turn it over. | The geometry is checked (`engram_test`); the look of it is not |
| **BFS 9000's eight** | Click with it: one diagonal cut down to your left; click again: the mirror, down to your right. Each is slow and heavy, and the off hand joins the grip for both. | `spoon_test` / `offhand_test` check the joints; how it feels at half the old pace does not show in numbers |
| **The spawn shield** | Die, or join: you arrive in a blue bubble for six seconds, and a swing, an orb or a torch passes through you without a mark or a shove. | `forcefield_test` checks the shield and the refusal; the bubble's look is not |
| **The cane's charge sound** | Hold a charge with the cane: the drone swells into a big room, at its fullest by five and a half seconds, and from two seconds thins as a high-pass sweeps up until it is bright and without its low end at full. Let go part-way and charge again: it picks up as wet and as thin as that far in. | `cast_test` reads the reverb and the filter's settings, `audio_api_test` the bus; how the sweep sounds needs ears |
| **Take Engram, from the scan** | The button is on the panel from the moment it opens, including the front page. Dim there, and pressing it says to open a block or an address first; lit once you are on one. It costs nothing and signs nothing -- an Engram is a link the server holds for you while you are here -- so it should land instantly and appear in your bag. | GUI |
| **Louis** | Darker leather — body, neck, head and tail. The bill's orange and the gold monogram are untouched. Needs the same republish as the hat before it shows. | The asset is stale, not the code |
| **The sky's sun, moon and stars** | `Sky.StarCount = 3000` at midnight: stars, thinning as the sun comes up. A `SunTextureId` should sit exactly where the shadows point away from. `MoonAngularSize` should be believable at 11 and silly at 60. | The numbers reaching the shader are tested; a sky is a thing you look at |
| **Emitter shapes** | A `Cylinder` emitter should be a ring of particles, a `Disc` a flat one, `ShapeStyle = Surface` a skin rather than a fog, and `ShapeInOut = Inward` particles falling toward the middle. | The cloud is tested exactly; whether it reads as a cylinder is a look |
| **`VelocityInheritance`** | Carry a torch at a run: at 0 the sparks stay where they were lit, at 1 they come with you. | Needs a runner |
| **PBR maps** | A `SurfaceAppearance` with a NormalMap should look bumpy under a moving sun; a `MaterialVariant` with `StudsPerTile` should tile rather than stretch. | Which slots the maps reach is tested; whether they read as a surface is a look |
| **Water that moves** | Carve a pool, set `WaterWaveSize = 2` and `WaterWaveSpeed = 20`: it should roll, and the light should roll with it rather than sliding over a still surface. `WaterReflectance = 1` should read as a mirror. | The numbers reaching the shader are tested; waves are a thing you watch |
| **Sun rays** | A `SunRaysEffect` in Lighting at a low sun: shafts through the air. `Spread = 0` should be narrow beams and `1` a broad glow. | The numbers reaching the fog are tested; shafts are a thing you look at |
| **`ClickDetector.CursorIcon`** | Set one on a detector; the pointer becomes that image while it is over the part and goes back to what it was on the way out. | Needs a pointer, which headless has not got |
| **The emotes** | `/wave` `/sit` `/lay` (and `/lie`), and `/roll` to turn over once you are down. The shapes are measured; whether a six-part body reads as *sitting* rather than as a shape is a look. Sitting should meet the floor -- if it hovers or sinks, `hold` in `Emotes.luau` is the number. | Poses are tested exactly; how they read is not |
| **Standing up by walking** | Press a key while sat: you should stand instantly, not after three studs. That half cannot be tested -- the world rewrites `MoveDirection` every frame from the client's own input, so nothing a script sets to it survives to be seen. Straying three studs is the half that is tested. | Needs real input |
| **The shelf, after the move** | Sal's cards, your bags and your rung all come from `Chain.server.luau` now rather than from the client. Everything should look exactly as it did. | The numbers are tested; the panels are not |


## Checked, with a window

Run windowed (drop `--headless`) and driven from a script -- clicks and hover synthesised
through `Input.parse_input_event`, the frame read back off the viewport texture. `Main.gd`
takes `show_title = false` so none of it needs anybody to press Start.

| What | What it did | How it was checked |
|---|---|---|
| **`GuiObject.Interactable`** | A click on a button inside the panel registered; `Interactable = false` on the panel swallowed it; `true` again let it through. 1 / 0 / 1. | Real mouse-down and mouse-up at the button's own `AbsolutePosition` |
| **The GUI inset** | A `ScreenGui` keeping the inset starts at y = **36**; one with `IgnoreGuiInset` starts at y = **0**. | Read `AbsolutePosition` off a frame in each |
| **`GuiBase2d.AbsoluteRotation`** | A frame at `Rotation = 30` holding one at `15` reports **30** and **45**. `AbsoluteSize` reports real extents (200x100, 60x40) rather than the zeroes headless gives. | Read both back after a frame |
| **`Sound.PlaybackLoudness`** | **0** idle, peaks **319.9** while playing, **0** again on stop. In range and moving with the audio rather than with Volume. | Played a real clip and sampled for a second |
| **`Tool.ToolTip`** | The hotbar slot carries "It prods things." | It is Godot's own tooltip, so the check is that the string reaches the control's `tooltip_text` -- the popup after that is the toolkit's |
| **UI size button** | The cycle is **1, 1.25, 1.5, 1.75**. 1.75 is back; 2x stayed gone. | Read `Theme.scaleSteps` |
| **Studs and inlets** | Eight studs on a 4 x 1 x 2 brick, catching the light from the side; the inlet face reads as the rim of a hole. | Photographed both, side by side |
| **A pre-2016 hat** | An Accessory with no Attachment anywhere in it, only `AttachmentPos`, sits ON the head: handle at y 5.80, head at 5.40, which is the 0.4 it asked for. | Measured and photographed |
| **The force field** | A clear blue bubble round the whole body, the character visible through it. | Photographed |
| **The hit ghosts** (`hitbox_shot.gd`; `/hitbox` in the town) | A clear blue ball on every body, the size its root counts for; while a stroke cuts, a red capsule from the swinger's root out to the weapon's reach, as wide as its radius. The BFS 9000's is long and narrow and starts late in its swing. | Photographed: Spoonie from the side and above, 2026-09-16 |
| **Emitter shapes** | `Disc` is plainly flat, `ShapeStyle = Surface` is a shell rather than a fog, and `ShapeInOut = Inward` falls toward the middle. **Cylinder is still unchecked** -- it was behind the scenery in the shot. | Four emitters side by side, photographed |

## Run, and what they said

All fourteen were run windowed on 2026-09-11. Three of them were lying, and one long-standing
bug was real.

| Test | Verdict |
|---|---|
| `bar_click_test` | **Was failing, and not the town's fault.** "A press on the world does not swing", which reads as combat being broken. It never set `show_title = false`, so the whole run happened behind the title screen — and `Weapons.client`'s `windowOpen()` is true while any non-HUD ScreenGui is up, so the spoon was disarmed throughout. It also clicked where the arithmetic said square 1 was rather than where the bar says it is, thirty-three pixels apart. Fixed: 0 swings from a square, 1 from the world. |
| `candle_test` | **Was 11 of 13**, and stale rather than broken: it demanded every visible piece be Neon and that there be at least five. True of the candle as first built — one body and four tongues. The candle has three tongues now, each its own colour, and a Slate wick, because a wick that glows is not a wick. The check names the exception instead of counting. **13 / 13.** |
| `pvp_test` | **Was 7 of 10**, and had not been run since the Funmaster moved onto `write`. Not his fault: it asserted "duelling starts on", and the Funmaster reads `fighting(address)` off the Duelling contract a second into every start — so the signed-in wallet decides the answer, and this one has duelling **off** on chain. A fact about an account, not about the town. It asks the town for its default now and sets the state it needs. **14 / 14.** |
| `intro_test` | **Was 5 of 10**, and that one is recent: it held the dark open by publishing only the splash, which no longer works now the host announces when it has finished the manifest. The whole dark is under five seconds; the test sampled at nine. Samples mid-roar now. **10 / 10.** |
| `cull_test` | Photographed the **title card**, then the intro's black. Both fixed. Looked at: two rockets, the blanket-reversed one and the per-face one, both solid. **Passes.** |
| `squash_test` | Same two staleness bugs. Looked at: the right-hand emitter is plainly a tall column against the left one's round blob. `Squash = 3` works. **Passes.** |
| `combat_test` | **9 / 0.** |
| `torch_test` | **12 / 0.** |
| `title_test` | **12 / 0.** |
| `sfx_test` | **9 played, 0 silent.** |
| `vgm_test` | **4 / 0.** |
| `font_test` | **1 / 0** — 811 of 19200 sampled pixels differ from the fallback, so the file's own face is reaching the label. |
| `draw_test` | All three: a drawn weapon swings, one just swapped to is refused, and it swings once drawn. |
| `hit_test` | A probe rather than a pass/fail — it prints what is under a pixel. Useful, not a verdict. |

**Thirteen of the fourteen never set `show_title`.** They were all written before the title
screen existed and none of them started asking for it to be skipped. The ones that only read
the tree were unaffected; the ones that photograph or click were all testing the title card.
If you write another, set it — and wait for `intro:` before taking a picture, because the
intro holds a black over the window for several seconds after the title has gone.

**Un-anchoring a welded assembly is fixed.** It was diagnosed here and left standing; now
measured. An assembly whose anchored part is also its biggest fell **0.00 studs** when let
go, and falls 203.47 with the fix. The root is chosen as an anchored member if there is one
and otherwise the biggest, so unanchoring the anchored part changes the root only when it was
not also the biggest — and when it keeps the root, nothing rebuilt the body. `unanchor_test.gd`
checks both shapes, because only the first was ever broken.

## Still waiting on a look

`prompt_click_test.gd` took **`ProximityPrompt.ClickablePrompt`** off this list, and found a
real bug doing it: a prompt opened with the mouse fired once and then refused every trigger
after it, the key included, because a click had no release to match its press. Clicking a
door once meant it never opened again.

Everything in the first table that is not named above. The ones with the clearest path now
that the windowed harness works again: **`ClickDetector.CursorIcon`** (a hover away), the **Cylinder
emitter** (a photograph beside the three already checked), the **emotes** and the **sky**
(photographs). The rest are sound, which needs ears, or assets, which need publishing.

**The Wizard Hat needs republishing, not fixing.** The generator stopped emitting turned
Handles some time ago — `accessory()` slips an untuned speck in front when the first part is
turned — but the item on chain was published before that, and its Handle is the Brim with
`Orientation = [0, 0, 90]`. `worn_test` measures both shapes offline: the fixed one puts the
tip at y 6.04 straight above the head, the published one at x 3.22 lying on its side. One
command, when you want it:

```
node scripts/publish-catalogue.js --only wizardhat
```

It moves the existing token's uri rather than registering a new one, so id 39 stays id 39 and
anyone already holding it gets the fixed model. `crudespoon` wants the same treatment: its
stem was called "Handle" too, which gave the model two of them.

**A decision waiting for you.** Roblox's own `Instance.new("Part")` comes back with
`TopSurface = Studs` and `BottomSurface = Inlet`; this engine's schema has always said
`Smooth` for all six. Matching Roblox is one word in `pulseblockz_world.h` and one line in
`rbx_instance.cpp` -- and it studs every part in every place at once, which is a restyle
rather than a fix, so it is yours to call.

`pvp_test` in particular has never been run since the Funmaster moved onto the `write`
primitive.

`buy_live` and `tailor_live` spend real gas and are not part of the offline suite. Both were
rewritten when the collectors moved: `buy_live` was still writing `{"action":"buy","id":n}`,
a request shape the client stopped answering some time ago, so it had been failing for a
reason that had nothing to do with buying.

---

Anything on this list that turns out to work should get a windowed test written for it, so
it stops needing a person. Anything that turns out **not** to work is a bug that shipped
looking finished, which is the failure this file exists to make less likely.
