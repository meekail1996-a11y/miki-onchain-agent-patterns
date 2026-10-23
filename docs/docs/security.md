# Security Checklist for On-chain Agents

Reference implementations in this repo are **educational**, not audited. Before deploying to production, work through this checklist.

---

## 1. Key Management

- [ ] **Never give the LLM direct access to private keys**
- [ ] Use a dedicated signer key, separate from the deployer
- [ ] Store keys in a secure environment (HSM, TEE, or hardware wallet)
- [ ] Rotate signer keys on a schedule
- [ ] Have an emergency key revocation mechanism

---

## 2. Intent Validation

- [ ] **Verify EIP-712 signatures on-chain** (don't trust off-chain validation)
- [ ] Include a **deadline** in every intent
- [ ] Include a **nonce** to prevent replay attacks
- [ ] Validate all intent fields (target, value, data) against expected bounds
- [ ] Reject intents with `deadline` in the past

---

## 3. Access Control

- [ ] **Whitelist target contracts** the agent can call
- [ ] Cap **max value per transaction**
- [ ] Cap **max total spend per epoch** (e.g., per day)
- [ ] Only allow specific function selectors (avoid generic `call`)
- [ ] Use a **pausable** pattern for emergency stops

---

## 4. Economic Safety

- [ ] Simulate the transaction before executing (Tenderly, Foundry fork)
- [ ] Set **max slippage** for DEX interactions
- [ ] Consider **MEV protection** (Flashbots Protect, private mempools)
- [ ] Have a **circuit breaker** for abnormal conditions
- [ ] Log every intent and execution on-chain (for auditability)

---

## 5. Testing

- [ ] Unit tests for all edge cases (expired, replay, wrong signer, etc.)
- [ ] Fuzz tests for intent fields
- [ ] Fork tests against real mainnet state
- [ ] Invariant tests for economic properties
- [ ] **External audit** before handling real funds

---

## 6. Operational

- [ ] Monitoring and alerting on unusual activity
- [ ] Incident response plan (who does what if something goes wrong)
- [ ] Rate limiting on intent submission
- [ ] Dead man's switch (if signer goes offline for X hours, halt)

---

## 7. Known Limitations

**Pattern 1 (Planner/Executor):**
- No built-in target whitelist (must be added)
- No spending caps (must be added)
- If signer key leaks, attacker can sign arbitrary intents (until revoke)

**Pattern 2 (Bounded Autonomy):**
- Parameter tuning is critical (too tight = useless, too loose = dangerous)
- Session key management adds complexity
- TEEs have their own trust assumptions

**Pattern 3 (Multi-agent):**
- Significantly slower (10-100x)
- Coordination overhead
- Dispute resolution is non-trivial

---

## Reporting Vulnerabilities

If you find a security issue in this repo, open an issue with the `[SECURITY]` prefix. Do not exploit.

For production deployments, always commission a professional audit.
