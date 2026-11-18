# Evidence map: claim → test → command

Every row in this file is machine-checkable: the claim, the exact test that pins it, and the
command that reproduces it. Nothing here is asserted without a test name, and the
documentation guard fails the build if a test named in this repository's documentation stops
existing (`scripts/check_doc_claims.py`, run in CI as the `docs-claims` job).

Purpose for readers of a grant application: a reviewer should not have to trust prose. Pick
a row, run the command, see the pass.

## How to run everything

```bash
git submodule update --init --recursive
forge test                                 # the whole Solidity suite
python -m pip install -r requirements.txt  # once, for the Python suite
python -m unittest discover -s tests -v    # the Python signer tests
bash scripts/verify_all.sh                 # all four CI checks, locally
```

The last command is the same set CI runs: Solidity, Python, the release-workflow harness and
the documentation guard (in both of its modes).

## Signature authorization

| Claim | Pinned by | Reproduce |
|---|---|---|
| A signature that does not recover to the configured signer is rejected | `test_RevertWhenSignatureIsInvalid` (`test/Pattern1.t.sol`) | `forge test --match-test test_RevertWhenSignatureIsInvalid` |
| A malleable (high-`s`) signature is not accepted as a second valid encoding | `test_RejectsMalleableHighSSignature` (`test/SecurityReview.t.sol`) | `forge test --match-test test_RejectsMalleableHighSSignature` |
| A signature made for another chain does not verify here | `test_RejectsSignatureFromAnotherChain` (`test/SecurityReview.t.sol`) | `forge test --match-test test_RejectsSignatureFromAnotherChain` |
| The Python signer produces a digest the contract accepts (no format drift between the two implementations) | `test_ExecutePythonGeneratedEIP712Signature` (`test/Pattern1.t.sol`) | `forge test --match-test test_ExecutePythonGeneratedEIP712Signature` |
| The Python signer validates its configuration and refuses malformed input instead of guessing | the Python suite: 7 cases covering input validation and signer recovery (`tests/`) | `python -m unittest discover -s tests -v` |

## Replay and nonce ordering

| Claim | Pinned by | Reproduce |
|---|---|---|
| The same signed Intent cannot be executed twice | `test_RevertWhenReplayingUsedIntent` (`test/Pattern1.t.sol`), `test_ReplayAfterExecutionRevertsOnNonce` (`test/SecurityReview.t.sol`) | `forge test --match-test test_ReplayAfterExecutionRevertsOnNonce` |
| An Intent with the wrong nonce is rejected | `test_RevertWhenWrongNonce` (`test/Pattern1.t.sol`) | `forge test --match-test test_RevertWhenWrongNonce` |
| A future nonce may be queued but not executed before its turn | `test_QueuedFutureNonceExecutesAfterEarlierIntent` (`test/SecurityReview.t.sol`), `test_RevertWhenExecutingFutureNonceBeforeCurrentNonce` (`test/Pattern3.t.sol`) | `forge test --match-test test_QueuedFutureNonceExecutesAfterEarlierIntent` |
| Two proposals cannot reserve the same nonce | `test_RevertWhenNonceIsAlreadyReserved` (`test/Pattern3.t.sol`) | `forge test --match-test test_RevertWhenNonceIsAlreadyReserved` |

## Deadline

| Claim | Pinned by | Reproduce |
|---|---|---|
| An expired Intent is rejected | `test_RevertWhenExpired` (`test/Pattern1.t.sol`) | `forge test --match-test test_RevertWhenExpired` |
| The boundary second is allowed, deliberately | `test_DeadlineBoundaryIsInclusive` (`test/SecurityReview.t.sol`) | `forge test --match-test test_DeadlineBoundaryIsInclusive` |

## Spending cap and day boundary

