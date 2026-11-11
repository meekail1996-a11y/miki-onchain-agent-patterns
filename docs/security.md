# Security Model and Threat Considerations

This document describes the security controls, assumptions, and known limitations of the patterns implemented in this repository.

The project is an educational and experimental reference for exploring how AI agents can interact with smart contracts under explicit on-chain constraints.

**Core principle: Planner proposes. Executor enforces.**

## General Security Principles

- Off-chain components may prepare and propose actions, but on-chain contracts must enforce critical execution rules.
- Signed Intents should have explicit authorization boundaries.
- Nonces and deadlines help prevent replay and stale execution.
- Spending limits, target restrictions, and emergency controls reduce the impact of unintended actions.
- External calls and state updates must be designed with reentrancy risks in mind.
- Passing tests does not prove that a contract is free from vulnerabilities.

## Pattern 1 — Signed Intent

### Security Controls

- Uses EIP-712 typed structured data for signing Intents.
- Verifies that the signature belongs to the authorized signer.
- Uses nonces to prevent replay of previously executed Intents.
- Uses deadlines to reject expired Intents.

### Known Limitations

- Anyone holding a valid signed Intent may submit it for execution. The relayer is not bound to the signature.
- A compromised signer key can authorize malicious Intents.
- Long deadlines increase the time window in which a signed Intent may be submitted.
- Pattern 1 does not include Pattern 2's target allowlist or daily spending cap.

## Pattern 2 — Bounded Autonomy

### Security Controls

- Restricts execution to administrator-approved target contracts.
- Enforces a daily spending cap for native asset value.
- Includes emergency stop and resume controls.
- Updates spending accounting before making the inherited external execution call.
- Includes adversarial testing for reentrancy against the daily spending limit.

### Known Limitations

- The daily spending cap accounts for `intent.value` only. It does not track ERC-20 transfers or other token exposure.
- Administrative authority is centralized. The current implementation does not require a multisig or timelock.
- The target allowlist restricts which contracts can be called, but does not validate the safety of individual functions or calldata sent to an allowed contract.
- Reentrancy-focused tests cover specific attack scenarios; they do not prove that all possible reentrancy vulnerabilities have been eliminated.
- Further adversarial testing and independent security review are necessary.

## Pattern 3 — Multi-Agent Coordination and Arbitration

### Security Controls

- Requires agents to register before participating.
- Allows registered agents to create proposals.
- Restricts each registered agent to one vote per proposal.
- Uses an arbiter to approve or reject proposals.

### Known Limitations

- There is no quorum or minimum voting threshold.
- The arbiter retains decisive authority over proposal outcomes.
- The implementation should not be considered decentralized consensus.
- Agent registration and voting do not independently guarantee that proposals are correct or safe.

## Operational Security Recommendations

- Never commit private keys, seed phrases, API keys, or other secrets to the repository.
- Use dedicated test accounts for local development and testing.
- Use short Intent deadlines where practical.
- Verify the chain ID, signer, executor address, target address, nonce, and value before signing or submitting an Intent.
- Review target contracts and their callable functions before adding them to an allowlist.
- Monitor execution events and administrative changes.
- Keep administrative credentials secure and consider multisig and timelock controls before any real-world deployment.
- Do not use real funds without independent security review and appropriate hardening.

## Security Status

This repository is an educational and experimental project.

- It has not undergone an independent professional security audit.
- It is not production-ready.
- Passing automated tests does not guarantee the absence of vulnerabilities.
- The documented controls reduce specific risks but do not eliminate all smart contract, key-management, operational, or integration risks.

## Future Security Improvements

Potential improvements include:

- Multisig and timelock-based administration.
- Stronger configuration validation.
- Expanded threat modeling.
- Additional adversarial and invariant testing.
- Improved monitoring and operational safeguards.
- Stronger governance and authorization boundaries.