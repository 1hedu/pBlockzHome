# Open

Things known to be wrong, or known to be untested, that are not fixed yet. Kept here because
until now they lived in a chat log, which meant they survived exactly as long as the session
did and had to be re-reported by the owner every time.

Rules for this file: something goes in when it is found, and comes out in the commit that
fixes it. "Untested" is an entry in its own right — most of this week's real bugs were sat
behind a test that passed while asking the wrong question.

## Parity program: solid modelling and what it touches

Every gap found while making Spoonie's rim, written down so none of them is quietly dropped.
Sources are Roblox's own doc files (github.com/Roblox/creator-docs). Built in this order,
because each needs the ones above it. An item comes off this list in the commit that builds it.

1. **CSG API, exactly as documented.** Built: `fdb69d7` and the CalculateConstraintsToPreserve
   commit. `solid_rules_test` (24) and `solid_constraints_test` (11) hold it to the reference.
2. **`Content`.**
   - 2a, the datatype: built. `content_test` (22), `content_net_test` (6).
   - 2b, the Content properties on classes the kit has: built. 39 pairs, each reading and
     writing its string twin; which objects each may hold; PluginSecurity on read; .rbxm type
     0x22 and .rbxmx `<uri>`/`<null>`; saves keep the Content, not the string; an EditableImage
     draws through any image property. `content_props_test` (21), and Studio's save checks.
     `MeshPart.MeshId` / `MeshContent` refuse every script, and `AssetService:CreateMeshPartAsync`
     makes the part instead; the Tree uses it. `meshpart_async_test` (15), `tree_meshpart_test` (10).
   - 2b, the rest: built. Decal's PBR maps drawn and its ColorMap names (other names for
     TextureContent, as rbx-dom stores them); EmissiveMaskContent / Strength / Tint drawn on
     SurfaceAppearance and MaterialVariant; TexturePackContent and HSR the engine's alone.
     `content_maps_test` (16); `tests/maps_shot.gd` photographs it.
   - The Content properties of classes the kit does not have yet arrive with each class:
     AdGui, AudioPlayer, CharacterMesh, DragDetector, ImageHandleAdornment, InputActionLabel,
     InputBinding, PackageLink, Pants, PluginToolbarButton, ScreenshotHud, Shirt,
     ShirtGraphic, TerrainDetail, UIDragDetector, VideoFrame, VideoPlayer, VideoSampler,
     WrapTextureTransfer.
   - Found beside them, not Content, next to build: `SurfaceAppearance.AlphaMode` is declared and
     the host ignores it (Overlay / Transparency / TintMask all draw alike); SurfaceAppearance
     `Color` and `ResampleMode`; MaterialVariant `AlphaMode` and `CustomPhysicalProperties`;
     Decal `Rotation`, `UVOffset`, `UVScale`, `LocalTransparencyModifier`, `AutoLocalize`.
     Layered clothing is not drawn at all: WrapLayer / WrapTarget are declared only, so HSR has
     nothing to hide.
   - 2c, Object: built. EditableImage is an Object, not an Instance; objects live while a script,
     a Content or a property holds them; a side without the object gets the placeholder (reads
     throw, draws as the cyan and magenta checkerboard); ImageCombineType numbered as Roblox
     numbers it, with NormalMapBlend, Subtract and anti-aliasing; DrawImageTransformed;
     CreateEditableImageAsync; CreateDataModelContentAsync and Opaque Content, which replicates.
     WritePixels / ReadPixels / Resize / Copy removed, as Roblox removed them. `object_test` (37),
     `content_net_test` (12).
   - 2d, EditableMesh: built. The whole method set, stable ids, split attributes, batches,
     bones and FACS poses kept, the 60,000 / 20,000 limits, FixedSize; CreateEditableMesh(Async);
     CreateMeshPartAsync and ApplyMesh on one, drawn live at the scale it was applied with, its
     collision kept until applied again; baked meshes; DrawImageProjected / SampleImageProjected.
     `editable_mesh_test` (47); `tests/mesh_shot.gd` photographs it.
   - Still open, found on the way:
     - Skinned meshes are not drawn: an EditableMesh's bones, weights and FACS poses are kept
       as data and nothing deforms by them (`MeshPart.HasSkinnedMesh`, FaceControls).
     - A Content holding an object sent through a RemoteEvent arrives as Content.none, not as a
       placeholder. Roblox documents the placeholder for replicated properties; what a remote
       does is not documented and is untested against Roblox.
     - Play Solo draws the server's tree, so a server script's EditableImage shows as the image
       there, where a Roblox player would see the placeholder.
