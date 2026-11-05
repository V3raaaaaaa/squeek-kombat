// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {SqueekKombat} from "../src/SqueekKombat.sol";

/// forge script script/Deploy.s.sol --rpc-url sepolia --broadcast --verify
contract Deploy is Script {
    address constant CORE = 0xFD6C166D4B8E2962E65746a13e5a0797CD4dE0c4;
    address constant GENESIS = 0xC4C7982657f00509548F3a3a41db7FA439a6856B;
    address constant STAKING = 0x50fd1780526C3186A0c037c7622203bC4fb611ca;
    address constant SQK = 0xd78a3956cF63164d1Fa1C622ad3c66623162Fa1e;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        vm.startBroadcast(pk);
        SqueekKombat k = new SqueekKombat(CORE, GENESIS, STAKING, SQK);
        vm.stopBroadcast();
        console2.log("SqueekKombat deployed:", address(k));
        console2.log("core/genesis/staking/sqk:", CORE, GENESIS, STAKING);
    }
}
