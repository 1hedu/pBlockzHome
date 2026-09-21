// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

/// @notice A stand-in for atropaMath's Random(), for tests only: hands back whatever it was told to
///         next, then counts up from there.
contract MockRandom {
    uint64 public next;

    function setNext(uint64 value) external {
        next = value;
    }

    function Random() external returns (uint64 value) {
        value = next;
        unchecked { next += 1; }
    }
}