2½. **The rest of the scripting surface is not measured.** `PARITY.md` counts classes only.
   Globals, libraries, datatypes and enums are not on it -- found because `collectgarbage` was
   missing outright (now built). The sandbox also strips `getfenv`, `setfenv`, `debug` and
   `loadstring`/`newproxy` status is unknown; Roblox has all of these. Measure them into
   PARITY.md, then build what is missing.
3. **How PartOperations draw and collide.** Built. `SmoothingAngle` smooths only between faces
   of one colour (0, the default, is flat); `RenderFidelity` Automatic drops to half the
   triangles past 250 studs and a quarter past 500, Precise never does, Performance is always
   the quarter; PartOperations are box-mapped, so a Decal lies on a union's faces and not over
   its holes, and a MeshPart result keeps the main mesh's UVs with the rest at (0,0) (MeshData
   is version 3, with UVs); `CollisionFidelity` Box and Hull are one convex shape, Default,
   PreciseConvexDecomposition and Tunable are convex decompositions a ball can drop into a
   notch of. `solid_render_test` (23); `tests/union_shot.gd` photographs it.
   - Still open, found on the way:
     - Tunable's tuning (PhysicalConfigData) is engine data Roblox does not document; it
       decomposes between Default and Precise.
     - A decomposition runs on the frame a mesh is first shaped (cached by mesh after that):
       three big town meshes at 4x cost a 132 ms frame on Default, 150 ms on Precise, against
       92 ms on Hull (`tests/decompose_time_probe.gd`). Roblox bakes it at upload.
     - Studio's Union tool (`../studio/Solid.gd`) still writes MeshData version 1: no colours, no
       UVs. Item 5 rebuilds it.
4. **Spatial queries against real geometry.** Raycasts and overlap queries use the actual shape
   of unions and MeshParts, not their boxes, so a hole can be shot through.
5. **Studio.** The Intersect tool (Shift+Ctrl+I, named Intersection), a negated part's red tint,
   and Separate for intersections.
6. **GeometryService extras (Roblox beta).** `FragmentAsync`, `GenerateFragmentSites`,
   `SweepPartAsync`.
7. **Fluid forces.** `BasePart.EnableFluidForces`, `FluidFidelity`, Workspace aerodynamics.
8. **The new audio API.** AudioPlayer, AudioEmitter, AudioListener, AudioDeviceOutput, Wire and
   the rest, with `AudioCanCollide` occlusion and reflection.

## Broken, seen in play

- **Bots wear the owner's whole wardrobe, including the Cane.** Wardrobe dresses walletless bots.
- **Grey box near the NPCs.** Not seen for a while; may already be gone. Unidentified.
- **Bots flying vertically off the map.** Not seen for a while. The shove adds to `vel.Y`
  rather than setting it, and `fade` only stops it *growing* — worth a look if it returns,
  now that HURT_KNOCK is 2.0.
- **Headless floods `mesh_get_surface_count` / `Parameter "m" is null`.** Noise, but it
  buries real errors in every log.

## Not covered by any test

- **`Weapons.client.luau` — the real click path.** Eleven files fire `WeaponRemote` directly.
  Nothing has ever exercised the handler an actual mouse click goes through, with its draw
  gate and its refusal while a panel is open. `swing_watch_test.gd` was started for this and
  is incomplete.
- **Typing into the chat box.** Never driven by a test.
- **Being hit, from the victim's own screen.** Only the attacker's side is covered.
- **The bank's PvP flag, and death/respawn.** Named repeatedly, never written.
- **The trampoline and strong-hit sounds, by ear.** The Sound fix (`ad6b0d1`) is generic and
  the Familiar is measured audible on another machine, so these should follow — but neither
  has been measured itself, and "should follow" is what got us here.

## Harness

- **Clock-based waits, everywhere.** Tests advance on `task.wait` and fixed phase timers
  rather than on the condition they are waiting for. `knock_net_test` gave all-zeros on one
  run and correct numbers on the next off the same binary; `hitbox_test` passes alone and
  failed at `-Jobs 3`. This is the single biggest source of false results in the suite and
  it needs a `waitUntil(cond, timeout)` helper plus a pass through the flakiest files.
- **`studio_test` failed 4 checks once and passed the next four runs, same binary.** "nothing
  in the project maps to the Workspace itself", "a Camera with a file of its own is not swept
  away", "and no ground in it until you make some", "Workspace.CurrentCamera is a Ref". The
  failing run came straight after a parallel batch; load is the suspect, not proven.
