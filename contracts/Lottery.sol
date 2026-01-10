pragma solidity ^0.8.22;
// SPDX-License-Identifier: UNLICENSED
import "Taxpayer.sol";

contract Lottery {
    address owner;
    mapping(address => bytes32) commits;
    mapping(address => uint) reveals;
    address[] revealed;

    uint256 startTime;
    uint256 revealTime;
    uint256 endTime;
    uint256 period;
    bool iscontract;

    // Initialize the registry with the lottery period.
    constructor(uint p) {
        period = p;
        startTime = 0;
        endTime = 0;
        iscontract = true;
    }

    //If the lottery has not started, anyone can invoke a lottery.
    function startLottery() public {
        require(startTime == 0);
        //startTime current time. Users send their committed value
        startTime = block.timestamp;
        //revealTime  time for revealing. User reveal their value
        revealTime = startTime + period;
        //endTime a winner can be computed
        endTime = revealTime + period;
    }

    //A taxpayer send his own commitment.
    function commit(bytes32 y) public {
        require(block.timestamp >= startTime);
          // write-once per round
  require(commits[msg.sender] == bytes32(0), "already committed");
        commits[msg.sender] = y;
    }

    //A valid taxpayer who sent his own commitment, sends the revealing value.
    function reveal(uint256 rev) public {
        require(block.timestamp >= revealTime);
        require(keccak256(abi.encode(rev)) == commits[msg.sender]);
        revealed.push(msg.sender);
        reveals[msg.sender] = uint(rev);
    }

    //Ends the lottery and compute the winner.
    function endLottery() public {
        require(block.timestamp >= endTime);
        uint total = 0;
        for (uint i = 0; i < revealed.length; i++)
            total += reveals[revealed[i]];
        Taxpayer(revealed[total % revealed.length]).setTaxAllowance(7000);
        startTime = 0;
        revealTime = 0;
        endTime = 0;
    }
    function isContract() public view returns (bool) {
        return iscontract;
    }

    function getCommit(address a) external view returns (bytes32) {
        return commits[a];
    }

    function getReveal(address a) external view returns (uint) {
        return reveals[a];
    }

    function revealedLength() external view returns (uint) {
        return revealed.length;
    }

    function revealedAt(uint i) external view returns (address) {
        return revealed[i];
    }

    function getTimes() external view returns (uint256, uint256, uint256) {
        return (startTime, revealTime, endTime);
    }
}
