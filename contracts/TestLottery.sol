// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./TestableLottery.sol";

/*
 * player wrapper
 * --------------
 * echidna calls functions on the harness contract, so msg.sender would otherwise
 * always be TestLottery.
 *
 * we want per-participant behavior with stable participant addresses, so we use
 * small wrapper contracts: player1 and player2. then msg.sender is address(playerX).
 */
contract Player {
    Lottery internal lot;

    constructor(Lottery _lot) {
        lot = _lot;
    }

    function commitSecret(uint256 secret) external {
        // commit = keccak(secret)
        bytes32 h = keccak256(abi.encode(secret));
        lot.commit(h);
    }

    function revealSecret(uint256 secret) external {
        lot.reveal(secret);
    }
}

contract TestLottery {
    // -------------------------------------------------------------------------
    // system under test (sut) + participants
    // -------------------------------------------------------------------------
    TestableLottery internal lot;
    Player internal player1;
    Player internal player2;

    // -------------------------------------------------------------------------
    // harness memory (to make reveal reachable and consistent)
    // -------------------------------------------------------------------------
    // we store the last committed secret for each participant so reveal can use
    // a value that actually matches the stored commit.
    uint256 internal lastSecret1;
    uint256 internal lastSecret2;
    bool internal hasSecret1;
    bool internal hasSecret2;

    // -------------------------------------------------------------------------
    // property 11 bookkeeping (post-close cleanliness + restartability)
    // -------------------------------------------------------------------------
    // after we observe a successful endLottery() that actually closes the round,
    // we arm a check:
    //  (a) right after closing, round state must be clean
    //  (b) the first startLottery() after that close must succeed (no revert)
    bool internal pendingPostCloseCheck;
    bool internal lastPostCloseWasClean = true;
    bool internal lastStartAfterCloseSucceeded = true;

    constructor() {
        // period = 1: revealTime = start+1, endTime = reveal+1
        // time is controlled via TestableLottery fake clock + warp()
        lot = new TestableLottery(1);

        player1 = new Player(lot);
        player2 = new Player(lot);

        // start immediately so commit is reachable without needing startRound first
        lot.startLottery();
    }

    // -------------------------------------------------------------------------
    // echidna actions (state exploration entry points)
    // -------------------------------------------------------------------------

    /*
     * advance time deterministically
     * ------------------------------
     * echidna does not reliably control block.timestamp, so we use TestableLottery
     * which overrides _now() with a fake time we can warp forward.
     */
    function warp(uint256 delta) external {
        lot.warp(delta);
    }

    /*
     * commit actions
     * --------------
     * store the secret in harness memory and commit via player wrapper
     * (so msg.sender is player address, not TestLottery).
     */
    function commitP1(uint256 secret) external {
        lastSecret1 = secret;
        hasSecret1 = true;
        player1.commitSecret(secret);
    }

    function commitP2(uint256 secret) external {
        lastSecret2 = secret;
        hasSecret2 = true;
        player2.commitSecret(secret);
    }

    /*
     * reveal actions
     * --------------
     * reveal using the stored secret (matches commit). may revert if not in reveal window.
     */
    function revealP1() external {
        if (!hasSecret1) return;
        player1.revealSecret(lastSecret1);
    }

    function revealP2() external {
        if (!hasSecret2) return;
        player2.revealSecret(lastSecret2);
    }

    // -------------------------------------------------------------------------
    // internal helpers (commit/reveal write-once probes)
    // -------------------------------------------------------------------------

    /*
     * commit must be write-once per participant
     * ----------------------------------------
     * if commit exists already, attempt an overwrite. either:
     *  - it reverts (ok), or
     *  - it succeeds but must not change stored commit.
     */
    function _checkCommitWriteOnce(Player p) internal returns (bool) {
        bytes32 before = lot.getCommit(address(p));

        // no commit yet => nothing to enforce
        if (before == bytes32(0)) return true;

        // overwrite probe (revert is acceptable)
        try p.commitSecret(999999) {
            return lot.getCommit(address(p)) == before;
        } catch {
            return lot.getCommit(address(p)) == before;
        }
    }

    /*
     * warp into reveal phase deterministically
     * ---------------------------------------
     * we do this inside the property helper so it does not depend on action ordering.
     */
    function _warpToReveal() internal {
        (, uint256 rTime, ) = lot.getTimes();
        uint256 nowTs = lot.getTime();
        if (nowTs < rTime) {
            lot.warp(rTime - nowTs);
        }
    }

    /*
     * warp into end phase deterministically
     * ------------------------------------
     * ensures endLottery() is reachable without relying on real time.
     */
    function _warpToEnd() internal {
        (, , uint256 eTime) = lot.getTimes();
        uint256 nowTs = lot.getTime();
        if (nowTs < eTime) {
            lot.warp(eTime - nowTs);
        }
    }

    /*
     * reveal must be write-once per participant
     * ----------------------------------------
     * attempt first reveal with the matching secret. if it succeeds, a second reveal with
     * the same secret must not change state (no duplicate ticket).
     *
     * if the first reveal fails (e.g. wrong window), we return true (cannot test yet).
     */
    function _checkRevealWriteOnce(
        Player p,
        uint256 sec,
        bool hasSec
    ) internal returns (bool) {
        // need a known secret and an existing commit
        if (!hasSec) return true;
        if (lot.getCommit(address(p)) == bytes32(0)) return true;

        _warpToReveal();

        uint256 lenBefore = lot.revealedLength();

        // first reveal attempt (must be the matching secret)
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
            // cannot enforce write-once if first reveal never succeeded
            return true;
        }
    }

    // -------------------------------------------------------------------------
    // properties 8/9/10 (as decided: only player1)
    // -------------------------------------------------------------------------

    /*
     * property 8: commit is write-once per round (per participant)
     * kept for player1 only.
     */
    function echidna_commit_is_write_once_per_round() public returns (bool) {
        return _checkCommitWriteOnce(player1);
    }

    /*
     * property 9: reveal is write-once per round (per participant)
     * kept for player1 only.
     */
    function echidna_reveal_is_write_once_per_round() public returns (bool) {
        return _checkRevealWriteOnce(player1, lastSecret1, hasSecret1);
    }

    /*
     * property 10: endLottery must not revert with no reveals
     * ------------------------------------------------------
     * we warp to end phase, and if nobody revealed yet, endLottery() must not revert.
     */
    function echidna_endLottery_does_not_revert_with_no_reveals()
        public
        returns (bool)
    {
        _warpToEnd();

        // only meaningful if nobody revealed yet
        if (lot.revealedLength() != 0) return true;

        try lot.endLottery() {
            return true;
        } catch {
            return false;
        }
    }

    // -------------------------------------------------------------------------
    // property 11: post-close state must be clean, and next start must succeed
    // -------------------------------------------------------------------------

    /*
     * clean closed state definition
     * -----------------------------
     * this checks round-specific state that must be reset after endLottery():
     * - arrays empty
     * - per-known-player storage cleared (commit/reveal/flags)
     *
     * note: we only assert per-player cleanup for player1/player2 because those are
     * the participants we model in the harness.
     */
    function _isCleanClosedState() internal view returns (bool) {
        bool ok = true;

        // arrays must be empty after cleanup
        ok = ok && (lot.revealedLength() == 0);
        ok = ok && (lot.committedLength() == 0);

        // commits cleared
        ok = ok && (lot.getCommit(address(player1)) == bytes32(0));
        ok = ok && (lot.getCommit(address(player2)) == bytes32(0));

        // reveal flags cleared
        ok = ok && (lot.getHasRevealed(address(player1)) == false);
        ok = ok && (lot.getHasRevealed(address(player2)) == false);

        // commit flags cleared (observable compatibility for tests/properties)
        ok = ok && (lot.getHasCommitted(address(player1)) == false);
        ok = ok && (lot.getHasCommitted(address(player2)) == false);

        // revealed values cleared
        ok = ok && (lot.getReveal(address(player1)) == 0);
        ok = ok && (lot.getReveal(address(player2)) == 0);

        return ok;
    }

    /*
     * endRound action
     * ---------------
     * best-effort call to endLottery(). if it succeeds and the round is closed
     * (startTime == 0 sentinel), then:
     *  - we immediately check that the post-close state is clean
     *  - we arm the "next start must succeed" check
     */
    function endRound() external {
        try lot.endLottery() {
            (uint256 s,,) = lot.getTimes();
            if (s == 0) {
                // round closed: state must be clean right now
                lastPostCloseWasClean = _isCleanClosedState();
                pendingPostCloseCheck = true;
            }
        } catch {
            // ignore: this is a best-effort action, checks trigger only after a real close
        }
    }

    /*
     * startRound action
     * -----------------
     * if we did not just observe a close, this is a best-effort start (ignore failures).
     * if we DID observe a close, then this is the first start attempt after that close,
     * and it must succeed (no revert).
     */
    function startRound() external {
        if (!pendingPostCloseCheck) {
            // not the first start-after-close we care about
            try lot.startLottery() {} catch {}
            return;
        }

        // first start attempt after a close we observed: must succeed
        try lot.startLottery() {
            lastStartAfterCloseSucceeded = true;
        } catch {
            lastStartAfterCloseSucceeded = false;
        }

        pendingPostCloseCheck = false;
    }

    /*
     * property 11
     * -----------
     * whenever we observed a close and performed the related checks:
     *  (a) post-close state was clean
     *  (b) the next start succeeded (no revert)
     *
     * if no checked close-start cycle happened yet, defaults are true.
     */
    function echidna_round_starts_clean_for_all_participants()
        public
        view
        returns (bool)
    {
        return lastPostCloseWasClean && lastStartAfterCloseSucceeded;
    }
}
