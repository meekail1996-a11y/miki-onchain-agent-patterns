# On-chain Agent Patterns

**A security-first reference implementation for AI agents that interact with smart contracts.**

This project explores a simple but important boundary: an AI system can propose an action, but it should not have unrestricted authority to execute it. The Planner reasons about a task; the Executor enforces the rules on-chain.

> **Core principle:** Trust the Planner to propose. Trust the Executor to enforce. Keep signing authority separate from open-ended model output.

[Architecture](#architecture) · [Patterns](#patterns) · [Security Model](#security-model) · [Quick Start](#quick-start) · [Testing](#testing) · [Roadmap](#roadmap)

---

## Why this project exists

Connecting an LLM directly to a wallet creates a dangerous coupling between reasoning and financial authority. A model can misunderstand a prompt, produce unexpected calldata, or be manipulated by untrusted input.

A safer design introduces a constrained execution boundary. The Planner creates a structured **Intent**. A signer authorizes that exact intent. The smart-contract Executor validates the authorization and applies contract-level checks before making the call.

This repository is a learning-oriented, evolving reference implementation—not a production audit or a guarantee of safety.

---

## Architecture
