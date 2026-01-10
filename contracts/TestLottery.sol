// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./Lottery.sol";

/*
 * Player wrapper: keeps msg.sender stable (the Player contract),
 * so Echidna can reason about commits per participant address.
 */
contract Player {
    Lottery internal lot;

    constructor(Lottery _lot) {
        lot = _lot;
    }

    function commitSecret(uint256 secret) external {
        bytes32 h = keccak256(abi.encode(secret));
        lot.commit(h);
    }
}

contract TestLottery {
    Lottery internal lot;
    Player internal player;

    constructor() {
        // period = 1, start immediately
        lot = new Lottery(1);
        player = new Player(lot);
        lot.startLottery();
    }

    /*
     * echidna-callable action:
     * create the first commitment (if commit is allowed by the current time window).
     */
    function commitOnce(uint256 secret) external {
        player.commitSecret(secret);
    }

    /*
     * Property: commitment is write-once per round.
     *
     * If a participant has already committed (commit != 0),
     * then attempting to commit again must NOT change the stored commitment.
     *
     * We implement this as an active probe:
     * - read the stored commitment
     * - attempt an overwrite
     * - require that the stored commitment is unchanged
     *
     * IMPORTANT: the overwrite attempt may revert after the fix;
     * we catch that revert so the property result stays boolean (not ErrorRevert).
     */
    function echidna_commit_is_write_once_per_round() public returns (bool) {
        bytes32 before = lot.getCommit(address(player));

        // if player never committed yet, nothing to enforce
        if (before == bytes32(0)) return true;

        // attempt an overwrite; may revert (expected after the fix)
        try player.commitSecret(999999) {
            // if it doesn't revert, it still must not change the stored commitment
            return lot.getCommit(address(player)) == before;
        } catch {
            // revert is fine, but the stored commitment must still be unchanged
            return lot.getCommit(address(player)) == before;
        }
    }
}
