// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal views of the live Squeekchain contracts on Sepolia that Squeek Kombat reads.
/// Addresses (Sepolia, core-sepolia-20261103):
///   SqueekCore   0xfd6c166d4b8e2962e65746a13e5a0797cd4de0c4
///   Genesis NFT  0xc4c7982657f00509548f3a3a41db7fa439a6856b
///   Staking      0x50fd1780526c3186a0c037c7622203bc4fb611ca
///   SQK          0xd78a3956cf63164d1fa1c622ad3c66623162fa1e

interface ISqueekCore {
    struct CoreState {
        uint64 settledThroughRound;
        uint64 cumulativeWork; // every accepted pass of the real wheel = 1 work unit
        uint96 cumulativeBlockUnits;
        uint64 blockHeight;
        uint96 blockProgress;
        uint32 workPerThousandBlocks; // current difficulty
        uint256 authorizationNonce;
        bool paused;
    }

    function state() external view returns (CoreState memory result);
}

interface IGenesisSqueeks {
    function ownerOf(uint256 tokenId) external view returns (address);
    function level(uint256 tokenId) external view returns (uint8);
}

interface ISqueekStaking {
    /// @notice Account that deposited `tokenId` of `collection` into staking (address(0) if none).
    function depositor(address collection, uint256 tokenId) external view returns (address);
}

interface IERC20Min {
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}
