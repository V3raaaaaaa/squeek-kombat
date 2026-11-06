#!/usr/bin/env bash
# One-shot: deploy SqueekKombat to Sepolia, verify on Sourcify, print address + block.
# Usage: KEYFILE=~/squeekchain/.kombat_deployer ./script/deploy_sepolia.sh
set -euo pipefail
cd "$(dirname "$0")/.."

RPC="${SEPOLIA_RPC_URL:-https://ethereum-sepolia-rpc.publicnode.com}"
KEYFILE="${KEYFILE:-$HOME/squeekchain/.kombat_deployer}"
K=$(tr -d '[:space:]' < "$KEYFILE"); case "$K" in 0x*) ;; *) K="0x$K";; esac
export DEPLOYER_PK="$K" SEPOLIA_RPC_URL="$RPC"

CORE=0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4
GENESIS=0xC4C7982657f00509548F3a3a41db7FA439a6856B
STAKING=0x50fd1780526C3186A0c037c7622203bC4fb611ca
SQK=0xd78a3956cF63164d1Fa1C622ad3c66623162Fa1e

DEPLOYER=$(cast wallet address --private-key "$K")
echo "== deployer $DEPLOYER balance $(cast balance "$DEPLOYER" --rpc-url "$RPC" --ether) ETH"

# Sepolia runs Glamsterdam: state-creation repricing (EIP-8037) makes code deposit ~1.5k gas/byte,
# so this 8.6 KB contract needs ~13.7M gas. Foundry's local EVM still estimates ~2.5M and the
# transaction would run out of gas, so ask the node and send with an explicit limit (< 16.7M tx cap).
forge build --silent
INIT=$(forge inspect src/SqueekKombat.sol:SqueekKombat bytecode)$(cast abi-encode "constructor(address,address,address,address)" $CORE $GENESIS $STAKING $SQK | cut -c3-)
EST=$(cast estimate --rpc-url "$RPC" --from "$DEPLOYER" --create "$INIT")
GAS=$(( EST + EST / 10 ))
echo "== node estimate $EST gas, sending with limit $GAS"
TXH=$(cast send --rpc-url "$RPC" --private-key "$K" --gas-limit "$GAS" --create "$INIT" --json | python3 -c "import json,sys;r=json.load(sys.stdin);assert r['status'] in ('0x1',1,'1'),r;print(r['transactionHash'])")
ADDR=$(cast receipt "$TXH" contractAddress --rpc-url "$RPC")
BLK=$(cast receipt "$TXH" blockNumber --rpc-url "$RPC")
echo "== SqueekKombat $ADDR  tx $TXH  block $BLK  gasUsed $(cast receipt "$TXH" gasUsed --rpc-url "$RPC")"

ARGS=$(cast abi-encode "constructor(address,address,address,address)" $CORE $GENESIS $STAKING $SQK)
echo "== verifying on Sourcify"
forge verify-contract "$ADDR" src/SqueekKombat.sol:SqueekKombat --chain sepolia --verifier sourcify --constructor-args "$ARGS" 2>&1 | tail -5 || true

printf '%s\n%s\n%s\n' "$ADDR" "$TXH" "$BLK" > broadcast/sepolia_deploy.txt
echo "== done: $ADDR @ $BLK"
