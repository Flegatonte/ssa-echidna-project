// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Lottery.sol";

contract TestableLottery is Lottery {
    uint256 internal fakeNow;

    constructor(uint256 p) Lottery(p) {
        // fake time must start non-zero because startTime == 0 is the "closed / not started" sentinel
        fakeNow = 1;
    }

    function _now() internal view override returns (uint256) {
        // echidna can warp with deltas close to 2^256, which can push fakeNow near uint256.max.
        // in solidity 0.8+, arithmetic overflow reverts, so startLottery() could revert when doing:
        //   revealTime = startTime + period
        //   endTime    = revealTime + period
        //
        // this cannot happen with real block.timestamp, but it can happen with a fake clock.
        // so: when the lottery is closed, clamp the *observable* time to a safe max.
        //
        // when the lottery is running, we do not clamp, otherwise endLottery() could become
        // unreachable if endTime is close to uint256.max.
        if (startTime == 0) {
            uint256 maxStart = type(uint256).max - (2 * period);
            return fakeNow > maxStart ? maxStart : fakeNow;
        }

        return fakeNow;
    }

    /*
     * warp fake time forward
     * ----------------------
     * warp only updates the raw clock (fakeNow) using saturating arithmetic.
     * any "start safety" is handled in _now() when the lottery is closed.
     *
     * that is necessary because while running, we must allow time to reach endTime, otherwise endLottery() could be blocked.
     * moreover, after a close, we still want startLottery() to be safe even if no further warp() happens.
     */
    function warp(uint256 delta) external {
        // saturating add: fakeNow = min(fakeNow + delta, uint256.max)
        uint256 maxT = type(uint256).max;

        if (delta > maxT - fakeNow) {
            fakeNow = maxT;
        } else {
            fakeNow += delta;
        }
    }

    function getTime() external view returns (uint256) {
        return fakeNow;
    }
}
