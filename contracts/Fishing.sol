// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @notice The random number a cast is decided by: atropaMath's `Random()`, or anything shaped
///         like it.
interface IRandom {
    function Random() external returns (uint64);
}

/// @notice Where the Everliving Fish's picture is kept: the AssetStore the town's own assets are in.
interface IAssetStore {
    function read(uint256 blobId) external view returns (bytes memory);
    function blob(uint256 blobId) external view returns (address publisher, bytes32 contentHash, uint32 size, string memory mime, address[] memory chunks);
}

/// @title  Fishing — space fishing off the edge of the town, decided on chain.
/// @notice Two transactions, both the angler's own. `cast` puts a line out; a random number of
///         blocks later a fish bites, and there are a few blocks to `reel` before it gets away.
///         What is on the end is decided when you reel, by a second random number, so knowing when
///         the bite comes tells you nothing about what it is.
///
///         Nine coloured fish, equally likely. And one Everliving Fish: undiscovered, a 1 in 5555
///         chance on any reel until somebody finds it. Catching it is a catch like any other, and it
///         gives the angler the right to claim the discovery -- which is optional, and a separate
///         transaction: `claimDiscovery` mints the one and only token this contract will ever mint,
///         "First Catch of the Everliving Fish", names them the discoverer, and unlocks the species
///         for everyone. From then on it is caught like the others, a little more often than any one
///         colour, and those are ordinary fish, not tokens. Until somebody claims, anybody who has
///         caught it may; the first to claim is the discoverer, and every other claim lapses.
///
///         Every catch is counted against the angler. Nobody can take a fish off you and nobody can
///         give you one: you caught it or you did not.
///
/// @dev    The random number comes from `rng`, fixed at deployment. It is only as unpredictable as
///         that contract is: if its sequence can be predicted and stepped, a patient angler can wait
///         for a winning reel. Everything the angler supplies is nothing -- no seed, no result -- so
///         the most they can choose is WHEN to reel inside the window.
///
///         Blocks, not timestamps, for the bite and the window: the wait is the chain's, not the
///         screen's, and a client that skips the animation still cannot reel early.
///
///         Ownerless: no admin, no pause, no upgrade, no privileged address.
contract Fishing is ERC721, ReentrancyGuard {
    IRandom public immutable rng;

    /// Species 0..8 are the colours, in this order; 9 is the Everliving Fish.
    uint8 public constant COLOURS = 9;
    uint8 public constant EVERLIVING = 9;
    uint16 public constant DISCOVERY_ODDS = 5555;
    uint8 public constant COLOUR_WEIGHT = 4;
    uint8 public constant EVERLIVING_WEIGHT = 5;
    /// A bite comes 1 + (0..BITE_EXTRA) blocks after the cast, and can be reeled in for REEL_WINDOW
    /// blocks after that.
    uint8 public constant BITE_EXTRA = 2;
    uint8 public constant REEL_WINDOW = 3;

    struct Line {
        uint64 nonce;
        uint64 biteBlock;
        bool out;
    }

    mapping(address => Line) public lines;
    mapping(address => uint64) public castCount;
    mapping(address => mapping(uint8 => uint32)) public caught;
    uint64[10] private totals;

    /// Everybody who has ever cast, so a leaderboard can be read off the chain with calls alone.
    address[] public anglers;

    /// Who has caught the Everliving Fish while it was undiscovered, and may claim the discovery.
    mapping(address => bool) public canClaimDiscovery;

    address public discoverer;
    uint64 public discoveryBlock;

    /// The token's picture: a PNG in an AssetStore, the same bytes the game draws the fish with.
    /// Fixed here for good -- nothing can point the token at another picture later.
    IAssetStore public immutable pictureStore;
    uint256 public immutable pictureBlob;

    string public constant DISCOVERY_NAME = "First Catch of the Everliving Fish";
    string public constant DISCOVERY_DESCRIPTION = "ROMANS VI:IV";

    event Cast(address indexed angler, uint64 indexed nonce, uint64 biteBlock, uint64 lastBlock);
    event Caught(address indexed angler, uint64 indexed nonce, uint8 indexed species, bool discovery);
    event GotAway(address indexed angler, uint64 indexed nonce);
    event Discovered(address indexed discoverer, uint64 blockNumber);

    /// @param store  the AssetStore holding the picture
    /// @param blobId the picture's blob there; it must exist and be a PNG, checked now rather than
    ///               found broken on the day somebody makes the discovery
    constructor(IRandom random, IAssetStore store, uint256 blobId) ERC721(DISCOVERY_NAME, "EVERLIVING") {
        rng = random;
        (, , uint32 size, string memory mime, ) = store.blob(blobId);
        require(size > 0 && keccak256(bytes(mime)) == keccak256("image/png"), "the picture must be a PNG in the store");
        pictureStore = store;
        pictureBlob = blobId;
    }

    /// @notice Whether the Everliving Fish has been found.
    function discovered() public view returns (bool) {
        return discoverer != address(0);
    }

    /// @notice Put a line out. One at a time; a line whose window has passed can be cast over.
    function cast() external nonReentrant {
        Line memory line = lines[msg.sender];
        require(!line.out || block.number > line.biteBlock + REEL_WINDOW, "your line is already out");
        if (castCount[msg.sender] == 0) anglers.push(msg.sender);
        uint64 nonce = ++castCount[msg.sender];
        uint64 bite = uint64(block.number) + 1 + uint64(rng.Random() % (uint64(BITE_EXTRA) + 1));
        lines[msg.sender] = Line({ nonce: nonce, biteBlock: bite, out: true });
        emit Cast(msg.sender, nonce, bite, bite + REEL_WINDOW);
    }

    /// @notice Reel in. Too early reverts; too late and it got away.
    function reel() external nonReentrant returns (uint8 species, bool discovery) {
        Line memory line = lines[msg.sender];
        require(line.out, "no line out");
        require(block.number >= line.biteBlock, "nothing has bitten yet");
        delete lines[msg.sender];
        if (block.number > line.biteBlock + REEL_WINDOW) {
            emit GotAway(msg.sender, line.nonce);
            return (type(uint8).max, false);
        }

        uint256 roll = uint256(keccak256(abi.encode(rng.Random(), msg.sender, line.nonce, address(this), block.chainid)));
        if (!discovered()) {
            if (roll % DISCOVERY_ODDS == 0) {
                species = EVERLIVING;
                discovery = true;
                canClaimDiscovery[msg.sender] = true;
            } else {
                species = uint8((roll >> 16) % COLOURS);
            }
        } else {
            uint256 pick = (roll >> 16) % (uint256(COLOURS) * COLOUR_WEIGHT + EVERLIVING_WEIGHT);
            species = pick < uint256(COLOURS) * COLOUR_WEIGHT ? uint8(pick / COLOUR_WEIGHT) : EVERLIVING;
        }
        caught[msg.sender][species] += 1;
        totals[species] += 1;
        emit Caught(msg.sender, line.nonce, species, discovery);
    }

    /// @notice Claims the discovery of the Everliving Fish, for someone who has caught it while it was
    ///         undiscovered: mints the one token, names them the discoverer, and unlocks the species.
    function claimDiscovery() external nonReentrant {
        require(!discovered(), "the Everliving Fish has already been discovered");
        require(canClaimDiscovery[msg.sender], "you have not caught the Everliving Fish");
        canClaimDiscovery[msg.sender] = false;
        discoverer = msg.sender;
        discoveryBlock = uint64(block.number);
        _mint(msg.sender, 1);
        emit Discovered(msg.sender, discoveryBlock);
    }

    /// @notice Where an angler's line is, and where the chain is: whether a line is out, the block a
    ///         fish bites at, the last block it can be reeled in, and the block this was read at --
    ///         everything a client needs to show the float, the bite and the fish getting away.
    function lineOf(address angler) external view returns (bool out, uint64 biteBlock, uint64 lastBlock, uint64 nowBlock) {
        Line memory line = lines[angler];
        return (line.out, line.biteBlock, line.biteBlock + REEL_WINDOW, uint64(block.number));
    }

    /// @notice An angler's catches, by species: the nine colours, then the Everliving Fish.
    function caughtOf(address angler) external view returns (uint32[10] memory out) {
        for (uint8 i = 0; i < 10; i++) out[i] = caught[angler][i];
    }

    /// @notice How many of each species have been caught by everybody.
    function totalsOf() external view returns (uint64[10] memory) {
        return totals;
    }

    function anglerCount() external view returns (uint256) {
        return anglers.length;
    }

    /// @notice The token's metadata, made here and now out of what is on chain: its name, its
    ///         description, and its picture read straight out of the AssetStore -- the same bytes the
    ///         game draws the fish with. Returned as a data: URI, so any wallet or marketplace can show
    ///         it with no server, no gateway, and nothing anybody could ever swap out.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        bytes memory json = abi.encodePacked(
            '{"name":"', DISCOVERY_NAME,
            '","description":"', DISCOVERY_DESCRIPTION,
            '","image":"data:image/png;base64,', Base64.encode(pictureStore.read(pictureBlob)),
            '"}');
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }
}