| Claim | Pinned by | Reproduce |
|---|---|---|
| An Intent above the remaining cap is rejected | `test_RevertWhenSpendingCapExceeded` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenSpendingCapExceeded` |
| Spending exactly at the cap is allowed | `test_ExecuteAtExactDailySpendingCap` (`test/Pattern2.t.sol`) | `forge test --match-test test_ExecuteAtExactDailySpendingCap` |
| Several Intents in one day cannot sum past the cap | `test_MultipleTransactionsCannotExceedDailySpendingCap` (`test/Pattern2.t.sol`) | `forge test --match-test test_MultipleTransactionsCannotExceedDailySpendingCap` |
| Re-entrancy cannot be used to pass the cap | `test_ReentrancyCannotExceedDailySpendingCap` (`test/Pattern2.t.sol`) | `forge test --match-test test_ReentrancyCannotExceedDailySpendingCap` |
| The cap resets on a new day | `test_DailySpendingCapResetsOnNewDay` (`test/Pattern2.t.sol`) | `forge test --match-test test_DailySpendingCapResetsOnNewDay` |
| The old cap still applies one second before the boundary | `test_CapStillAppliesOneSecondBeforeDayBoundary` (`test/SecurityReview.t.sol`) | `forge test --match-test test_CapStillAppliesOneSecondBeforeDayBoundary` |
| A transaction straddling midnight can spend two caps seconds apart — documented, not claimed as prevented | `test_BoundaryStraddleAllowsTwoCapsCloseTogether` (`test/SecurityReview.t.sol`) | `forge test --match-test test_BoundaryStraddleAllowsTwoCapsCloseTogether` |
| Idle days do not accumulate allowance | `test_DayResetDoesNotAccumulateAcrossIdleDays` (`test/SecurityReview.t.sol`) | `forge test --match-test test_DayResetDoesNotAccumulateAcrossIdleDays` |
| Lowering the cap below what is already spent blocks further spending | `test_ReducingSpendingCapBelowSpentAmountBlocksFurtherSpending` (`test/Pattern2.t.sol`) | `forge test --match-test test_ReducingSpendingCapBelowSpentAmountBlocksFurtherSpending` |

## Emergency stop and allowlist

| Claim | Pinned by | Reproduce |
|---|---|---|
| A paused contract executes nothing | `test_RevertWhenEmergencyStopped` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenEmergencyStopped` |
| Pause is checked before the allowlist, so the revert reason is the pause | `test_ContractPausedTakesPrecedenceOverTargetNotAllowed` (`test/SecurityReview.t.sol`) | `forge test --match-test test_ContractPausedTakesPrecedenceOverTargetNotAllowed` |
| Resume lets the same signed Intent through, without yesterday's spend | `test_ResumeExecutesTheSameSignedIntent`, `test_ResumeAfterMidnightDoesNotCarryYesterdaySpend` (`test/SecurityReview.t.sol`) | `forge test --match-test test_ResumeExecutesTheSameSignedIntent` |
| A non-allowlisted target is rejected | `test_RevertWhenTargetNotAllowed` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenTargetNotAllowed` |
| Removing a target takes effect for later Intents | `test_AdminCanRemoveTarget` (`test/Pattern2.t.sol`) | `forge test --match-test test_AdminCanRemoveTarget` |

## Separation of duties

| Claim | Pinned by | Reproduce |
|---|---|---|
| Only the admin can change the cap | `test_RevertWhenNonAdminChangesSpendingCap` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenNonAdminChangesSpendingCap` |
| Only the admin can add or remove targets | `test_RevertWhenNonAdminAddsTarget`, `test_RevertWhenNonAdminRemovesTarget` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenNonAdminAddsTarget` |
| Only the admin can pause or resume | `test_RevertWhenNonAdminTriggersEmergencyStop`, `test_RevertWhenNonAdminResumesContract` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenNonAdminTriggersEmergencyStop` |
| Pattern 3 cannot be executed directly, bypassing the quorum | `test_RevertWhenDirectExecutionIsAttempted` (`test/Pattern3.t.sol`) | `forge test --match-test test_RevertWhenDirectExecutionIsAttempted` |
| Only the arbiter can add agents or resolve arbitration | `test_RevertWhenNotArbiter` (`test/Pattern3.t.sol`) | `forge test --match-test test_RevertWhenNotArbiter` |

## Atomicity and failure handling

| Claim | Pinned by | Reproduce |
|---|---|---|
| A failing target call rolls back the spend and the nonce | `test_RevertWhenTargetCallFailsAndRollsBackState` (`test/Pattern2.t.sol`) | `forge test --match-test test_RevertWhenTargetCallFailsAndRollsBackState` |
| A rejected proposal does not consume the nonce | `test_RejectedProposalReleasesNonce` (`test/Pattern3.t.sol`) | `forge test --match-test test_RejectedProposalReleasesNonce` |
| A paused rejection leaves nonce and spend unchanged | `test_PausedRejectionLeavesNonceAndDailySpendUntouched` (`test/SecurityReview.t.sol`) | `forge test --match-test test_PausedRejectionLeavesNonceAndDailySpendUntouched` |

## Quorum and arbitration

