// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Lottery.sol";

contract Taxpayer {
    // age in years (used by the lottery and allowance rules)
    uint age;

    // simple marital status model
    bool isMarried;

    // marker used by the assignment to distinguish contracts/EOAs
    bool iscontract;

    // spouse address if married, otherwise address(0)
    address spouse;

    // parents (also taxpayers), not really used in the lottery part
    address parent1;
    address parent2;

    // base allowance and pensioner allowance (>= 65)
    uint constant DEFAULT_ALLOWANCE = 5000;
    uint constant ALLOWANCE_OAP = 7000;

    // current allowance value (can change via marriage transfer or lottery win)
    uint tax_allowance;

    uint income;

    // last committed secret
    uint256 rev;

    // explicit access control: admin + registered lottery
    address admin;
    address lottery;

    function getSpouse() public view returns (address) {
        return spouse;
    }

    function getIsMarried() public view returns (bool) {
        return isMarried;
    }

    function getAge() public view returns (uint) {
        return age;
    }

    function getTaxAllowance() public view returns (uint) {
        return tax_allowance;
    }

    function getLottery() public view returns (address) {
        return lottery;
    }

    // parents are provided for completeness (they are also taxpayers in the assignment model)
    constructor(address p1, address p2) {
        admin = msg.sender;

        age = 0;
        isMarried = false;

        parent1 = p1;
        parent2 = p2;

        spouse = address(0);

        income = 0;
        tax_allowance = DEFAULT_ALLOWANCE;

        // this contract is meant to be treated as a "taxpayer contract"
        iscontract = true;

        // lottery is explicitly registered later by the test harness / deployer
        lottery = address(0);
    }

    // one-time wiring of the lottery contract address
    function setLottery(address lot) public {
        require(msg.sender == admin, "only admin");
        require(lottery == address(0), "lottery already set");
        require(lot != address(0), "invalid lottery");
        require(lot.code.length > 0, "lottery must be a contract");

        lottery = lot;
    }

    // marry another taxpayer contract
    function marry(address new_spouse) public {
        require(!isMarried, "already married");
        require(new_spouse != address(0), "invalid spouse");

        // spouse must be a contract and must implement the taxpayer interface
        require(new_spouse.code.length > 0, "spouse must be a contract");
        require(Taxpayer(new_spouse).isContract(), "spouse not taxpayer");

        require(new_spouse != address(this), "cannot marry self");

        spouse = new_spouse;
        isMarried = true;

        // symmetric update on the other side
        Taxpayer(new_spouse)._marryBack(address(this));
    }

    // confirmation call from the other spouse
    function _marryBack(address new_spouse) external {
        require(Taxpayer(new_spouse).isContract(), "spouse not taxpayer");
        require(!isMarried, "already married");
        require(msg.sender == new_spouse, "only spouse can confirm");

        spouse = new_spouse;
        isMarried = true;
    }

    // divorce resets spouse + marital status + allowance back to the age-based baseline
    function divorce() public {
        if (spouse != address(0)) {
            Taxpayer(spouse)._divorceBack(address(this));
        }

        spouse = address(0);
        isMarried = false;

        // restore baseline allowance in the single state
        tax_allowance = _baseAllowance();
    }

    function _divorceBack(address ex) external {
        require(isMarried, "not married");
        require(msg.sender == ex, "only ex spouse can confirm");
        require(spouse == ex, "not your spouse");

        spouse = address(0);
        isMarried = false;

        // restore baseline allowance in the single state
        tax_allowance = _baseAllowance();
    }

    // transfer part of your allowance to your spouse
    function transferAllowance(uint change) public {
        require(isMarried, "not married");
        require(spouse != address(0), "no spouse");
        require(change <= tax_allowance, "too much");

        tax_allowance -= change;

        // msg.sender at the receiver will be this contract, which is spouse for the receiver
        Taxpayer(spouse).setTaxAllowance(
            Taxpayer(spouse).getTaxAllowance() + change
        );
    }

    function haveBirthday() public {
        age++;

        // hitting 65 bumps your own baseline by +2000 (5000 -> 7000)
        if (age == 65) {
            tax_allowance += (ALLOWANCE_OAP - DEFAULT_ALLOWANCE);
        }
    }

    // setter used by:
    // - spouse/self (allowance transfer logic)
    // - the registered lottery contract (winner gets the oap allowance = 7000)
    function setTaxAllowance(uint ta) public {
        // explicit access control
        require(
            msg.sender == address(this) ||
                msg.sender == spouse ||
                (lottery != address(0) && msg.sender == lottery),
            "not authorized"
        );

        tax_allowance = ta;
    }

    function _baseAllowance() internal view returns (uint) {
        return (age < 65) ? DEFAULT_ALLOWANCE : ALLOWANCE_OAP;
    }

    function isContract() public view returns (bool) {
        return iscontract;
    }

    // convenience helpers used in some versions of the assignment (not in the echidna harness)
    function joinLottery(address lot, uint256 r) public {
        Lottery l = Lottery(lot);
        l.commit(keccak256(abi.encode(r)));
        rev = r;
    }

    function revealLottery(address lot, uint256 r) public {
        Lottery l = Lottery(lot);
        l.reveal(r);
        rev = 0;
    }
}
