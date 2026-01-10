pragma solidity ^0.8.22;
// SPDX-License-Identifier: UNLICENSED
import "Taxpayer.sol";

contract Lottery {
    address owner;

    mapping(address => bytes32) commits;
    mapping(address => uint256) reveals;

    mapping(address => bool) hasRevealed;
    mapping(address => bool) hasCommitted; // kept for compatibility / observability

    // round tracking to make cleanup reliable
    uint256 internal roundId;
    mapping(address => uint256) internal committedRound;

    address[] internal committed;
    address[] internal revealed;

    uint256 startTime;
    uint256 revealTime;
    uint256 endTime;
    uint256 period;

    bool iscontract;

    // Initialize the registry with the lottery period.
    constructor(uint256 p) {
        period = p;
        startTime = 0;
        endTime = 0;
        iscontract = true;
    }

    // time source (production: block.timestamp, test: overridable)
    function _now() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    // If the lottery has not started, anyone can invoke a lottery.
    function startLottery() public {
        require(startTime == 0);

        // open a fresh round
        roundId += 1;

        startTime = _now();
        revealTime = startTime + period;
        endTime = revealTime + period;
    }

    // A taxpayer sends their own commitment.
    function commit(bytes32 y) public {
        require(startTime != 0, "lottery not started");
        require(_now() >= startTime);
        require(commits[msg.sender] == bytes32(0), "already committed");

        // track committers for THIS round (reliable cleanup list)
        if (committedRound[msg.sender] != roundId) {
            committedRound[msg.sender] = roundId;
            committed.push(msg.sender);
        }

        // keep old observable flag for property checks / report
        hasCommitted[msg.sender] = true;

        commits[msg.sender] = y;
    }

    // A valid taxpayer who sent their commitment reveals the value.
    function reveal(uint256 rev) public {
        require(_now() >= revealTime);
        require(!hasRevealed[msg.sender], "already revealed");
        require(keccak256(abi.encode(rev)) == commits[msg.sender]);

        hasRevealed[msg.sender] = true;
        revealed.push(msg.sender);
        reveals[msg.sender] = rev;
    }

    // Ends the lottery and computes the winner.
    function endLottery() public {
        require(_now() >= endTime);

        // if nobody revealed, just cleanup and reset (prevents DoS + stale state)
        if (revealed.length != 0) {
            uint256 total = 0;
            for (uint256 i = 0; i < revealed.length; i++) {
                total += reveals[revealed[i]];
            }
            Taxpayer(revealed[total % revealed.length]).setTaxAllowance(7000);
        }

        // cleanup commits / reveals / flags for all committers (THIS round list)
        for (uint256 i = 0; i < committed.length; i++) {
            address a = committed[i];
            commits[a] = bytes32(0);
            reveals[a] = 0;
            hasRevealed[a] = false;
            hasCommitted[a] = false;
        }

        delete committed;
        delete revealed;

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

    function getReveal(address a) external view returns (uint256) {
        return reveals[a];
    }

    function revealedLength() external view returns (uint256) {
        return revealed.length;
    }

    function revealedAt(uint256 i) external view returns (address) {
        return revealed[i];
    }

    function getTimes() external view returns (uint256, uint256, uint256) {
        return (startTime, revealTime, endTime);
    }

    function getHasRevealed(address a) external view returns (bool) {
        return hasRevealed[a];
    }

    function committedLength() external view returns (uint256) {
        return committed.length;
    }

    function committedAt(uint256 i) external view returns (address) {
        return committed[i];
    }

    function getHasCommitted(address a) external view returns (bool) {
        return hasCommitted[a];
    }
}