| Claim | Pinned by | Reproduce |
|---|---|---|
| Execution requires a quorum | `test_RevertWhenApprovingWithoutQuorum` (`test/Pattern3.t.sol`) | `forge test --match-test test_RevertWhenApprovingWithoutQuorum` |
| Removing agents does not lower an existing proposal's quorum | `test_RemovingAgentDoesNotLowerExistingProposalQuorum` (`test/Pattern3.t.sol`) | `forge test --match-test test_RemovingAgentDoesNotLowerExistingProposalQuorum` |
| An agent added later cannot vote on an older proposal | `test_NewAgentCannotVoteOnOldProposal` (`test/Pattern3.t.sol`) | `forge test --match-test test_NewAgentCannotVoteOnOldProposal` |
| A removed agent cannot vote on an existing proposal | `test_RemovedAgentCannotVoteOnExistingProposal` (`test/SecurityReview.t.sol`) | `forge test --match-test test_RemovedAgentCannotVoteOnExistingProposal` |
| A squatted nonce stalls the pipeline until the arbiter rejects it | `test_SquattedNonceStallsPipelineUntilArbiterRejects` (`test/SecurityReview.t.sol`) | `forge test --match-test test_SquattedNonceStallsPipelineUntilArbiterRejects` |
| An expired proposal cannot execute but can still be rejected | `test_ExpiredProposalCannotExecuteButCanBeRejected` (`test/SecurityReview.t.sol`) | `forge test --match-test test_ExpiredProposalCannotExecuteButCanBeRejected` |

## Sequence-level properties (invariants)

| Claim | Pinned by | Reproduce |
|---|---|---|
| No execution leaves recorded spend above the cap in force at that moment | `invariant_ExecutionNeverExceedsCap` (`test/Pattern2Invariant.t.sol`) | `forge test --match-test invariant_ExecutionNeverExceedsCap` |
| Nothing executes while paused | `invariant_NoExecutionWhilePaused` (`test/Pattern2Invariant.t.sol`) | `forge test --match-test invariant_NoExecutionWhilePaused` |
| The nonce advances exactly once per successful execution | `invariant_NonceMatchesExecutions` (`test/Pattern2Invariant.t.sol`) | `forge test --match-test invariant_NonceMatchesExecutions` |
| Balance and recorded outflow agree, and the target received it | `invariant_BalanceMatchesOutflow` (`test/Pattern2Invariant.t.sol`) | `forge test --match-test invariant_BalanceMatchesOutflow` |

Each invariant runs over 256 runs and 128,000 handler calls with allowlisted and
non-allowlisted executions, cap changes, day jumps and pause/resume all active.

## The stolen-key comparison

| Claim | Pinned by | Reproduce |
|---|---|---|
| A stolen planner key drains Pattern 1 in one Intent | `test_StolenPlannerKey_DrainsPattern1` (`test/AttackComparison.t.sol`) | `forge test --match-test test_StolenPlannerKey_DrainsPattern1` |
| In Pattern 2 the same key cannot reach a non-allowlisted target and cannot pass the cap | `test_StolenPlannerKey_IsBoundedInPattern2` | `forge test --match-test test_StolenPlannerKey_IsBoundedInPattern2` |
| In Pattern 2 the same key still drains 3 ETH, over three days | `test_StolenPlannerKey_DrainsPattern2OverDays` | `forge test --match-test test_StolenPlannerKey_DrainsPattern2OverDays` |
| In Pattern 3 the same key cannot execute alone | `test_StolenPlannerKey_CannotExecuteAloneInPattern3` | `forge test --match-test test_StolenPlannerKey_CannotExecuteAloneInPattern3` |

## Known gaps, pinned by tests rather than hidden

| Gap | Pinned by | Reproduce |
|---|---|---|
| A registered token's direct `transfer` is bounded by its own daily cap; movement outside that path (a pre-existing allowance, a target that pulls with `transferFrom`) bypasses both caps | `test_TokenTransfersAreBoundedByTheirOwnCap` (`test/SecurityReview.t.sol`) | `forge test --match-test test_TokenTransfersAreBoundedByTheirOwnCap` |
| Malleable signatures would be accepted without the `ECDSA` library's high-`s` rejection | `test_RejectsMalleableHighSSignature` (`test/SecurityReview.t.sol`) | `forge test --match-test test_RejectsMalleableHighSSignature` |

## Documentation integrity

| Claim | Pinned by | Reproduce |
|---|---|---|
| A test count or test name in the documentation that the suite does not have fails the build | `scripts/check_doc_claims.py` (`docs-claims` CI job) | `python scripts/check_doc_claims.py` |
| The guard's own patterns are pinned, so a removed pattern fails instead of going quiet | `scripts/check_doc_claims.py --self-test` | `python scripts/check_doc_claims.py --self-test` |
| The release workflow publishes the CHANGELOG section, not a placeholder | `scripts/test_release_workflow.sh` (4 cases) | `bash scripts/test_release_workflow.sh` |

## What this map does not do

- It does not turn any of this into an audit. Every row is a test written by the same author
  as the code, and that is exactly the gap milestone M1 of the grant is meant to close.
- It does not prove liveness or accounting. Removing `dailySpent += intent.value` or the day
  reset leaves the four invariants green; those behaviours are pinned by the unit and fuzz
  suites above, not by the invariants.
- It does not cover ERC-20 value, key rotation, upgradeability or operational security: none
  of those are implemented, and the roadmap in the README lists them as planned work.
