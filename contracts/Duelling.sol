// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

/// @title  Duelling — whether you are up for a fight, and nothing else.
/// @notice One bit per address. Not a token, no ids, no standard, no supply: the same shape
///         Inventory is, one bit wide. A thing being state rather than a token is not a
///         reason to keep it off a chain — it is most of the argument for putting it on one.
///
///         What this buys over a server-side setting is that it follows you. Say once that
///         you would rather be left alone and every town that reads this contract knows it,
///         including ones nobody has written yet. A setting held by a server is a setting you
///         make again on the next server, and the one time you forget is the time it matters.
///
/// @dev    Default is IN. `optedOut` rather than `fighting`, so an address that has never
///         touched this contract reads false and is therefore in — a town where you have to
///         opt in to being hit is a town where nobody is ever hit, and a fresh wallet should
///         not have to transact to join in.
///
///         The chain does not enforce anything here and cannot: whether a blow lands is
///         decided by two players' positions at one instant, which only the thing holding
///         both can judge. This is a statement of intent that servers honour, which is the
///         honest description of it. A server that ignored it would be a server nobody plays
///         on, and that is the only enforcement a preference can have.
///
///         Ownerless: no admin, no pause, no upgrade, no privileged address. Nobody can set
///         this for you and nobody can clear it.
contract Duelling {
    /// @notice True when `who` has asked to be left out of it.
    mapping(address => bool) public optedOut;

    event Changed(address indexed who, bool fighting);

    /// @notice Say whether you are up for a fight. Yours to set and nobody else's.
    ///
    /// @dev The parameter is `on` rather than `fighting` because a parameter of that name
    ///      shadows the view below it, which the compiler warns about and which would make
    ///      one of them mean the other inside this function.
    function setFighting(bool on) external {
        optedOut[msg.sender] = !on;
        emit Changed(msg.sender, on);
    }

    /// @notice Whether `who` is up for a fight. True for anyone who has never said otherwise.
    function fighting(address who) external view returns (bool) {
        return !optedOut[who];
    }

    /// @notice The same question for a crowd, so a server joining thirty players reads once
    ///         instead of thirty times.
    function fightingMany(address[] calldata who) external view returns (bool[] memory out) {
        out = new bool[](who.length);
        for (uint256 i = 0; i < who.length; i++) out[i] = !optedOut[who[i]];
    }
}
