// SPDX-License-Identifier: LicenseRef-PulseBlockz
pragma solidity ^0.8.20;

/// @title  Announcements — what the town's owner has to say, kept on chain.
/// @notice The one contract the owner has any say over, and the only say it gives them: posting an
///         announcement, and pinning one. Every player's own client reads the newest and shows it in
///         chat, with the pinned one, if there is one, above it; the Hall of Records reads the whole
///         list. Nothing is ever edited or removed -- a later announcement is how anything gets
///         corrected. Pinning only picks which one stays up.
/// @dev    The owner is whoever deploys it, fixed for good: no transfer, no admin, nothing else to
///         own. Announcements are plain text, up to a few paragraphs.
contract Announcements {
    address public immutable owner;

    struct Announcement {
        string text;
        uint64 at;     // block timestamp
    }

    Announcement[] private announcements;

    /// The pinned announcement's index plus one; 0 when nothing is pinned.
    uint256 private pinnedPlusOne;

    uint256 public constant MAX_LENGTH = 2000;

    event Announced(uint256 indexed index, string text, uint64 at);
    event Pinned(uint256 indexed index);
    event Unpinned(uint256 indexed index);

    constructor() {
        owner = msg.sender;
    }

    /// @notice Posts an announcement. The owner's alone.
    function announce(string calldata text) external {
        require(msg.sender == owner, "only the owner makes announcements");
        uint256 length = bytes(text).length;
        require(length > 0 && length <= MAX_LENGTH, "an announcement is 1 to 2000 bytes");
        announcements.push(Announcement({ text: text, at: uint64(block.timestamp) }));
        emit Announced(announcements.length - 1, text, uint64(block.timestamp));
    }

    /// @notice Keeps one announcement up above the newest, until another is pinned or it is unpinned.
    function pin(uint256 index) external {
        require(msg.sender == owner, "only the owner pins announcements");
        require(index < announcements.length, "there is no such announcement");
        pinnedPlusOne = index + 1;
        emit Pinned(index);
    }

    /// @notice Takes the pinned announcement down. It stays in the list like every other.
    function unpin() external {
        require(msg.sender == owner, "only the owner pins announcements");
        require(pinnedPlusOne != 0, "nothing is pinned");
        uint256 index = pinnedPlusOne - 1;
        pinnedPlusOne = 0;
        emit Unpinned(index);
    }

    /// @notice Whether one is pinned, and which.
    function pinned() external view returns (bool isPinned, uint256 index) {
        if (pinnedPlusOne == 0) return (false, 0);
        return (true, pinnedPlusOne - 1);
    }

    /// @notice How many there have ever been.
    function count() external view returns (uint256) {
        return announcements.length;
    }

    /// @notice One of them, oldest first from 0: its text and when it was posted.
    function announcement(uint256 index) external view returns (string memory text, uint64 at) {
        Announcement storage a = announcements[index];
        return (a.text, a.at);
    }
}
