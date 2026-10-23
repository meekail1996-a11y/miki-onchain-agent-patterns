# Security Checklist for On-chain Agents

## General Principles

- Never give an agent unlimited control over funds
- Prefer explicit Intents over open-ended permissions
- Always include time bounds (deadlines)
- Use nonces or similar replay protection
- Validate all external calls

## Pattern 1 Specific Risks

- **Private key compromise**: If the `agentSigner` key is leaked, the attacker can execute arbitrary calls
- **Intent front-running**: Someone can submit a valid signed Intent before you do
- **Deadline too long**: Increases the window for misuse if key is compromised
- **Reentrancy**: Be careful with the target contracts you allow

## Recommendations

1. Use a dedicated hot wallet with limited funds for the agentSigner
2. Keep deadlines short (minutes to a few hours)
3. Monitor nonce and executed Intents
4. Consider adding daily/weekly spending limits in future versions
5. Audit any target contracts the agent is allowed to call

## Coming Improvements

- Spending limits
- Allowed target whitelist
- Multi-sig / secondary approval for large actions
- Better monitoring tools
