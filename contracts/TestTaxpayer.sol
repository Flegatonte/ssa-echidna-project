// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Taxpayer.sol";

/*
 * external caller model (pre-fix): used to simulate an unauthorized contract
 * bypassing setTaxAllowance checks by spoofing isContract() == true.
 *
 * keep this only if you want a regression test for the access-control bug.
 */
contract AttackerTaxpayer {
    function isContract() external pure returns (bool) {
        return true;
    }

    function attackSetAllowance(address victim, uint x) external {
        Taxpayer(victim).setTaxAllowance(x);
    }
}

/*
 * minimal interface for calling into spouse/other taxpayer
 */
interface ITaxpayerView {
    function getIsMarried() external view returns (bool);
    function getSpouse() external view returns (address);
    function isContract() external view returns (bool);

    function getTaxAllowance() external view returns (uint);
    function getAge() external view returns (uint);
}

contract TestTaxpayer is Taxpayer {
    // ======== environment ========

    Taxpayer internal other;
    AttackerTaxpayer internal attacker;

    constructor() Taxpayer(address(0), address(0)) {
        other = new Taxpayer(address(0), address(0));
        attacker = new AttackerTaxpayer();
    }

    // ======== echidna-callable actions ========

    function act_marry_other() external {
        marry(address(other));
    }

    function act_divorce() external {
        divorce();
    }

    // pre-fix attack surface: should FAIL before access-control fix, PASS after
    function act_attack_set_allowance(uint x) external {
        attacker.attackSetAllowance(address(this), x);
    }

    // historical wrapper used in earlier traces/screenshots
    function marryOtherOneWay() public {
        marry(address(other));
    }

    // age progression: expose existing transitions (reachability helper)
    function act_age_self() external {
        haveBirthday();
    }

    function act_age_other() external {
        other.haveBirthday();
    }

    function act_age_self_n(uint n) external {
        uint k = n % 70; // cap: max 69 increments per call
        for (uint i = 0; i < k; i++) {
            haveBirthday();
        }
    }

    function act_age_other_n(uint n) external {
        uint k = n % 70;
        for (uint i = 0; i < k; i++) {
            other.haveBirthday();
        }
    }

    // reachability helper for the divorce/allowance bug:
    // marry -> transfer (positive) -> divorce
    function act_scenario_dirty_then_divorce(uint x) external {
        if (!getIsMarried()) {
            marry(address(other));
        }

        // force a strictly positive transfer
        uint a = getTaxAllowance();
        if (a > 0) {
            uint c = 1 + (x % a); // 1..a
            transferAllowance(c);
        }

        divorce();
    }

    // ======== stateful memory (marriage-related) ========

    // used by "no multiple marriages"
    address internal lastSpouse;

    // used by "spouse stable while married"
    address internal spouse_snapshot;
    bool internal snapshot_taken;

    // used by "pooling gated by marriage"
    uint internal single_allowance_snapshot;
    bool internal single_snapshot_taken;

    // ======== properties: marriage (Part 1) ========

    function echidna_marriage_is_symmetric() public view returns (bool) {
        if (!getIsMarried()) return true;

        address sp = getSpouse();
        if (sp == address(0)) return false;

        try ITaxpayerView(sp).getIsMarried() returns (bool spMarried) {
            if (!spMarried) return false;
        } catch {
            return false;
        }
        try ITaxpayerView(sp).getSpouse() returns (address spSpouse) {
            return spSpouse == address(this);
        } catch {
            return false;
        }
    }

    // global coherence across (this, other)
    function echidna_pair_marriage_state_coherent() public view returns (bool) {
        bool meM = getIsMarried();
        bool otM = other.getIsMarried();

        address meS = getSpouse();
        address otS = other.getSpouse();

        if (!meM && !otM) {
            return meS == address(0) && otS == address(0);
        }

        if (meM && otM) {
            return meS == address(other) && otS == address(this);
        }

        return false;
    }

    function echidna_no_multiple_marriages() public returns (bool) {
        if (getIsMarried()) {
            address sp = getSpouse();

            if (lastSpouse == address(0)) {
                lastSpouse = sp;
                return true;
            }
            return sp == lastSpouse;
        }

        lastSpouse = address(0);
        return true;
    }

    function echidna_spouse_stable_while_married() public returns (bool) {
        if (getIsMarried()) {
            address sp = getSpouse();

            if (!snapshot_taken) {
                spouse_snapshot = sp;
                snapshot_taken = true;
                return true;
            }

            return sp == spouse_snapshot;
        }

        snapshot_taken = false;
        spouse_snapshot = address(0);
        return true;
    }

    function echidna_divorce_resets_state() public view returns (bool) {
        if (!getIsMarried()) {
            return getSpouse() == address(0);
        }
        return true;
    }

    // ======== properties: pooling + access control (Part 2) ========

    /*
     * tripwire for the pre-fix access control bug:
     * if setTaxAllowance can be called by an unauthorized contract, allowance can become arbitrary.
     *
     * NOTE: Part-2-specific. Enable only if your Part 2 spec guarantees this bound.
     */
    // function echidna_allowance_is_bounded_part2() public view returns (bool) {
    //     return getTaxAllowance() <= DEFAULT_ALLOWANCE * 2;
    // }

    // validated property: pooling operations must have no effect while single
    function echidna_pooling_is_gated_by_marriage() public returns (bool) {
        if (!getIsMarried()) {
            uint a = getTaxAllowance();

            if (!single_snapshot_taken) {
                single_allowance_snapshot = a;
                single_snapshot_taken = true;
                return true;
            }

            return a == single_allowance_snapshot;
        }

        single_snapshot_taken = false;
        single_allowance_snapshot = 0;
        return true;
    }

    // ======== properties: age-based pooling (Part 3) ========

    function echidna_pooling_total_is_constant_based_on_age()
        public
        view
        returns (bool)
    {
        uint a = getTaxAllowance();
        uint base = (getAge() < 65) ? DEFAULT_ALLOWANCE : ALLOWANCE_OAP;

        if (!getIsMarried()) {
            return a <= base;
        }

        address sp = getSpouse();
        if (sp == address(0)) return false;

        ITaxpayerView t = ITaxpayerView(sp);
        uint b = t.getTaxAllowance();
        uint baseSpouse = (t.getAge() < 65) ? DEFAULT_ALLOWANCE : ALLOWANCE_OAP;

        if (a > type(uint).max - b) return false;
        return a + b == base + baseSpouse;
    }

    // ======== properties: divorce should restore bases (Part 3) ========

    function echidna_single_state_has_base_allowance_age_based()
        public
        view
        returns (bool)
    {
        if (getIsMarried()) return true;

        uint baseMe = (getAge() < 65) ? DEFAULT_ALLOWANCE : ALLOWANCE_OAP;
        return getTaxAllowance() == baseMe;
    }

    function echidna_other_single_state_has_base_allowance_age_based()
        public
        view
        returns (bool)
    {
        if (other.getIsMarried()) return true;

        uint baseOther = (other.getAge() < 65)
            ? DEFAULT_ALLOWANCE
            : ALLOWANCE_OAP;
        return other.getTaxAllowance() == baseOther;
    }
}
