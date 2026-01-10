pragma solidity ^0.8.22;

import "./Taxpayer.sol";

contract AttackerTaxpayer {
    // mimic Taxpayer(msg.sender).isContract() == true
    function isContract() external pure returns (bool) {
        return true;
    }
    function attackSetAllowance(address victim, uint x) external {
        Taxpayer(victim).setTaxAllowance(x);
    }
    function act_attack_set_allowance(uint x) external {
        uint y = 10001 + (x % 100000); // sempre > 10000
        attacker.attackSetAllowance(address(this), y);
    }
}

contract TestTaxpayer is Taxpayer {
    Taxpayer internal other;
    AttackerTaxpayer internal attacker;

    bool internal attack_succeeded;

    function act_attack_set_allowance(uint x) external {
        uint y = 10001 + (x % 100000);
        try attacker.attackSetAllowance(address(this), y) {
            attack_succeeded = true;
        } catch {
            // do nothing, but now we know it reverted
        }
    }

    function echidna_attack_never_succeeds() public view returns (bool) {
        return !attack_succeeded;
    }

    constructor() Taxpayer(address(0), address(0)) {
        other = new Taxpayer(address(0), address(0));
        attacker = new AttackerTaxpayer();
    }

    // allow echidna to make you married (to enable spouse-only scenarios later)
    function act_marry_other() external {
        marry(address(other));
    }

    // the actual attack surface we want echidna to try
    function act_attack_set_allowance(uint x) external {
        attacker.attackSetAllowance(address(this), x);
    }

    // property: allowance must stay within the only legitimate envelope in Part 2
    // (pooling can redistribute up to 2*DEFAULT_ALLOWANCE, but cannot mint arbitrary values)
    function echidna_allowance_is_bounded_part2() public view returns (bool) {
        return getTaxAllowance() <= DEFAULT_ALLOWANCE * 2;
    }
}
