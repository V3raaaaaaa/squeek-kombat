// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {SqueekKombat} from "../src/SqueekKombat.sol";
import {MockCore, MockGenesis, MockStaking, MockSQK} from "./mocks/Mocks.sol";

/// @notice Dumps reference vectors through the external `simulate()` so the JavaScript port
///         can be checked bit-for-bit.  forge test --match-contract SimVectors -vv | grep 'V,'
contract SimVectorsTest is Test {
    SqueekKombat k;

    function setUp() public {
        k = new SqueekKombat(address(new MockCore()), address(new MockGenesis()), address(new MockStaking()), address(new MockSQK()));
    }

    function _one(uint8 la, uint8 lb, uint8 arena, uint256 i) internal view {
        bytes32 seed = keccak256(abi.encodePacked("squeek", i, arena));
        (uint8 w, uint16 ha, uint16 hb, uint8 ex) = k.simulate(la, lb, arena, seed);
        console2.log(
            string.concat(
                "V,", vm.toString(uint256(la)), ",", vm.toString(uint256(lb)), ",", vm.toString(uint256(arena)), ",",
                vm.toString(seed), ",", vm.toString(uint256(w)), ",", vm.toString(uint256(ha)), ",",
                vm.toString(uint256(hb)), ",", vm.toString(uint256(ex))
            )
        );
    }

    function test_dumpVectors() public view {
        uint8[21] memory la = [1, 1, 1, 2, 2, 2, 5, 5, 5, 10, 10, 10, 3, 3, 3, 7, 7, 7, 1, 10, 4];
        uint8[21] memory lb = [1, 1, 1, 1, 1, 1, 2, 2, 2, 10, 10, 10, 9, 9, 9, 4, 4, 4, 10, 1, 4];
        uint8[21] memory ar = [0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 0, 1, 2, 2, 2, 1];
        for (uint256 i = 0; i < 21; i++) {
            _one(la[i], lb[i], ar[i], i / 3);
        }
    }
}
