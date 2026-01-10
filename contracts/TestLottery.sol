// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./TestableLottery.sol";

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

    function revealSecret(uint256 secret) external {
        lot.reveal(secret);
    }
}

contract TestLottery {
    TestableLottery internal lot;
    Player internal player1;
    Player internal player2;

    // memory: last committed secret per participant (so reveal can match commit)
    uint256 internal lastSecret1;
    uint256 internal lastSecret2;
    bool internal hasSecret1;
    bool internal hasSecret2;

    constructor() {
        // period = 1, start immediately (time is controlled via TestableLottery)
        lot = new TestableLottery(1);
        player1 = new Player(lot);
        player2 = new Player(lot);
        lot.startLottery();
    }

    /*
     * echidna-callable action:
     * advance time deterministically (reachability for reveal/endLottery).
     */
    function warp(uint256 delta) external {
        lot.warp(delta);
    }

    /*
     * echidna-callable action:
     * create a commitment for player1.
     */
    function commitP1(uint256 secret) external {
        lastSecret1 = secret;
        hasSecret1 = true;
        player1.commitSecret(secret);
    }

    /*
     * echidna-callable action:
     * create a commitment for player2.
     */
    function commitP2(uint256 secret) external {
        lastSecret2 = secret;
        hasSecret2 = true;
        player2.commitSecret(secret);
    }

    /*
     * echidna-callable action:
     * reveal for player1 using the stored secret.
     */
    function revealP1() external {
        if (!hasSecret1) return;
        player1.revealSecret(lastSecret1);
    }

    /*
     * echidna-callable action:
     * reveal for player2 using the stored secret.
     */
    function revealP2() external {
        if (!hasSecret2) return;
        player2.revealSecret(lastSecret2);
    }

    function endRound() external {
    lot.endLottery();
}

    /*
     * internal helper: commit must be write-once for a participant.
     */
    function _checkCommitWriteOnce(Player p) internal returns (bool) {
        bytes32 before = lot.getCommit(address(p));

        // if participant never committed yet, nothing to enforce
        if (before == bytes32(0)) return true;

        // attempt an overwrite; may revert (expected after the fix)
        try p.commitSecret(999999) {
            return lot.getCommit(address(p)) == before;
        } catch {
            return lot.getCommit(address(p)) == before;
        }
    }

    /*
     * internal helper: move into reveal phase (deterministic).
     * we do this inside the property so it does not depend on action ordering.
     */
    function _warpToReveal() internal {
        (, uint256 rTime,) = lot.getTimes();
        uint256 nowTs = lot.getTime();
        if (nowTs < rTime) {
            lot.warp(rTime - nowTs);
        }
    }

    /*
     * internal helper: reveal must be write-once for a participant.
     */
    function _checkRevealWriteOnce(Player p, uint256 sec, bool hasSec) internal returns (bool) {
        // need a known secret that matches the current commit
        if (!hasSec) return true;
        if (lot.getCommit(address(p)) == bytes32(0)) return true;

        _warpToReveal();

        uint256 lenBefore = lot.revealedLength();

        // first reveal using the matching secret
        try p.revealSecret(sec) {
            uint256 lenAfterFirst = lot.revealedLength();

            // on success, must add exactly one ticket
            if (lenAfterFirst != lenBefore + 1) return false;

            // second reveal must not add another ticket (revert is ok)
            try p.revealSecret(sec) {
                return lot.revealedLength() == lenAfterFirst;
            } catch {
                return lot.revealedLength() == lenAfterFirst;
            }
        } catch {
            // if reveal fails even with stored secret, we can't enforce write-once yet
            return true;
        }
    }

    /*
     * Property 8: commitment is write-once per round (per participant).
     */
    function echidna_commit_is_write_once_per_round() public returns (bool) {
        if (!_checkCommitWriteOnce(player1)) return false;
        return true;
    }

    /*
     * Property 9: reveal is write-once per round (per participant).
     *
     * After a participant successfully reveals once in the current round,
     * any further reveal attempts by the same participant must NOT add
     * another entry in `revealed[]` (no duplicate tickets).
     */
    function echidna_reveal_is_write_once_per_round() public returns (bool) {
        if (!_checkRevealWriteOnce(player1, lastSecret1, hasSecret1)) return false;
        return true;
    }

    
}
