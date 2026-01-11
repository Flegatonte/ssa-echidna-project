// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "./TestableLottery.sol";

/*
 * player wrappers
 * ---------------
 * echidna calls methods on this harness, so without wrappers msg.sender would
 * always be TestLottery.
 *
 * we use small contracts as "participants" so each one has a stable address and
 * we can reason about per-player commits/reveals.
 */
contract Player is Taxpayer {
    Lottery internal lot;

    constructor(Lottery _lot) Taxpayer(address(0), address(0)) {
        lot = _lot;

        // keep it under 65 to be eligible for the lottery
        age = 30;
    }

    function commitSecret(uint256 secret) external {
        // commit = keccak256(secret)
        bytes32 h = keccak256(abi.encode(secret));
        lot.commit(h);
    }

    function revealSecret(uint256 secret) external {
        lot.reveal(secret);
    }
}

/*
 * senior player
 * -------------
 * used only to test the "under 65 only" rule.
 */
contract SeniorPlayer is Taxpayer {
    Lottery internal lot;

    constructor(Lottery _lot) Taxpayer(address(0), address(0)) {
        lot = _lot;

        // >= 65 by construction
        age = 70;
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
    // lot + participants
    TestableLottery internal lot;
    Player internal player1;
    Player internal player2;
    SeniorPlayer internal senior;

    // harness memory (so reveal can actually match commit)
    uint256 internal lastSecret1;
    uint256 internal lastSecret2;
    bool internal hasSecret1;
    bool internal hasSecret2;

    // property 11 bookkeeping (close -> clean -> next start must work)
    bool internal pendingPostCloseCheck;
    bool internal lastPostCloseWasClean = true;
    bool internal lastStartAfterCloseSucceeded = true;

    constructor() {
        // period = 1: revealTime = start+1, endTime = reveal+1
        // time is controlled via TestableLottery fake clock + warp()
        lot = new TestableLottery(1);

        player1 = new Player(lot);
        player2 = new Player(lot);
        senior = new SeniorPlayer(lot);

        // start immediately so commit is reachable without needing startRound first
        lot.startLottery();
    }

    // echidna actions

    // move fake time forward (bounded inside TestableLottery)
    function warp(uint256 delta) external {
        lot.warp(delta);
    }

    // commit actions: store secret so we can later reveal the matching value
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

    // reveal actions: use stored secrets (may revert if called in the wrong phase)
    function revealP1() external {
        if (!hasSecret1) return;
        player1.revealSecret(lastSecret1);
    }

    function revealP2() external {
        if (!hasSecret2) return;
        player2.revealSecret(lastSecret2);
    }

    // internal helpers for properties

    // commit should be write-once per participant (in the same round)
    function _checkCommitWriteOnce(Player p) internal returns (bool) {
        bytes32 before = lot.getCommit(address(p));

        // nothing committed yet => nothing to enforce
        if (before == bytes32(0)) return true;

        // overwrite probe: revert is fine, success must not change the stored commit
        try p.commitSecret(999999) {
            return lot.getCommit(address(p)) == before;
        } catch {
            return lot.getCommit(address(p)) == before;
        }
    }

    // warp to reveal phase (so reveal can be reached deterministically)
    function _warpToReveal() internal {
        (, uint256 rTime, ) = lot.getTimes();
        uint256 nowTs = lot.getTime();
        if (nowTs < rTime) {
            lot.warp(rTime - nowTs);
        }
    }

    // warp to end phase (so endLottery can be reached deterministically)
    function _warpToEnd() internal {
        (, , uint256 eTime) = lot.getTimes();
        uint256 nowTs = lot.getTime();
        if (nowTs < eTime) {
            lot.warp(eTime - nowTs);
        }
    }

    // reveal should be write-once per participant (no duplicate ticket)
    function _checkRevealWriteOnce(
        Player p,
        uint256 sec,
        bool hasSec
    ) internal returns (bool) {
        if (!hasSec) return true;
        if (lot.getCommit(address(p)) == bytes32(0)) return true;

        _warpToReveal();

        uint256 lenBefore = lot.revealedLength();

        // first reveal attempt with the matching secret
        try p.revealSecret(sec) {
            uint256 lenAfterFirst = lot.revealedLength();

            // on success, exactly one ticket must be added
            if (lenAfterFirst != lenBefore + 1) return false;

            // second reveal must not add another ticket (revert ok)
            try p.revealSecret(sec) {
                return lot.revealedLength() == lenAfterFirst;
            } catch {
                return lot.revealedLength() == lenAfterFirst;
            }
        } catch {
            // if first reveal never succeeded, we cannot enforce write-once yet
            return true;
        }
    }

    // -------------------------------------------------------------------------
    // properties 8/9/10 
    // -------------------------------------------------------------------------

    function echidna_commit_is_write_once_per_round() public returns (bool) {
        return _checkCommitWriteOnce(player1);
    }

    function echidna_reveal_is_write_once_per_round() public returns (bool) {
        return _checkRevealWriteOnce(player1, lastSecret1, hasSecret1);
    }

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
    // property 11: clean close + restartability
    // -------------------------------------------------------------------------

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

    // if a close actually happens, we record the post-close checks
    function endRound() external {
        try lot.endLottery() {
            (uint256 s, , ) = lot.getTimes();
            if (s == 0) {
                lastPostCloseWasClean = _isCleanClosedState();
                pendingPostCloseCheck = true;
            }
        } catch {
            // ignore: we only arm checks after a real successful close
        }
    }

    // start after a checked close must succeed
    function startRound() external {
        if (!pendingPostCloseCheck) {
            try lot.startLottery() {} catch {}
            return;
        }

        try lot.startLottery() {
            lastStartAfterCloseSucceeded = true;
        } catch {
            lastStartAfterCloseSucceeded = false;
        }

        pendingPostCloseCheck = false;
    }

    function echidna_round_starts_clean_for_all_participants()
        public
        view
        returns (bool)
    {
        return lastPostCloseWasClean && lastStartAfterCloseSucceeded;
    }

    // -------------------------------------------------------------------------
    // property 12: under-65 only
    // -------------------------------------------------------------------------

    function echidna_only_under_65_can_commit() public returns (bool) {
        // senior tries to commit: revert is fine, but state must not change
        try senior.commitSecret(123456) {} catch {}

        bool ok = true;
        ok = ok && (lot.getCommit(address(senior)) == bytes32(0));
        ok = ok && (lot.getHasCommitted(address(senior)) == false);
        return ok;
    }

    // -------------------------------------------------------------------------
    // property 13: phase separation
    // -------------------------------------------------------------------------

    function echidna_phase_separation() public returns (bool) {
        bool ok = true;

        (uint256 st, uint256 rt, uint256 et) = lot.getTimes();
        uint256 nowT = lot.getTime();

        if (st == 0) return true;

        // commit after revealTime must revert or have no observable effects
        if (nowT < rt) {
            try lot.warp(rt - nowT + 1) {} catch {}
        }

        bool commitSucceeded = true;
        try player1.commitSecret(123) {} catch {
            commitSucceeded = false;
        }

        if (commitSucceeded) {
            ok = ok && (lot.getCommit(address(player1)) == bytes32(0));
            ok = ok && (lot.getHasCommitted(address(player1)) == false);
        }

        // reveal after endTime must revert or have no observable effects
        nowT = lot.getTime();
        if (nowT < et) {
            try lot.warp(et - nowT + 1) {} catch {}
        }

        bool revealSucceeded = true;
        try player2.revealSecret(456) {} catch {
            revealSucceeded = false;
        }

        if (revealSucceeded) {
            ok = ok && (lot.getHasRevealed(address(player2)) == false);
            ok = ok && (lot.getReveal(address(player2)) == 0);
        }

        return ok;
    }

    // -------------------------------------------------------------------------
    // property 14: winner validity (post-condition of endLottery)
    // -------------------------------------------------------------------------

    function echidna_winner_is_revealed_participant() public returns (bool) {
        (uint256 st, , uint256 et) = lot.getTimes();

        if (st == 0) return true;

        uint256 rlen = lot.revealedLength();
        if (rlen == 0) return true;

        // make endLottery reachable
        uint256 nowT = lot.getTime();
        if (nowT < et) {
            try lot.warp(et - nowT + 1) {} catch {}
        }

        // snapshot revealed[] before endLottery clears it
        address[] memory snap = new address[](rlen);
        for (uint256 i = 0; i < rlen; i++) {
            snap[i] = lot.revealedAt(i);
        }

        // close must succeed now (given now >= endTime and rlen > 0)
        try lot.endLottery() {} catch {
            return false;
        }

        // winner must be one of the revealed addresses we snapped
        address w = lot.getWinner();
        for (uint256 i = 0; i < rlen; i++) {
            if (snap[i] == w) return true;
        }

        return false;
    }
}
