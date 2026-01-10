// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Lottery.sol";

contract TestableLottery is Lottery {
    uint256 internal fakeNow;

    constructor(uint256 p) Lottery(p) {
        // must be non-zero, because startTime==0 is the "not started" sentinel
        fakeNow = 1;
    }

    function _now() internal view override returns (uint256) {
        // when the lottery is closed (startTime == 0), we clamp the observable time
        // to a "start-safe" maximum so startLottery() cannot overflow when computing:
        //   revealTime = startTime + period
        //   endTime    = revealTime + period
        //
        // this avoids artificial reverts caused by echidna warping fake time near uint256.max.
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
     * we keep warp simple: it only advances the raw clock (fakeNow) with saturating arithmetic.
     * any "start-safety" is enforced by _now() when the lottery is closed, not by warp().
     *
     * rationale:
     * - we must allow time to reach endTime while running, otherwise endLottery() can be blocked.
     * - we must prevent overflow in startLottery() after a close, even if no further warp() occurs.
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
