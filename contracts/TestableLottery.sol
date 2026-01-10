// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Lottery.sol";

contract TestableLottery is Lottery {
    uint256 internal fakeNow;

    constructor(uint p) Lottery(p) {
        // must be non-zero, because startTime==0 is the "not started" sentinel
        fakeNow = 1;
    }

    function _now() internal view override returns (uint256) {
        return fakeNow;
    }

    function warp(uint256 delta) external {
        fakeNow += delta;
    }

    function getTime() external view returns (uint256) {
        return fakeNow;
    }
}
