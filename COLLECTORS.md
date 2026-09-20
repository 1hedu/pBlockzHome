# The collectors: where the line ended up

This file used to say why the split stopped short of the collectors. It didn't. Here is
what moved, what stayed, and the reasoning that decided each — which is the part worth
keeping, because the same question comes up every time something new wants the chain.

## The line

**Deciding what to ask for is the place's. Going and getting it is the client's.**

The same line that put the PNG encoder in the place and left the decoder in the client.

| | |
|---|---|
| Which contracts, which functions, which ids | the place, via `read` |
| Making the RPC calls | the client |
| Fetching a `pblockz://` uri and checking its hash | the client, via `fetch` |
| Deciding *which* uri to fetch | the place |
| Turning bytes into something drawable | the client — `fetch as = "file"` / `"model"` |
| Turning metadata into a shelf card | the place |

## What moved

`Chain.server.luau` reads the registry, the marketplace and the ladder into one catalogue,
and reads each signed-in player's holdings — the Registry's balances and the Inventory
contract, by the address they signed in with — fetching the metadata and mounting the models.
`Ledger.data(player)` puts that player's picture together: the catalogue, their holdings, and
the wallet half their own machine sent. It is the same shape every desk always read, one
player at a time. `Engrams.luau` and `Engram.luau` took the last of it: the badge you carry is a
model the town builds now, not a shape compiled into the client.

`Registry`, `Marketplace`, `AssetStore` and `Donations` joined `Inventory` and `Duelling` in
`Contracts.luau`. `luau/gdextension/host/Wallet.gd`'s `ADDRESSES` has one contract left in it — the store
this client writes to by default — and that is configuration, not a rule.

## What the two verbs had to grow first

Both changes were prerequisites rather than conveniences, and both are worth knowing about
before adding anything here:

**`read` takes a list.** Forty items and forty-odd listings asked one at a time, each polled
at a tenth of a second by `Ledger.request`, is minutes of waiting and a hammered request
channel. A batch is three round trips. One malformed entry is answered in its own slot
rather than failing the batch — the alternative is a place discovering that one bad row
anywhere means the whole shop is empty.

**`read` decodes dynamic returns.** It used to refuse them, on the reasoning that half a
decoder is worse than none. The reasoning was right and the conclusion was not: `inventoryOf`
answers with three `bytes32[]`, `ladder()` with a list of rungs, `uri()` with a string,
`tokensFor()` with a list of addresses — so a place could not read its own contracts without
carrying an ABI decoder of its own. The fix for half a decoder is the other half, not a
second one somewhere else.

**`fetch` takes a list, and an `as`.** `"text"` for the JSON documents, `"file"` for a
picture an ImageLabel can be pointed at, `"model"` for something the game can clone. It also
takes the *parts* — a hash, a store, a blob id — because `inventoryOf` answers with hashes
and a place should not have to know how a `pblockz://` uri is spelled.

## What stayed in the client, and why

Not everything in `_collect` was a town's business. What is left is what a **wallet** is:

* **the account** — address, gas balance, token balances, nonce. A wallet showing your
  balances is a wallet.
* **the chain** — height, base fee, chain id. Facts about where you are standing.
* **your history** — read from the explorer, about your own address, needing no contract.
* **PulseX** — swapping and liquidity. A wallet does swaps; this is not this town's feature.

That half is published into the player's own tree as `Chain.Wallet`, and `Mine.client.luau`
hands it to the server for that player's desks — shown to them, never believed: a half naming
an address other than the one they signed in with is dropped. A place that wants nothing to
do with any of it can ignore `Wallet`; a place with no `Chain` script has no catalogue at all,
which is the honest outcome rather than a client-shaped one.

## The traps

Two things bit during the move and will bite again:

**A successful `read` used to trigger a full refresh.** Harmless while every reader was a
person leaning on a desk. A loop the moment a place reads on a schedule: the payload lands,
the place reads because it landed, the read refreshes, the payload lands. Only the verbs
that change something refresh now.

**`fetch` warmed only the blob path.** Assets published as transaction calldata need their
manifest read and then their chunks — a different pass entirely — so forty thumbnails were
being fetched one at a time. Warming both is most of a minute: 180s to 70s on a cold start.

## What still wants doing

The client's `chain_id`, `network`, `rpc_url` and token list are configuration living in
source. They should be a settings file, so a client can point at another deployment without
a rebuild. Right now it can only ever talk to this one.
