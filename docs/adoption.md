# Using these patterns in your own stack

This page is for someone who has read the README and wants to know whether one of these
patterns fits their agent, and what it costs to find out. It is a usage guide, not a
recommendation: the repository is an educational reference, it has not been independently
audited, and it is not production-ready. `README.md` → *Scope and Guarantees* is the
authoritative statement of that, and it applies to everything below.

## 1. Which pattern is your problem?

| If your situation is… | Start with | Contract | The test that shows the boundary |
|---|---|---|---|
| An LLM decides actions and you want the chain to enforce exactly what was authorised | Pattern 1 | `contracts/Pattern1_PlannerExecutor.sol` | `test_StolenPlannerKey_DrainsPattern1` |
| …and you want a bad decision to be rate-limited, not unbounded | Pattern 2 | `contracts/Pattern2_BoundedAutonomy.sol` | `test_StolenPlannerKey_IsBoundedInPattern2`, `test_StolenPlannerKey_DrainsPattern2OverDays` |
| …and no single agent should be able to move funds alone | Pattern 3 | `contracts/Pattern3_MultiAgentArbitration.sol` | `test_StolenPlannerKey_CannotExecuteAloneInPattern3` |

The tests in the last column run the *same* failure — the attacker controls the planner
signing key and can produce valid intents — against all three patterns. Reading those four
assertions is the fastest way to decide whether the trade-off is one you want.

## 2. Reproduce the test suite

No keys, no deployment, no funded account:

```bash
git clone https://github.com/meekail1996-a11y/miki-onchain-agent-patterns.git
cd miki-onchain-agent-patterns
git submodule update --init --recursive
git rev-parse HEAD     # the exact state you tested
forge --version        # the compiler toolchain behind it
forge test
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
bash scripts/verify_all.sh          # all four CI checks, including the docs guard
```

Record the commit and the Forge version with the run. A report that arrives three weeks
later is only reusable if it says which state it describes.

If those pass, you are looking at the state this page describes. If they do not, that is
worth reporting before anything else here matters.

## 3. What to read, in this order

1. `README.md` → *Scope and Guarantees* — what the project refuses to claim.
2. `docs/patterns.md` → the *Limitations* list under each pattern. These are the sentences
   that decide whether the pattern is usable for you.
3. `docs/architecture.md` → *Failure and stop paths*: 21 rows, each naming the test that
   pins it. If you plan to rely on a control, that table says which assertion stands behind
   it.
4. `docs/security.md` → every static-analysis finding with a written disposition, including
   the ones deliberately left unfixed and why.

Do not skip step 2. The most common way to misuse this repository is to adopt a pattern
because its tests are green and to miss the limitation written directly below them.

## 4. Limits that outlive any adaptation

| Pattern | What stays true even after you adapt it |
|---|---|
| 1 | A stolen signer key is full authority. A signature proves *who authorised*, never that the action is safe. |
| 2 | The daily cap bounds **native value**; ERC-20 is bounded only on the metered direct-`transfer` path, and an allowlisted target can still pull tokens through an allowance. The cap is a rate limit, not a barrier — 3 ETH still drains in 3 days against a 1 ETH cap. |
| 2 | `admin` is `immutable`: no transfer, no renounce. Lose the key, lose administration. |
| 3 | Quorum is a strict majority snapshotted at proposal creation, so removing agents can leave a proposal permanently unable to reach it. The arbiter can still reject such a proposal — the quorum check sits only in the approve branch of `resolveArbitration` — and rejection frees the reserved nonce. That exit still depends on the arbiter being reachable, and the arbiter is `immutable`. |
| 3 | The arbiter both admits agents (`addAgent` and `removeAgent` are `onlyArbiter`) and approves proposals. Quorum therefore constrains an arbiter only when the agents are genuinely independent of it. |
| 3 | The arbiter has decisive authority with no timeout or automatic escalation, and a lost arbiter key freezes governance until a redeploy. This is arbitration, not decentralised consensus. |

If your design needs any of these to be false, the pattern is a starting point for the
*shape*, not for the code.

## 5. A time-boxed trial (about half a day)

The useful question is not "does this compile" but "where does it stop fitting my stack".
A trial that answers it:

1. **Pick one pattern** — the one your current design most resembles, not the strongest one.
2. **Replace one seam**: your real signer for the Python signer, or your real target
   contract for the test target. Keep everything else untouched, so the diff shows what the
   pattern actually required of you.
3. **Break it on purpose**: send an intent above the cap, from a non-allowlisted target,
   with a stale nonce, and while paused. Note which of those your own code would have caught
   without the pattern.
4. **Record four things**: what you had to change, what the pattern could not express, what
   surprised you, and whether you would keep it. Half a page is enough.

Local anvil or a testnet is sufficient. Nothing here needs real funds, and no trial should
use a key that controls any.

## 6. Feedback that is actually useful

- A control you expected and did not find.
- A documented limitation that is wrong, understated, or already fixed upstream.
- A calldata or token path that reaches the target without the constraint you assumed.
- A place where the documentation reads stronger than the test that backs it.

Each of those is a documentation or test defect in this repository, and each is actionable.
"Looks good" is not: it cannot be acted on, and it will not be recorded as anything.

## 7. How to report it

Open an issue at
https://github.com/meekail1996-a11y/miki-onchain-agent-patterns/issues with the pattern,
the command you ran, and the observed versus expected behaviour.

If you are willing to have the trial mentioned publicly, say so explicitly and say how you
want to be named. Nothing about your use is documented, quoted, or counted as adoption
until you approve the exact wording — and a "no" costs you nothing.
