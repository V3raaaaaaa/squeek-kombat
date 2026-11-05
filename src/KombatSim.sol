// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title KombatSim — deterministic hamster duel simulator
/// @notice Pure, gas-bounded fight resolution. The exact same algorithm is ported to JavaScript
///         in the frontend, so the canvas replays the on-chain result move for move from the seed.
library KombatSim {
    uint8 internal constant ARENA_NAP = 0; // wheel idle: no crits
    uint8 internal constant ARENA_JOG = 1; // wheel moving: crits on, meter trickles
    uint8 internal constant ARENA_ZOOMIES = 2; // wheel outpacing difficulty: damage x2, meter floods

    uint8 internal constant MAX_EXCHANGES = 24;

    struct Stats {
        uint16 hp;
        uint8 light;
        uint8 heavy;
        uint8 special;
    }

    struct Result {
        uint8 winner; // 0 = A, 1 = B, 2 = draw
        uint16 hpA;
        uint16 hpB;
        uint8 exchanges;
    }

    function statsFor(uint8 level) internal pure returns (Stats memory s) {
        uint8 l = level == 0 ? 1 : (level > 10 ? 10 : level);
        s.hp = uint16(100 + uint16(l - 1) * 35);
        s.light = uint8(6 + 2 * l);
        s.heavy = uint8(13 + 3 * l);
        s.special = uint8(28 + 6 * l);
    }

    /// @dev rng stream: roll(seed, i) in [0, 1000)
    function roll(bytes32 seed, uint256 i) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, i))) % 1000;
    }

    /// @notice Resolve a duel. Deterministic in (levelA, levelB, arena, seed).
    function fight(uint8 levelA, uint8 levelB, uint8 arena, bytes32 seed)
        internal
        pure
        returns (Result memory r)
    {
        Stats memory a = statsFor(levelA);
        Stats memory b = statsFor(levelB);
        int32 hpA = int32(uint32(a.hp));
        int32 hpB = int32(uint32(b.hp));
        uint16 mA;
        uint16 mB;
        uint256 n; // rng cursor

        uint16 trickle = arena == ARENA_ZOOMIES ? 22 : (arena == ARENA_JOG ? 7 : 0);
        uint8 dmgMul = arena == ARENA_ZOOMIES ? 2 : 1;

        uint8 ex;
        for (ex = 0; ex < MAX_EXCHANGES; ex++) {
            // meter trickle from the live wheel
            mA = _cap(mA + trickle);
            mB = _cap(mB + trickle);

            // each side picks an action: 0 light, 1 heavy, 2 block, 3 special (if meter full)
            uint8 actA = _pick(seed, n++, mA);
            uint8 actB = _pick(seed, n++, mB);

            // A strikes B
            (int32 dB, uint16 gA, uint16 gB) = _strike(a, actA, actB, arena, dmgMul, seed, n);
            n += 2;
            // B strikes A
            (int32 dA, uint16 gB2, uint16 gA2) = _strike(b, actB, actA, arena, dmgMul, seed, n);
            n += 2;

            if (actA == 3) mA = 0;
            if (actB == 3) mB = 0;
            mA = _cap(mA + gA + gA2);
            mB = _cap(mB + gB + gB2);
            hpB -= dB;
            hpA -= dA;
            if (hpA <= 0 || hpB <= 0) {
                ex++;
                break;
            }
        }

        r.exchanges = ex;
        r.hpA = hpA < 0 ? 0 : uint16(uint32(hpA));
        r.hpB = hpB < 0 ? 0 : uint16(uint32(hpB));
        if (r.hpA == r.hpB) r.winner = 2;
        else r.winner = r.hpA > r.hpB ? 0 : 1;
    }

    function _cap(uint256 v) private pure returns (uint16) {
        return v > 100 ? 100 : uint16(v);
    }

    function _pick(bytes32 seed, uint256 i, uint16 meter) private pure returns (uint8) {
        uint256 x = roll(seed, i);
        if (meter >= 100 && x < 600) return 3; // special, 60% when charged
        if (x < 550) return 0; // light
        if (x < 850) return 1; // heavy
        return 2; // block
    }

    /// @return dmg to defender, meter gained by attacker, meter gained by defender
    function _strike(
        Stats memory atk,
        uint8 action,
        uint8 defAction,
        uint8 arena,
        uint8 dmgMul,
        bytes32 seed,
        uint256 n
    ) private pure returns (int32 dmg, uint16 gAtk, uint16 gDef) {
        if (action == 2) return (0, 0, 0); // blocking, no strike
        uint256 hitRoll = roll(seed, n);
        uint256 hitChance = action == 0 ? 780 : (action == 1 ? 640 : 900);
        if (hitRoll >= hitChance) return (0, 2, 0); // whiff, tiny meter for trying

        uint256 base = action == 0 ? atk.light : (action == 1 ? atk.heavy : atk.special);
        uint256 d = base * dmgMul;
        if (arena != ARENA_NAP && roll(seed, n + 1) < 150) d = (d * 3) / 2; // crit only when the wheel moves
        bool blocked = defAction == 2;
        if (blocked) d = (d + 3) / 4; // block absorbs 75%
        dmg = int32(uint32(d));
        gAtk = blocked ? 4 : (action == 0 ? 12 : (action == 1 ? 18 : 0));
        gDef = 6;
    }
}
