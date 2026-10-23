# On-chain Agent Patterns – Deep Dive

## 1. Planner / Executor

**Status:** Implemented

### How it works
- An off-chain AI (Planner) decides what action to take
- It creates and signs an `Intent` (EIP-712)
- Anyone can submit the signed Intent to the contract
- The contract verifies the signature, nonce, and deadline, then executes the call

### Key Properties
- High trust (only the designated signer can authorize actions)
- Low latency
- Simple and auditable

### Best for
- Retail DeFi actions
- Controlled agent operations
- Situations where you want strong guarantees

### Limitations
- The agent cannot act without creating a new signed Intent
- Not suitable for high-frequency or fully autonomous strategies

---

## 2. Bounded Autonomy

**Status:** Planned

### Concept
The agent receives limited permission to act freely within predefined boundaries (spending limits, allowed targets, time windows, etc.).

Instead of signing every single action, the agent operates inside a sandbox enforced by the smart contract.

### Expected Benefits
- Better autonomy
- Still maintains meaningful constraints
- Good balance between flexibility and safety

---

## 3. Multi-agent + Arbitration

**Status:** Planned

### Concept
Multiple agents can propose actions.  
A consensus or arbitration mechanism (voting, multisig, dispute window, etc.) decides what gets executed.

### Best for
- High-value decisions
- Institutional use cases
- Situations requiring higher security and checks

---

More details and implementations will be added as the patterns are built.
