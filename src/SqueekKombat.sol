// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISqueekCore, IGenesisSqueeks, ISqueekStaking, IERC20Min} from "./interfaces/ISqueek.sol";
import {KombatSim} from "./KombatSim.sol";

/// @title Squeek Kombat — 1v1 hamster duels on Squeekchain (Sepolia)
/// @notice Your Genesis Squeek is your fighter. Duels resolve on-chain from the fighters' NFT levels,
///         the live state of Squeektoshi's real wheel (read from SqueekCore) and a block seed.
///         Two modes:
///           • Arena  — free ranked duel against any Squeek, resolved in one transaction.
///           • Wager  — both sides escrow SQK; resolved from a committed future blockhash.
///         No owner, no admin keys, no upgrade path. Testnet only.
contract SqueekKombat {
    using KombatSim for *;

    // ---------- immutable wiring ----------
    ISqueekCore public immutable core;
    IGenesisSqueeks public immutable squeeks;
    ISqueekStaking public immutable staking;
    IERC20Min public immutable sqk;

    // ---------- constants ----------
    uint256 public constant WAGER_RESOLVE_WINDOW = 256; // blocks after accept while blockhash is available
    int32 public constant START_RATING = 1000;
    int32 public constant ELO_K = 32;

    // ---------- records ----------
    struct Record {
        uint32 wins;
        uint32 losses;
        uint32 draws;
        int32 rating;
    }

    mapping(uint256 tokenId => Record) private _records;

    enum Status {
        None,
        Open, // wager posted, waiting for the target to accept
        Ready, // accepted, waiting one block to resolve
        Resolved,
        Cancelled
    }

    struct Duel {
        uint256 challengerToken;
        uint256 targetToken;
        address challenger;
        address target; // set on accept (wager) — address(0) in arena mode
        uint96 wager; // per side, in SQK base units
        uint64 createdBlock;
        uint64 acceptedBlock;
        Status status;
    }

    uint256 public duelCount;
    mapping(uint256 duelId => Duel) private _duels;

    // wheel tracker: last observed settled work, to derive nap / jog / zoomies on-chain
    uint64 public lastWork;
    uint64 public lastWorkBlock;

    bool private _lock;

    // ---------- events ----------
    event ArenaFight(
        uint256 indexed duelId,
        uint256 indexed challengerToken,
        uint256 indexed targetToken,
        address challenger,
        uint8 arena,
        bytes32 seed,
        uint8 winner,
        uint16 hpA,
        uint16 hpB,
        uint8 exchanges
    );
    event WagerCreated(
        uint256 indexed duelId, uint256 indexed challengerToken, uint256 indexed targetToken, address challenger, uint96 wager
    );
    event WagerAccepted(uint256 indexed duelId, address target, uint64 acceptedBlock);
    event WagerResolved(
        uint256 indexed duelId, uint8 arena, bytes32 seed, uint8 winner, uint16 hpA, uint16 hpB, uint8 exchanges, uint256 payout
    );
    event WagerCancelled(uint256 indexed duelId, string reason);
    event RatingChanged(uint256 indexed tokenId, int32 rating, uint32 wins, uint32 losses, uint32 draws);
    event WheelObserved(uint64 work, uint64 blockNumber, uint8 arena);

    // ---------- errors ----------
    error NotController(uint256 tokenId);
    error SameSqueek();
    error UnknownSqueek(uint256 tokenId);
    error BadStatus();
    error TooEarly();
    error ZeroWager();
    error Reentrancy();
    error TransferFailed();

    constructor(address core_, address squeeks_, address staking_, address sqk_) {
        core = ISqueekCore(core_);
        squeeks = IGenesisSqueeks(squeeks_);
        staking = ISqueekStaking(staking_);
        sqk = IERC20Min(sqk_);
        ISqueekCore.CoreState memory s = core.state();
        lastWork = s.cumulativeWork;
        lastWorkBlock = uint64(block.number);
    }

    modifier nonReentrant() {
        if (_lock) revert Reentrancy();
        _lock = true;
        _;
        _lock = false;
    }

    // ================================================================
    //                              VIEWS
    // ================================================================

    /// @notice Who may fight with `tokenId`: its owner, or its depositor when it sits in Staking.
    function controllerOf(uint256 tokenId) public view returns (address) {
        address owner;
        try squeeks.ownerOf(tokenId) returns (address o) {
            owner = o;
        } catch {
            revert UnknownSqueek(tokenId);
        }
        if (owner == address(staking)) {
            address d = staking.depositor(address(squeeks), tokenId);
            return d == address(0) ? owner : d;
        }
        return owner;
    }

    function recordOf(uint256 tokenId) external view returns (Record memory r) {
        r = _records[tokenId];
        if (r.rating == 0) r.rating = START_RATING;
    }

    function duelOf(uint256 duelId) external view returns (Duel memory) {
        return _duels[duelId];
    }

    /// @notice Arena the wheel would set right now, without mutating the tracker.
    ///         nap: no settled work since last look · jog: work below difficulty pace · zoomies: at/above pace.
    function currentArena() public view returns (uint8 arena, uint64 work, uint32 difficulty) {
        ISqueekCore.CoreState memory s = core.state();
        work = s.cumulativeWork;
        difficulty = s.workPerThousandBlocks;
        arena = _arenaFrom(work, difficulty);
    }

    /// @notice Pure simulation exposed for verification and frontend replay.
    function simulate(uint8 levelA, uint8 levelB, uint8 arena, bytes32 seed)
        external
        pure
        returns (uint8 winner, uint16 hpA, uint16 hpB, uint8 exchanges)
    {
        KombatSim.Result memory r = KombatSim.fight(levelA, levelB, arena, seed);
        return (r.winner, r.hpA, r.hpB, r.exchanges);
    }

    // ================================================================
    //                              ARENA
    // ================================================================

    /// @notice Free ranked duel, resolved now. Seed mixes prevrandao and the previous blockhash —
    ///         testnet-grade randomness, documented as such. Nothing of value rides on it.
    function arenaFight(uint256 myToken, uint256 targetToken) external nonReentrant returns (uint256 duelId) {
        if (myToken == targetToken) revert SameSqueek();
        if (controllerOf(myToken) != msg.sender) revert NotController(myToken);
        controllerOf(targetToken); // reverts UnknownSqueek if it does not exist

        uint8 arena = _observeWheel();
        duelId = ++duelCount;
        bytes32 seed = keccak256(abi.encodePacked(block.prevrandao, blockhash(block.number - 1), duelId, msg.sender));

        KombatSim.Result memory r =
            KombatSim.fight(squeeks.level(myToken), squeeks.level(targetToken), arena, seed);

        _duels[duelId] = Duel({
            challengerToken: myToken,
            targetToken: targetToken,
            challenger: msg.sender,
            target: address(0),
            wager: 0,
            createdBlock: uint64(block.number),
            acceptedBlock: uint64(block.number),
            status: Status.Resolved
        });

        _settleRatings(myToken, targetToken, r.winner);
        emit ArenaFight(duelId, myToken, targetToken, msg.sender, arena, seed, r.winner, r.hpA, r.hpB, r.exchanges);
    }

    // ================================================================
    //                              WAGER
    // ================================================================

    /// @notice Post a wager duel. Escrows `amount` SQK (caller must approve first).
    function wagerChallenge(uint256 myToken, uint256 targetToken, uint96 amount)
        external
        nonReentrant
        returns (uint256 duelId)
    {
        if (amount == 0) revert ZeroWager();
        if (myToken == targetToken) revert SameSqueek();
        if (controllerOf(myToken) != msg.sender) revert NotController(myToken);
        controllerOf(targetToken);

        duelId = ++duelCount;
        _duels[duelId] = Duel({
            challengerToken: myToken,
            targetToken: targetToken,
            challenger: msg.sender,
            target: address(0),
            wager: amount,
            createdBlock: uint64(block.number),
            acceptedBlock: 0,
            status: Status.Open
        });
        _pull(msg.sender, amount);
        emit WagerCreated(duelId, myToken, targetToken, msg.sender, amount);
    }

    /// @notice Target's controller matches the stake. The duel resolves from blockhash(acceptedBlock),
    ///         which is unknown now and readable from the next block.
    function acceptWager(uint256 duelId) external nonReentrant {
        Duel storage d = _duels[duelId];
        if (d.status != Status.Open) revert BadStatus();
        if (controllerOf(d.targetToken) != msg.sender) revert NotController(d.targetToken);
        d.target = msg.sender;
        d.acceptedBlock = uint64(block.number);
        d.status = Status.Ready;
        _pull(msg.sender, d.wager);
        emit WagerAccepted(duelId, msg.sender, d.acceptedBlock);
    }

    /// @notice Anyone may resolve once a block has passed. Past the 256-block window the hash is
    ///         gone, so the duel is voided and both stakes refunded.
    function resolveWager(uint256 duelId) external nonReentrant {
        Duel storage d = _duels[duelId];
        if (d.status != Status.Ready) revert BadStatus();
        if (block.number <= d.acceptedBlock) revert TooEarly();

        if (block.number > d.acceptedBlock + WAGER_RESOLVE_WINDOW) {
            d.status = Status.Cancelled;
            _push(d.challenger, d.wager);
            _push(d.target, d.wager);
            emit WagerCancelled(duelId, "resolve window expired");
            return;
        }

        uint8 arena = _observeWheel();
        bytes32 seed = keccak256(abi.encodePacked(blockhash(d.acceptedBlock), duelId));
        KombatSim.Result memory r =
            KombatSim.fight(squeeks.level(d.challengerToken), squeeks.level(d.targetToken), arena, seed);

        d.status = Status.Resolved;
        uint256 pot = uint256(d.wager) * 2;
        uint256 payout;
        if (r.winner == 0) {
            payout = pot;
            _push(d.challenger, pot);
        } else if (r.winner == 1) {
            payout = pot;
            _push(d.target, pot);
        } else {
            _push(d.challenger, d.wager);
            _push(d.target, d.wager);
        }
        _settleRatings(d.challengerToken, d.targetToken, r.winner);
        emit WagerResolved(duelId, arena, seed, r.winner, r.hpA, r.hpB, r.exchanges, payout);
    }

    /// @notice Challenger withdraws an unaccepted wager at any time.
    function cancelWager(uint256 duelId) external nonReentrant {
        Duel storage d = _duels[duelId];
        if (d.status != Status.Open) revert BadStatus();
        if (d.challenger != msg.sender) revert NotController(d.challengerToken);
        d.status = Status.Cancelled;
        _push(msg.sender, d.wager);
        emit WagerCancelled(duelId, "withdrawn by challenger");
    }

    // ================================================================
    //                            INTERNALS
    // ================================================================

    /// @dev Reads the real wheel from SqueekCore and classifies it against the pace difficulty asks for.
    function _observeWheel() private returns (uint8 arena) {
        ISqueekCore.CoreState memory s = core.state();
        arena = _arenaFrom(s.cumulativeWork, s.workPerThousandBlocks);
        lastWork = s.cumulativeWork;
        lastWorkBlock = uint64(block.number);
        emit WheelObserved(s.cumulativeWork, uint64(block.number), arena);
    }

    function _arenaFrom(uint64 work, uint32 difficulty) private view returns (uint8) {
        if (work <= lastWork) return KombatSim.ARENA_NAP;
        uint256 blocks = block.number > lastWorkBlock ? block.number - lastWorkBlock : 1;
        // observed work per 1000 blocks vs what difficulty expects per 1000 Squeek blocks
        uint256 pace = (uint256(work - lastWork) * 1000) / blocks;
        return pace >= difficulty ? KombatSim.ARENA_ZOOMIES : KombatSim.ARENA_JOG;
    }

    function _settleRatings(uint256 a, uint256 b, uint8 winner) private {
        Record storage ra = _records[a];
        Record storage rb = _records[b];
        if (ra.rating == 0) ra.rating = START_RATING;
        if (rb.rating == 0) rb.rating = START_RATING;

        // expected score for A, in thousandths, linear approximation of the logistic curve
        int32 diff = rb.rating - ra.rating; // positive when B is stronger
        if (diff > 400) diff = 400;
        if (diff < -400) diff = -400;
        int32 expA = 500 - diff; // 100..900 ≈ 1 / (1 + 10^(diff/400)) scaled
        if (expA < 100) expA = 100;
        if (expA > 900) expA = 900;

        int32 scoreA = winner == 0 ? int32(1000) : (winner == 1 ? int32(0) : int32(500));
        int32 delta = (ELO_K * (scoreA - expA)) / 1000;
        ra.rating += delta;
        rb.rating -= delta;

        if (winner == 0) {
            ra.wins++;
            rb.losses++;
        } else if (winner == 1) {
            rb.wins++;
            ra.losses++;
        } else {
            ra.draws++;
            rb.draws++;
        }
        emit RatingChanged(a, ra.rating, ra.wins, ra.losses, ra.draws);
        emit RatingChanged(b, rb.rating, rb.wins, rb.losses, rb.draws);
    }

    function _pull(address from, uint256 amount) private {
        if (!sqk.transferFrom(from, address(this), amount)) revert TransferFailed();
    }

    function _push(address to, uint256 amount) private {
        if (!sqk.transfer(to, amount)) revert TransferFailed();
    }
}
