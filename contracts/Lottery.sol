// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Taxpayer.sol";

contract Lottery {
    // owner is unused in this version, but kept to match the original skeleton
    address owner;

    // commit/reveal storage
    mapping(address => bytes32) commits;
    mapping(address => uint256) reveals;

    // observable flags (useful for testing and report discussion)
    mapping(address => bool) hasRevealed;
    mapping(address => bool) hasCommitted;

    // round tracking: helps us clean up reliably at the end of each round
    uint256 internal roundId;
    mapping(address => uint256) internal committedRound;

    // participants seen in the current round
    address[] internal committed;
    address[] internal revealed;

    // timing (startTime == 0 is the "closed" sentinel)
    uint256 startTime;
    uint256 revealTime;
    uint256 endTime;
    uint256 period;

    // marker used by Taxpayer.setTaxAllowance() to recognize the lottery contract
    bool iscontract;

    // winner of the most recently closed round (only meaningful if there was at least one reveal)
    address public winner;

    constructor(uint256 p) {
        period = p;

        // closed by default
        startTime = 0;
        revealTime = 0;
        endTime = 0;

        iscontract = true;
    }

    // time source (block.timestamp in production, fake clock in tests)
    function _now() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    // start a new round (only allowed when closed)
    function startLottery() public {
        require(startTime == 0, "lottery already running");

        // new round id for cleanup bookkeeping
        roundId += 1;

        startTime = _now();
        revealTime = startTime + period;
        endTime = revealTime + period;
    }

    // commit phase: accept one commitment per participant
    function commit(bytes32 y) public {
        // only taxpayer contracts can participate
        require(msg.sender.code.length > 0, "participant must be a contract");
        require(Taxpayer(msg.sender).isContract(), "participant not taxpayer");

        // lottery is reserved to under-65 participants
        require(Taxpayer(msg.sender).getAge() < 65, "age >= 65");

        // must be running and inside the commit window
        require(startTime != 0, "lottery not started");
        require(_now() >= startTime, "too early");
        require(_now() < revealTime, "commit phase over");

        // write-once per round (per participant)
        require(commits[msg.sender] == bytes32(0), "already committed");

        // track who committed in this round so we can clean state at the end
        if (committedRound[msg.sender] != roundId) {
            committedRound[msg.sender] = roundId;
            committed.push(msg.sender);
        }

        hasCommitted[msg.sender] = true;
        commits[msg.sender] = y;
    }

    // reveal phase: reveal the preimage of the commitment
    function reveal(uint256 rev) public {
        require(msg.sender.code.length > 0, "participant must be a contract");
        require(Taxpayer(msg.sender).isContract(), "participant not taxpayer");
        require(Taxpayer(msg.sender).getAge() < 65, "age >= 65");

        // must be inside reveal window
        require(_now() >= revealTime, "reveal not started");
        require(_now() < endTime, "reveal phase over");

        // write-once per participant
        require(!hasRevealed[msg.sender], "already revealed");

        // must match the commitment
        require(keccak256(abi.encode(rev)) == commits[msg.sender], "invalid reveal");

        hasRevealed[msg.sender] = true;
        revealed.push(msg.sender);
        reveals[msg.sender] = rev;
    }

    // end the round, compute winner if possible, then reset all round state
    function endLottery() public {
        require(_now() >= endTime, "too early to end");

        // if nobody revealed, we still must reset the round (no dos by inactivity)
        if (revealed.length != 0) {
            uint256 total = 0;
            for (uint256 i = 0; i < revealed.length; i++) {
                total += reveals[revealed[i]];
            }

            winner = revealed[total % revealed.length];

            // reward: winner gets the 7000 allowance (as per assignment)
            Taxpayer(winner).setTaxAllowance(7000);
        }

        // cleanup all per-round participant state (based on committed[] list)
        for (uint256 i = 0; i < committed.length; i++) {
            address a = committed[i];
            commits[a] = bytes32(0);
            reveals[a] = 0;
            hasRevealed[a] = false;
            hasCommitted[a] = false;
        }

        delete committed;
        delete revealed;

        // close the lottery
        startTime = 0;
        revealTime = 0;
        endTime = 0;
    }

    // used by Taxpayer to recognize the lottery as an authorized caller
    function isContract() public view returns (bool) {
        return iscontract;
    }

    // getters used by echidna properties
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

    function getWinner() external view returns (address) {
        return winner;
    }
}
