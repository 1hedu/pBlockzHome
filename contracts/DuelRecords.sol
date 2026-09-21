// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/// @title  DuelRecords — a ranked duel's result, once both sides have agreed to it, or witnesses have.
/// @notice A town keeps its duel results itself. Putting one here is optional, and it takes
///         both sides: somebody from one team sends the transaction and pays for it, and it
///         carries a signature from somebody on the OTHER team saying the result is right.
///         Nobody can write down a win the losers did not sign for, and nobody can write down
///         a loss the winners did not sign for.
///
///         That is consensus between the players, not proof. The chain cannot see a fight --
///         whether a blow landed is decided by two players' positions at one instant, which
///         only the server holding both can judge -- so what this records is that both sides
///         agreed on what happened. Nothing of value rides on it, and that is why agreement
///         is enough.
///
/// @dev    The signature is EIP-712 over `Result`, so a wallet shows the signer every field
///         before they sign, and a signature for this contract on this chain cannot be
///         replayed against any other.
///
///         Each id is recorded once. `kills` counts every recorded kill per address, which is
///         what a leaderboard ranks by: a win in a match to one and a win in a match to
///         twenty-five are not the same thing, and a kill is a kill. `wins` and `losses` are
///         kept beside it for anyone who wants them.
///
///         WITNESSED is the other way in, and it is kept apart on purpose. When one side will not
///         agree, the town asks the bystanders who were there, and a result they signed can be
///         recorded with their signatures instead. The chain cannot tell a bystander from a
///         spare wallet of the winner's -- only the town that asked them can -- so a witnessed
///         result never touches `kills`, `wins` or `losses`. It lands in `witnessedOf` and its own
///         `witnessed*` counts, and anybody reading them can decide what a witness is worth. The
///         agreed ledger stays one that nobody can write alone.
///
///         Ownerless: no admin, no pause, no upgrade, no privileged address.
contract DuelRecords is EIP712 {
    bytes32 public constant RESULT_TYPEHASH = keccak256(
        "Result(bytes32 id,address[] teamA,address[] teamB,uint16[] killsA,uint16[] killsB,uint16 limit,uint8 winner,uint64 endedAt)"
    );

    /// @notice The EIP-712 struct hash of what was recorded under an id; zero if nothing was.
    mapping(bytes32 => bytes32) public recordOf;
    mapping(address => uint32) public kills;
    mapping(address => uint32) public wins;
    mapping(address => uint32) public losses;

    /// @notice Results recorded on witnesses' signatures instead of the other side's, kept apart.
    mapping(bytes32 => bytes32) public witnessedOf;
    mapping(address => uint32) public witnessedKills;
    mapping(address => uint32) public witnessedWins;
    mapping(address => uint32) public witnessedLosses;

    uint256 public constant MAX_TEAM = 4;
    uint256 public constant MAX_WITNESSES = 16;

    event Recorded(
        bytes32 indexed id,
        address[] teamA,
        address[] teamB,
        uint16[] killsA,
        uint16[] killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt,
        address submittedBy,
        address signedBy
    );

    event Witnessed(
        bytes32 indexed id,
        address[] teamA,
        address[] teamB,
        uint16[] killsA,
        uint16[] killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt,
        address submittedBy,
        address[] witnesses
    );

    // The name below is not this project's name: an EIP-712 domain is part of the digest, so it
    // is part of the deployed interface. This contract is on chain with that string inside it and
    // every signature already made was made against it. It changes on a redeploy and not before.
    constructor() EIP712("PulseBlockz Duels", "1") {}

    /// @notice Whether an id has been recorded.
    function recorded(bytes32 id) external view returns (bool) {
        return recordOf[id] != bytes32(0);
    }

    /// @notice The digest the other side signs, for anyone checking a signature off chain.
    function digest(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt
    ) public view returns (bytes32) {
        return _hashTypedDataV4(_structHash(id, teamA, teamB, killsA, killsB, limit, winner, endedAt));
    }

    /// @notice Who signed a result -- zero for a signature that is not one. For a town checking a
    ///         signature it was handed before keeping it, with a read and no key.
    function signerOf(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt,
        bytes memory signature
    ) external view returns (address) {
        (address who, ECDSA.RecoverError err, ) =
            ECDSA.tryRecover(digest(id, teamA, teamB, killsA, killsB, limit, winner, endedAt), signature);
        return err == ECDSA.RecoverError.NoError ? who : address(0);
    }

    /// @notice Record a result. Sent by somebody on one team, signed by somebody on the other.
    /// @param killsA each of team A's kills, in the same order as teamA; a team's frags are the sum.
    /// @param winner 1 for team A, 2 for team B. Said outright rather than worked out from the
    ///        kills, because a duel somebody walked out of is won short of the limit.
    function record(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt,
        bytes memory signature
    ) external {
        require(recordOf[id] == bytes32(0), "already recorded");
        _valid(id, teamA, teamB, killsA, killsB, limit, winner);

        bytes32 structHash = _structHash(id, teamA, teamB, killsA, killsB, limit, winner, endedAt);
        address signer = _agreed(teamA, teamB, structHash, signature);
        recordOf[id] = structHash;
        _tally(teamA, killsA, winner == 1, false);
        _tally(teamB, killsB, winner == 2, false);
        emit Recorded(id, teamA, teamB, killsA, killsB, limit, winner, endedAt, msg.sender, signer);
    }

    /// @notice Record a result on witnesses' signatures, when one side would not agree. Sent by
    ///         somebody in the duel; every signature from somebody in neither team, each once.
    ///         Counted apart from agreed results -- see the contract's notes.
    function recordWitnessed(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt,
        bytes[] memory signatures
    ) external {
        require(recordOf[id] == bytes32(0), "already agreed and recorded");
        require(witnessedOf[id] == bytes32(0), "already witnessed");
        _valid(id, teamA, teamB, killsA, killsB, limit, winner);
        require(_has(teamA, msg.sender) || _has(teamB, msg.sender), "sender is not in this duel");

        bytes32 structHash = _structHash(id, teamA, teamB, killsA, killsB, limit, winner, endedAt);
        address[] memory witnesses = _witnesses(teamA, teamB, structHash, signatures);
        witnessedOf[id] = structHash;
        _tally(teamA, killsA, winner == 1, true);
        _tally(teamB, killsB, winner == 2, true);
        emit Witnessed(id, teamA, teamB, killsA, killsB, limit, winner, endedAt, msg.sender, witnesses);
    }

    function _valid(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner
    ) internal pure {
        require(id != bytes32(0), "no id");
        require(teamA.length > 0 && teamA.length <= MAX_TEAM, "team A size");
        require(teamB.length > 0 && teamB.length <= MAX_TEAM, "team B size");
        require(killsA.length == teamA.length && killsB.length == teamB.length, "a kill count for each player");
        require(winner == 1 || winner == 2, "winner is 1 or 2");
        require(limit > 0 && _sum(killsA) <= limit && _sum(killsB) <= limit, "frags past the limit");
        _distinct(teamA, teamB);
    }

    /// @dev Every signature recovers to somebody in neither team, and nobody signs twice.
    function _witnesses(address[] memory teamA, address[] memory teamB, bytes32 structHash, bytes[] memory signatures)
        internal
        view
        returns (address[] memory out)
    {
        require(signatures.length > 0 && signatures.length <= MAX_WITNESSES, "witness count");
        bytes32 digestHash = _hashTypedDataV4(structHash);
        out = new address[](signatures.length);
        for (uint256 i = 0; i < signatures.length; i++) {
            address who = ECDSA.recover(digestHash, signatures[i]);
            require(!_has(teamA, who) && !_has(teamB, who), "a witness was in the duel");
            for (uint256 j = 0; j < i; j++) require(out[j] != who, "a witness signed twice");
            out[i] = who;
        }
    }

    /// @dev The sender is on one team and the signature is from somebody on the other.
    function _agreed(address[] memory teamA, address[] memory teamB, bytes32 structHash, bytes memory signature)
        internal
        view
        returns (address signer)
    {
        signer = ECDSA.recover(_hashTypedDataV4(structHash), signature);
        bool senderA = _has(teamA, msg.sender);
        require(senderA || _has(teamB, msg.sender), "sender is not in this duel");
        require(senderA ? _has(teamB, signer) : _has(teamA, signer), "needs a signature from the other team");
    }

    function _tally(address[] memory team, uint16[] memory teamKills, bool won, bool witnessed) internal {
        for (uint256 i = 0; i < team.length; i++) {
            if (witnessed) {
                witnessedKills[team[i]] += teamKills[i];
                if (won) witnessedWins[team[i]] += 1;
                else witnessedLosses[team[i]] += 1;
            } else {
                kills[team[i]] += teamKills[i];
                if (won) wins[team[i]] += 1;
                else losses[team[i]] += 1;
            }
        }
    }

    function _sum(uint16[] memory list) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < list.length; i++) total += list[i];
    }

    function _structHash(
        bytes32 id,
        address[] memory teamA,
        address[] memory teamB,
        uint16[] memory killsA,
        uint16[] memory killsB,
        uint16 limit,
        uint8 winner,
        uint64 endedAt
    ) internal pure returns (bytes32) {
        // EIP-712 encodes an array as the hash of its elements' 32-byte encodings, which is
        // exactly what encodePacked does with an address[] or a uint16[].
        return keccak256(
            abi.encode(
                RESULT_TYPEHASH,
                id,
                keccak256(abi.encodePacked(teamA)),
                keccak256(abi.encodePacked(teamB)),
                keccak256(abi.encodePacked(killsA)),
                keccak256(abi.encodePacked(killsB)),
                limit,
                winner,
                endedAt
            )
        );
    }

    function _has(address[] memory list, address who) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) if (list[i] == who) return true;
        return false;
    }

    /// @dev Nobody on both sides, and nobody twice: a player cannot sign for the team they
    ///      are sending from by also being listed on the other one.
    function _distinct(address[] memory a, address[] memory b) internal pure {
        for (uint256 i = 0; i < a.length; i++) {
            require(a[i] != address(0), "zero address");
            for (uint256 j = i + 1; j < a.length; j++) require(a[i] != a[j], "listed twice");
            for (uint256 j = 0; j < b.length; j++) require(a[i] != b[j], "on both teams");
        }
        for (uint256 i = 0; i < b.length; i++) {
            require(b[i] != address(0), "zero address");
            for (uint256 j = i + 1; j < b.length; j++) require(b[i] != b[j], "listed twice");
        }
    }
}
