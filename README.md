# Squeek Kombat

**1v1 hamster duels on Squeekchain.** Your Genesis Squeek is your fighter. Squeektoshi's real wheel sets the arena. Every result is resolved on-chain on Sepolia and the browser only replays it.

- Live site: _(set after deploy)_
- Contract (Sepolia): _(set after deploy, Sourcify-verified)_
- Built on [Squeekchain](https://squeekchain.com) · Sepolia testnet · unaudited · tokens have no value

## How a duel works

1. **Fighters are NFTs.** `arenaFight(myToken, targetToken)` checks you control `myToken` — its ERC-721 owner, or, when it sits in Squeekchain Staking, the account that deposited it (`Staking.depositor`). So staked Squeeks keep earning and still fight.
2. **The wheel sets the arena.** The contract reads `SqueekCore.state()` and compares the settled work since it last looked against the current difficulty (`workPerThousandBlocks`):
   - **NAP** — no new work: calm round, no crits.
   - **JOG** — work below difficulty pace: crits on, special meter trickles.
   - **ZOOMIES** — work at/above pace: damage ×2, meter floods.
3. **Resolution is deterministic.** `KombatSim.fight(levelA, levelB, arena, seed)` is a pure, gas-bounded simulation (≤24 exchanges). Stats scale with the NFT's `level()`. The same algorithm is ported to `web/sim.js`, checked bit-for-bit against the Solidity output, so the canvas replays the exact on-chain fight and shows a "verified" badge.
4. **Ratings are per Squeek.** ELO-style (K=32), zero-sum, with wins/losses/draws, emitted as `RatingChanged` events. The leaderboard is built purely from events.

### Two modes

| Mode | Cost | Randomness | Flow |
|---|---|---|---|
| **Arena** | free (gas only) | `prevrandao` + previous blockhash — testnet-grade, documented | one transaction, resolved immediately |
| **Wager** | both sides escrow SQK | `blockhash(acceptedBlock)` — unknown when the target accepts, readable from the next block | `wagerChallenge` → `acceptWager` → `resolveWager` (anyone, within 256 blocks; past the window the duel is voided and both stakes refunded) |

The winner takes the whole pot; draws refund both. The challenger can withdraw an unaccepted wager at any time. No fee, no owner, no admin, no upgrade path, no pause.

## Contracts

```
src/SqueekKombat.sol      duels, wager escrow, ratings, wheel tracker
src/KombatSim.sol         pure fight simulator (library)
src/interfaces/ISqueek.sol minimal views of the live Squeekchain contracts
```

Live Squeekchain dependencies on Sepolia (`core-sepolia-20261103`):

| | address |
|---|---|
| SqueekCore | `0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4` |
| Genesis Squeeks (ERC-721, `level()`) | `0xC4C7982657f00509548F3a3a41db7FA439a6856B` |
| Staking (`depositor()`) | `0x50fd1780526C3186A0c037c7622203bC4fb611ca` |
| SQK | `0xd78a3956cF63164d1Fa1C622ad3c66623162Fa1e` |

## Tests

```
forge test --no-match-contract Fork         # 23 unit tests incl. fuzz (256 runs)
SEPOLIA_RPC_URL=... forge test --match-contract Fork   # 6 fork tests on the live deployment
forge test --match-contract SimVectors -vv | grep 'V,' > web/vectors.txt && node -e '...'  # JS parity (21/21)
```

Unit tests cover controller resolution (owner / depositor / unknown token), arena resolution and gas bound (<450k), wheel classification (nap/jog/zoomies) and tracker advance, the full wager lifecycle (post → accept → resolve → payout; withdraw; expired window refunds; controller change before accept), zero-sum ELO, and a fuzz over all levels/arenas/seeds proving termination and a valid winner. Fork tests run against the real SqueekCore, Genesis collection and Staking: a real holder arena-fights with a **staked** Squeek, a stranger cannot, an unknown token reverts.

## Frontend

`web/` is a static site (GitHub Pages-ready): ethers v6, wallet connect on Sepolia, read-only spectating without a wallet, live wheel from `api.squeekchain.com/v1/status` plus `currentArena()` from the contract, arena + wager flows, wager inbox, leaderboard and recent-fights feed from events, and a canvas replay driven by `sim.js`.

## Deploy & verify

```
export DEPLOYER_PK=0x...   SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
forge verify-contract <address> src/SqueekKombat.sol:SqueekKombat --chain sepolia --verifier sourcify \
  --constructor-args $(cast abi-encode "constructor(address,address,address,address)" 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4 0xC4C7982657f00509548F3a3a41db7FA439a6856B 0x50fd1780526C3186A0c037c7622203bC4fb611ca 0xd78a3956cF63164d1Fa1C622ad3c66623162Fa1e)
```
Then set `kombat` and `deployBlock` in `web/config.js`.

## Disclaimer

Testnet only. Unaudited. SQK and Squeeks on Sepolia have no value. Arena randomness is testnet-grade by design; nothing of value rides on it. Unofficial fan project; not affiliated with the Squeekchain team.
