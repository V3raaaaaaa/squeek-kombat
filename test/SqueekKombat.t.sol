// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekKombat} from "../src/SqueekKombat.sol";
import {KombatSim} from "../src/KombatSim.sol";
import {MockCore, MockGenesis, MockStaking, MockSQK} from "./mocks/Mocks.sol";

contract SqueekKombatTest is Test {
    MockCore core;
    MockGenesis gen;
    MockStaking stk;
    MockSQK sqk;
    SqueekKombat k;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA201);

    function setUp() public {
        core = new MockCore();
        gen = new MockGenesis();
        stk = new MockStaking();
        sqk = new MockSQK();
        k = new SqueekKombat(address(core), address(gen), address(stk), address(sqk));

        gen.mint(alice, 1, 2); // alice: L2
        gen.mint(bob, 2, 1); // bob: L1
        gen.mint(carol, 3, 5); // carol: L5
        gen.mint(address(stk), 4, 3); // token 4 staked, deposited by alice
        stk.deposit(address(gen), 4, alice);

        sqk.mint(alice, 1_000 ether);
        sqk.mint(bob, 1_000 ether);
        vm.prank(alice);
        sqk.approve(address(k), type(uint256).max);
        vm.prank(bob);
        sqk.approve(address(k), type(uint256).max);
        vm.roll(100);
    }

    // ---------------- controller / auth ----------------

    function test_controllerOf_owner() public view {
        assertEq(k.controllerOf(1), alice);
    }

    function test_controllerOf_stakedUsesDepositor() public view {
        assertEq(k.controllerOf(4), alice);
    }

    function test_controllerOf_unknownReverts() public {
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.UnknownSqueek.selector, 999));
        k.controllerOf(999);
    }

    function test_arena_requiresController() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.NotController.selector, 1));
        k.arenaFight(1, 2);
    }

    function test_arena_sameSqueekReverts() public {
        vm.prank(alice);
        vm.expectRevert(SqueekKombat.SameSqueek.selector);
        k.arenaFight(1, 1);
    }

    function test_arena_stakedSqueekCanFight() public {
        vm.prank(alice);
        uint256 id = k.arenaFight(4, 2);
        assertEq(id, 1);
        SqueekKombat.Duel memory d = k.duelOf(id);
        assertEq(uint8(d.status), uint8(SqueekKombat.Status.Resolved));
    }

    // ---------------- arena ----------------

    function test_arena_resolvesAndRecords() public {
        vm.prank(alice);
        k.arenaFight(1, 2);
        SqueekKombat.Record memory ra = k.recordOf(1);
        SqueekKombat.Record memory rb = k.recordOf(2);
        assertEq(ra.wins + ra.losses + ra.draws, 1);
        assertEq(rb.wins + rb.losses + rb.draws, 1);
        // ratings are zero-sum around 1000
        assertEq(int256(ra.rating) + int256(rb.rating), 2000);
    }

    function test_arena_higherLevelWinsMostly() public {
        uint256 carolWins;
        for (uint256 i = 0; i < 40; i++) {
            vm.roll(block.number + 1);
            vm.prevrandao(bytes32(uint256(keccak256(abi.encode(i)))));
            vm.prank(carol);
            k.arenaFight(3, 2); // L5 vs L1
        }
        SqueekKombat.Record memory rc = k.recordOf(3);
        carolWins = rc.wins;
        assertGt(carolWins, 30, "L5 should dominate L1");
    }

    function test_arena_isDeterministicForSeed() public view {
        (uint8 w1, uint16 a1, uint16 b1, uint8 e1) = k.simulate(2, 1, 1, bytes32(uint256(42)));
        (uint8 w2, uint16 a2, uint16 b2, uint8 e2) = k.simulate(2, 1, 1, bytes32(uint256(42)));
        assertEq(w1, w2);
        assertEq(a1, a2);
        assertEq(b1, b2);
        assertEq(e1, e2);
    }

    function test_arena_gasBounded() public {
        vm.prank(carol);
        uint256 g = gasleft();
        k.arenaFight(3, 1);
        uint256 used = g - gasleft();
        assertLt(used, 450_000, "arena fight must stay cheap");
    }

    // ---------------- wheel -> arena ----------------

    function test_wheel_napWhenNoNewWork() public view {
        (uint8 arena,,) = k.currentArena();
        assertEq(arena, KombatSim.ARENA_NAP);
    }

    function test_wheel_jogWhenSlowWork() public {
        vm.roll(block.number + 100);
        core.addWork(50); // 50 work / 100 blocks = 500 per 1000 < 9546
        (uint8 arena,,) = k.currentArena();
        assertEq(arena, KombatSim.ARENA_JOG);
    }

    function test_wheel_zoomiesWhenOutpacingDifficulty() public {
        vm.roll(block.number + 10);
        // pace is measured since the tracker's lastWorkBlock (constructor block), so push hard
        uint256 blocks = block.number - k.lastWorkBlock();
        core.addWork(uint64(blocks * 20)); // 20 work/block = 20000 per 1000 >= 9546
        (uint8 arena,,) = k.currentArena();
        assertEq(arena, KombatSim.ARENA_ZOOMIES);
    }

    function test_wheel_trackerAdvancesAfterFight() public {
        vm.roll(block.number + 10);
        core.addWork(200);
        vm.prank(alice);
        k.arenaFight(1, 2);
        assertEq(k.lastWork(), 3817 + 200);
        (uint8 arena,,) = k.currentArena();
        assertEq(arena, KombatSim.ARENA_NAP, "no new work since observation");
    }

    function test_sim_zoomiesDoublesDamage() public pure {
        // same seed, same fighters: zoomies must end faster or with lower remaining hp than nap
        KombatSim.Result memory nap = KombatSim.fight(3, 3, KombatSim.ARENA_NAP, bytes32(uint256(7)));
        KombatSim.Result memory zoom = KombatSim.fight(3, 3, KombatSim.ARENA_ZOOMIES, bytes32(uint256(7)));
        assertLe(zoom.exchanges, nap.exchanges);
    }

    // ---------------- wager ----------------

    function test_wager_fullFlow_winnerTakesPot() public {
        vm.prank(alice);
        uint256 id = k.wagerChallenge(1, 2, 100 ether);
        assertEq(sqk.balanceOf(address(k)), 100 ether);

        vm.prank(bob);
        k.acceptWager(id);
        assertEq(sqk.balanceOf(address(k)), 200 ether);

        vm.expectRevert(SqueekKombat.TooEarly.selector);
        k.resolveWager(id);

        vm.roll(block.number + 1);
        k.resolveWager(id);
        assertEq(sqk.balanceOf(address(k)), 0, "escrow fully paid out");
        SqueekKombat.Duel memory d = k.duelOf(id);
        assertEq(uint8(d.status), uint8(SqueekKombat.Status.Resolved));
        uint256 total = sqk.balanceOf(alice) + sqk.balanceOf(bob);
        assertEq(total, 2_000 ether, "no value created or lost");
    }

    function test_wager_zeroReverts() public {
        vm.prank(alice);
        vm.expectRevert(SqueekKombat.ZeroWager.selector);
        k.wagerChallenge(1, 2, 0);
    }

    function test_wager_onlyTargetControllerAccepts() public {
        vm.prank(alice);
        uint256 id = k.wagerChallenge(1, 2, 10 ether);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.NotController.selector, 2));
        k.acceptWager(id);
    }

    function test_wager_cancelRefundsChallenger() public {
        vm.prank(alice);
        uint256 id = k.wagerChallenge(1, 2, 10 ether);
        vm.prank(alice);
        k.cancelWager(id);
        assertEq(sqk.balanceOf(alice), 1_000 ether);
        vm.prank(bob);
        vm.expectRevert(SqueekKombat.BadStatus.selector);
        k.acceptWager(id);
    }

    function test_wager_expiredWindowRefundsBoth() public {
        vm.prank(alice);
        uint256 id = k.wagerChallenge(1, 2, 10 ether);
        vm.prank(bob);
        k.acceptWager(id);
        vm.roll(block.number + 257);
        k.resolveWager(id);
        assertEq(sqk.balanceOf(alice), 1_000 ether);
        assertEq(sqk.balanceOf(bob), 1_000 ether);
        SqueekKombat.Duel memory d = k.duelOf(id);
        assertEq(uint8(d.status), uint8(SqueekKombat.Status.Cancelled));
    }

    function test_wager_controllerCanChangeBeforeAccept() public {
        vm.prank(alice);
        uint256 id = k.wagerChallenge(1, 2, 10 ether);
        gen.transfer(2, carol); // bob sells his squeek
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(SqueekKombat.NotController.selector, 2));
        k.acceptWager(id);
    }

    // ---------------- elo ----------------

    function test_elo_zeroSumAndBounded() public {
        for (uint256 i = 0; i < 20; i++) {
            vm.roll(block.number + 1);
            vm.prank(carol);
            k.arenaFight(3, 2);
        }
        SqueekKombat.Record memory rc = k.recordOf(3);
        SqueekKombat.Record memory rb = k.recordOf(2);
        assertEq(int256(rc.rating) + int256(rb.rating), 2000);
        assertGt(rc.rating, 1000);
    }

    // ---------------- fuzz ----------------

    function testFuzz_sim_alwaysTerminatesWithValidWinner(uint8 la, uint8 lb, uint8 arena, bytes32 seed) public pure {
        arena = arena % 3;
        KombatSim.Result memory r = KombatSim.fight(la, lb, arena, seed);
        assertLe(r.exchanges, KombatSim.MAX_EXCHANGES);
        assertLe(r.winner, 2);
        if (r.winner == 0) assertGt(r.hpA, r.hpB);
        if (r.winner == 1) assertGt(r.hpB, r.hpA);
        if (r.winner == 2) assertEq(r.hpA, r.hpB);
    }
}
