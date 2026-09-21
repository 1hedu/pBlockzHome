# pBlockz Home

A town on PulseChain, played in PulseBlockz. Everything it is lives on chain: every script here
is published by its content hash, and the hash of the whole thing is the game.

    pblockz://2591ffe2b9390e371cb19474c45e3676fcdc9c676a20cb53a9ec5ae3b3bd96ab

Open that link in the PulseBlockz Player to play it alone, or join the town at
`play.safewrap.xyz:8800`, where the same hash is what the server runs.

## What is here

| | |
|---|---|
| `src/` | the place: Luau for the server, the client and what they share, laid out for Rojo (`default.project.json`) |
| `models/`, `assets/` | what it is made of — meshes, sounds, the skybox, the font — in the form the tools publish from |
| `place-assets.json` | each of those by name, and the `pblockz://` it was published as |
| `town/` | the Godot project the town is served from: `Serve.gd` for a server, `Join.gd` for a client, `Main.gd` for either, and its own tests |
| `contracts/` | the four this game owns — fishing, duelling, the duel records, the noticeboard — and two stand-ins for a local chain |
| `tools/` | deploying those, and publishing the place and its assets |
| `addresses.943.json` | where all of it lives on testnet v4 |

## What is not here

The engine, the Studio, the Player, the Publisher and the host layer are
[PulseBlockz](https://github.com/1hedu/pBlox) — the suite this is a game for. `town/` has no
`host/` folder for that reason: those scripts are the suite's, copied into a project by its
`scripts/sync-host.js`, and a second copy here would only drift. To run `town/` you need the
suite's checkout beside this one, for `host/` and for the engine the project loads.

## Publishing it

    node tools/publish-place-assets.js          # the art, each by its own hash
    node <suite>/scripts/publish-experience.js . "pBlockz Home" \
      --uses chain,transact,sign,pulsex,scan,market \
      --server play.safewrap.xyz:8800 \
      --assets place-assets.json \
      --contracts src/shared/Contracts.luau

The uses are what the place may ask a player's wallet for, and a client refuses anything not
declared — so a missing flag is a game that silently cannot read the chain.
