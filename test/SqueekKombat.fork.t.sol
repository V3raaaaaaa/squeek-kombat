// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekKombat} from "../src/SqueekKombat.sol";
import {ISqueekCore, IGenesisSqueeks} from "../src/interfaces/ISqueek.sol";

/// @notice Runs against the live Squeekchain deployment on Sepolia.
///         forge test --match-contract Fork --fork-url $SEPOLIA_RPC_URL
contract SqueekKombatForkTest is Test {
    address constant CORE = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
    address constant GENESIS = 0xC4C7982657f00509548F3a3a41db7FA439a6856B;
    address constant STAKING = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;
    address constant SQK = 0xd78a3956cF63164d1Fa1C622ad3c66623162Fa1e;

    // a real holder with staked Squeeks (#855 L2 deposited)
    address constant HOLDER = 0x4d4ae1FD39Ac9b18610e87c82A1f48c96E42B979;
    uint256 constant STAKED_TOKEN = 855;
    uint256 constant ANY_TOKEN = 500; // known L2 in wallet custody

    SqueekKombat k;

    function setUp() public {
        string memory url = vm.envOr("SEPOLIA_RPC_URL", string("https://ethereum-sepolia-rpc.publicnode.com"));
        vm.createSelectFork(url);
        k = new SqueekKombat(CORE, GENESIS, STAKING, SQK);
    }

    function test_fork_readsRealCoreState() public view {
        ISqueekCore.CoreState memory s = ISqueekCore(CORE).state();
        assertGt(s.cumulativeWork, 0);
        assertGt(s.workPerThousandBlocks, 0);
        assertEq(k.lastWork(), s.cumulativeWork);
    }

    function test_fork_stakedSqueekControllerIsDepositor() public view {
        assertEq(IGenesisSqueeks(GENESIS).ownerOf(STAKED_TOKEN), STAKING);
        assertEq(k.controllerOf(STAKED_TOKEN), HOLDER);
        assertEq(IGenesisSqueeks(GENESIS).level(STAKED_TOKEN), 2);
    }

    function test_fork_currentArenaIsValid() public view {
        (uint8 arena, uint64 work, uint32 diff) = k.currentArena();
        assertLe(arena, 2);
        assertGt(work, 0);
        assertGt(diff, 0);
    }

    function test_fork_holderCanArenaFightWithStakedSqueek() public {
        vm.roll(block.number + 1);
        vm.prank(HOLDER);
        uint256 id = k.arenaFight(STAKED_TOKEN, ANY_TOKEN);
        SqueekKombat.Duel memory d = k.duelOf(id);
        assertEq(d.challenger, HOLDER);
        assertEq(uint8(d.status), uint8(SqueekKombat.Status.Resolved));
        SqueekKombat.Record memory r = k.recordOf(STAKED_TOKEN);
        assertEq(r.wins + r.losses + r.draws, 1);
    }

    function test_fork_strangerCannotFightWithHoldersSqueek() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.NotController.selector, STAKED_TOKEN));
        k.arenaFight(STAKED_TOKEN, ANY_TOKEN);
    }

    function test_fork_unknownTokenReverts() public {
        vm.prank(HOLDER);
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.UnknownSqueek.selector, 99_999_999));
        k.arenaFight(STAKED_TOKEN, 99_999_999);
    }
}
