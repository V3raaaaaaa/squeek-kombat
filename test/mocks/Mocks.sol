// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ISqueekCore} from "../../src/interfaces/ISqueek.sol";

contract MockCore {
    ISqueekCore.CoreState public s;

    constructor() {
        s.settledThroughRound = 280;
        s.cumulativeWork = 3817;
        s.blockHeight = 366;
        s.workPerThousandBlocks = 9546;
    }

    function state() external view returns (ISqueekCore.CoreState memory) {
        return s;
    }

    function addWork(uint64 w) external {
        s.cumulativeWork += w;
    }

    function setDifficulty(uint32 d) external {
        s.workPerThousandBlocks = d;
    }
}

contract MockGenesis {
    mapping(uint256 => address) public owners;
    mapping(uint256 => uint8) public levels;

    function mint(address to, uint256 id, uint8 lvl) external {
        owners[id] = to;
        levels[id] = lvl;
    }

    function ownerOf(uint256 id) external view returns (address o) {
        o = owners[id];
        require(o != address(0), "ERC721NonexistentToken");
    }

    function level(uint256 id) external view returns (uint8) {
        return levels[id];
    }

    function transfer(uint256 id, address to) external {
        owners[id] = to;
    }
}

contract MockStaking {
    mapping(address => mapping(uint256 => address)) public dep;

    function deposit(address col, uint256 id, address who) external {
        dep[col][id] = who;
    }

    function depositor(address col, uint256 id) external view returns (address) {
        return dep[col][id];
    }
}

contract MockSQK {
    string public constant symbol = "SQK";
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function approve(address sp, uint256 v) external returns (bool) {
        allowance[msg.sender][sp] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        require(balanceOf[msg.sender] >= v, "bal");
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        require(allowance[f][msg.sender] >= v, "allow");
        require(balanceOf[f] >= v, "bal");
        allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        return true;
    }
}
