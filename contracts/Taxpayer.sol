// SPDX-License-Identifier: UNLICENSED 
pragma solidity ^0.8.22;

import "Lottery.sol";

contract Taxpayer {

 uint age; 

 bool isMarried; 

 bool iscontract;

 /* Reference to spouse if person is married, address(0) otherwise */
 address spouse; 


address  parent1; 
address  parent2; 

 /* Constant default income tax allowance */
 uint constant  DEFAULT_ALLOWANCE = 5000;

 /* Constant income tax allowance for Older Taxpayers over 65 */
  uint constant ALLOWANCE_OAP = 7000;

 /* Income tax allowance */
 uint tax_allowance; 

 uint income; 

uint256 rev;

function getSpouse() public view returns (address) { return spouse; }
function getIsMarried() public view returns (bool) { return isMarried; }

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
 }

 function _divorceBack(address ex) external {
    require(isMarried, "not married");
    require(msg.sender == ex, "only ex spouse can confirm");
    require(spouse == ex, "not your spouse");

    spouse = address(0);
    isMarried = false;
}

 /* Transfer part of tax allowance to own spouse */
 function transferAllowance(uint change) public {
  tax_allowance = tax_allowance - change;
  Taxpayer sp = Taxpayer(address(spouse));
  sp.setTaxAllowance(sp.getTaxAllowance()+change);
 }

 function haveBirthday() public {
  age++;
 }
 
  function setTaxAllowance(uint ta) public {
    require(Taxpayer(msg.sender).isContract() || Lottery(msg.sender).isContract());
    tax_allowance = ta;
  }
  function getTaxAllowance() public view returns(uint) {
    return tax_allowance;
  }
  function isContract() public view returns(bool){
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