- **`request_test` asks `Ledger.askScan`, which `3d20134` removed** when the scan moved to the
  client. Two of its checks fail on a Lua error; the test needs rewriting against the new path.
- **Fifteen tests print no "N passed, M failed" line** and the runner calls them NO RESULT:
  bar_click, cull, draw, font, hit, intro, load, place, read_time, sfx, squash, town, and
  more. Probes and timings in their own formats. Give each a result line or mark it a probe.
- **`trampoline_test` fails 4 runs in 5, same binary, before this week's Content work too.**
  "TrampolineBankEast goes up about thirty studs: 6", and the bed never flexes -- the last
  launch comes inside the pad's 1.6 s AGAIN cooldown, most likely. Measured on `020c2df`.
- **The full suite at -Jobs 3 ran the box out of memory** and was killed partway. -Jobs 2 for now.
- **`hitbox_test` bodies drift 130+ studs during a stand.** No longer breaks the test (the
  dummy is kept alive and the shove is stubbed) but nothing explains the drift itself.
- **The action bar's click sound is not asserted.** `bar_use_test` covers the three
  outcomes (act / remove / wear) but could not find the squares from `PlayerGui` to read
  their `Sfx` attribute. What it should be is written down in `ActionBar.client.luau`: none
  for a worn thing with a trick, since the trick makes its own noise.
- **Builds fight the running client for the DLL.** `scons` fails with "Access is denied" when
  a client holds `demo2/bin/...dll`, and the next run then measures the OLD binary. Check the
  build stamp before believing any result.

## Catalogue, waiting on the next publish

Built locally, on chain at an older shape or not at all. A `bots.ps1` run stages all of these
off disk now (`scripts/stage-preview.js all .preview`, then straight into
`ReplicatedStorage/OnChain`), so they can be worn and judged before anything is published.

- **Roma** — 3x bigger.
- **Spoonie** (key `crudespoon`) — renamed from Crude Spoon, and the head is round with a rim
  all the way round and the dish sunk inside it. The rim is a `UnionOperation` made by
  `SubtractAsync` (`tests/bake_spoonie_rim.gd` -> `scripts/models/spoonie-rim.json`), 0.07
  thick, centred on the stem; the dish is a `SpecialMesh` oval 0.002 thick at the bottom of the rim, so the hollow is the rim's whole depth. Its MeshData
  (version 3, with UVs) adds about 94 KB to the item's model JSON on publish.
- **BFS 9000** (key `spoonie`) — the big spoon, published as Spoonie; renamed SPOOM locally when Crude Spoon
  took the name Spoonie, and now BFS 9000, name only, plus a deep red shelf tile.
  The keys did NOT move with the names: a key is the publisher's content address
  (`item:<key>:<name>`), so renaming one orphans the manifest and republishes the item as a
  new slot rather than updating it. `crudespoon` is Spoonie and `spoonie` is BFS 9000.
- **Gold Glitter Dress Shoes** — the sole is gold with the red on its Bottom face only; it
  used to be a red box whose rim showed red from every side. The sole reaches 0.06 below the
  leg's end, so the trouser leg's bottom no longer flickers against the red.
- **Wizard Hat** — worn sideways; sits at the Top Hat's height (brim 0.43 lower); 18 stars
  scattered round the cone instead of 3.
- **Louis** — leather, and a new thumbnail.
- **Tang Cape** — the rename.
- **Crude Spoon** — two Handles collapsed into one.
- **Rolex** — the hands.
- **Black Dress Shoes** — the sole reaches below the leg's end, like the gold pair's.
- **Two torch tiles.**
- **Nipple-pegs** — a 3 degree tilt. Optional.

## Waiting on the owner

- **The publish.** Ten assets are staged off disk and not on chain: `SfxTrampoline`,
  `SfxStrongHit`, `SfxFamiliar1`, `SfxFamiliar2`, `TreeTrunkMesh`, `TreeCanopyMesh`, and the
  cane's orb, `OrbMesh`, and the gradient it and the Engram wear, `PulseGradient`, with the
  Engram's `EngramBadge` (`scripts/prep-gradient.js`), and the cane's sounds, `SfxCharge` and
  `SfxBuster` (`scripts/prep-sfx.js`). A `bots.ps1` run mounts them all, so they can be played
  without publishing; without its pictures the cane still fires and hits, as a plain purple ball,
  and without its sounds it is silent. The publish order
  is place assets -> `make-props.js` -> experience -> catalogue.
