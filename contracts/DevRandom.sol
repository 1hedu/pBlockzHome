// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

/// @title  DevRandom — a stand-in for atropaMath's `Random()` on a local chain, for playing the
///         Fishing contract before it is deployed anywhere real.
/// @notice Never deploy this anywhere that matters: anybody can queue the next number, which is
///         exactly what makes it useful for testing -- `queue` lets a tester land the one-in-5555
///         Everliving Fish on demand (scripts/dev-chain.js discover).
contract DevRandom {
    uint64 private counter;
    uint64[] private queued;

    /// The next numbers `Random()` hands out, in order, before it goes back to making them up.
    function queue(uint64[] calldata values) external {
        for (uint256 i = values.length; i > 0; i--) queued.push(values[i - 1]);
    }

    function Random() external returns (uint64) {
        if (queued.length > 0) {
            uint64 v = queued[queued.length - 1];
            queued.pop();
            return v;
        }
        unchecked { counter++; }
        return uint64(uint256(keccak256(abi.encode(blockhash(block.number - 1), block.prevrandao, block.timestamp, counter, msg.sender))));
    }
}
