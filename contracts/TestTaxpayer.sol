pragma solidity ^0.8.22;

import "./Taxpayer.sol";

// minimal interface: adapt if you used getters instead of public vars
interface ITaxpayerView {
    function getIsMarried() external view returns (bool);
    function getSpouse() external view returns (address);
    function isContract() external view returns (bool);
}

contract TestTaxpayer is Taxpayer {
    Taxpayer internal other; // "the spouse" we can point to

    // memory to detect the married -> single transition
    address internal lastSpouse;
    bool internal wasMarried;

    // memory to ensure the spouse doesn't change 
    address internal spouse_snapshot;
    bool internal snapshot_taken;

    constructor() Taxpayer(address(0), address(0)) {
        // create another taxpayer instance so echidna can produce asymmetry
        other = new Taxpayer(address(0), address(0));
    }

    // echidna property: marriage must be symmetric
    function echidna_marriage_is_symmetric() public view returns (bool) {
        // if i'm not married, invariant doesn't constrain me
        if (!getIsMarried()) {
            return true;
        }

        // if i'm married, spouse must exist
        if (getSpouse() == address(0)) {
            return false;
        }

        // spouse must behave like a taxpayer and agree i'm their spouse
        // if the call fails (spouse not a taxpayer contract), treat as violation
        try ITaxpayerView(spouse).getIsMarried() returns (bool spMarried) {
            if (!spMarried) return false;
        } catch {
            return false;
        }

        try ITaxpayerView(spouse).getSpouse() returns (address spSpouse) {
            return spSpouse == address(this);
        } catch {
            return false;
        }
    }

    function echidna_pair_marriage_state_coherent() public view returns (bool) {
        bool meM = getIsMarried();
        bool otM = other.getIsMarried();

        address meS = getSpouse();
        address otS = other.getSpouse();

        // case 1: both single -> both spouse pointers must be zero
        if (!meM && !otM) {
            return meS == address(0) && otS == address(0);
        }

        // case 2: both married -> must be married to each other
        if (meM && otM) {
            return meS == address(other) && otS == address(this);
        }

        // mixed states are invalid (one married, the other not)
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
            // while married, spouse must not change
            return sp == spouse_snapshot;
        } else {
            // if not married, reset snapshot
            snapshot_taken = false;
            spouse_snapshot = address(0);
            return true;
        }
    }

    function echidna_divorce_resets_state() public view returns (bool) {
        if (!getIsMarried()) {
            return getSpouse() == address(0);
        }
        return true;
    }

    // helper to let echidna create asymmetric states quickly 
    function marryOtherOneWay() public {
        marry(address(other)); // only sets THIS side, other stays single -> should violate invariant
    }
}
