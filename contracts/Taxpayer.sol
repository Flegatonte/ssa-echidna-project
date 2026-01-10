// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "Lottery.sol";

contract Taxpayer {
    uint age;

    bool isMarried;

    bool iscontract;

    /* Reference to spouse if person is married, address(0) otherwise */
    address spouse;

    address parent1;
    address parent2;

    /* Constant default income tax allowance */
    uint constant DEFAULT_ALLOWANCE = 5000;

    /* Constant income tax allowance for Older Taxpayers over 65 */
    uint constant ALLOWANCE_OAP = 7000;

    /* Income tax allowance */
    uint tax_allowance;

    uint income;

    uint256 rev;

    function getSpouse() public view returns (address) {
        return spouse;
    }
    function getIsMarried() public view returns (bool) {
        return isMarried;
    }
    function getAge() public view returns (uint) {
        return age;
    }

    //Parents are taxpayers
    constructor(address p1, address p2) {
        age = 0;
        isMarried = false;
        parent1 = p1;
        parent2 = p2;
        spouse = address(0);
        income = 0;
        tax_allowance = DEFAULT_ALLOWANCE;
        iscontract = true;
    }

    //We require new_spouse != address(0);
    function marry(address new_spouse) public {
        require(!isMarried, "already married");
        require(new_spouse != address(0), "invalid spouse");

        // we require new_spouse to be a contract first, then a Taxpayer
        require(new_spouse.code.length > 0, "spouse must be a contract");
        require(Taxpayer(new_spouse).isContract(), "spouse not taxpayer");

        // a TaxPayer cannot marry himself
        require(new_spouse != address(this), "cannot marry self");

        spouse = new_spouse;
        isMarried = true;
        Taxpayer(new_spouse)._marryBack(address(this));
    }

    function _marryBack(address new_spouse) external {
        require(Taxpayer(new_spouse).isContract(), "spouse not taxpayer");
        require(!isMarried, "already married");
        require(msg.sender == new_spouse, "only spouse can confirm");
        spouse = new_spouse;
        isMarried = true;
    }

    function divorce() public {
        if (spouse != address(0)) {
            Taxpayer(spouse)._divorceBack(address(this));
        }
        spouse = address(0);
        isMarried = false;
        // restore base allowance in the single state
        tax_allowance = _baseAllowance();
    }

    function _divorceBack(address ex) external {
        require(isMarried, "not married");
        require(msg.sender == ex, "only ex spouse can confirm");
        require(spouse == ex, "not your spouse");

        spouse = address(0);
        isMarried = false;

        // restore base allowance in the single state
        tax_allowance = _baseAllowance();
    }

    /* Transfer part of tax allowance to own spouse */
    function transferAllowance(uint change) public {
        require(isMarried, "not married");
        require(spouse != address(0), "no spouse");
        require(change <= tax_allowance, "too much");
        tax_allowance -= change;
        Taxpayer(spouse).setTaxAllowance(
            Taxpayer(spouse).getTaxAllowance() + change
        );
    }

    function haveBirthday() public {
        age++;
        // when entering OAP category, increase the couple's total by +2000
        if (age == 65) {
            tax_allowance += (ALLOWANCE_OAP - DEFAULT_ALLOWANCE); // +2000
        }
    }

    function setTaxAllowance(uint ta) public {
        require(
            Taxpayer(msg.sender).isContract() ||
                Lottery(msg.sender).isContract()
        );
        require(
            msg.sender == address(this) || msg.sender == spouse,
            "not authorized"
        );
        tax_allowance = ta;
    }
    function getTaxAllowance() public view returns (uint) {
        return tax_allowance;
    }

    function _baseAllowance() internal view returns (uint) {
        return (age < 65) ? DEFAULT_ALLOWANCE : ALLOWANCE_OAP;
    }

    function isContract() public view returns (bool) {
        return iscontract;
    }

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
