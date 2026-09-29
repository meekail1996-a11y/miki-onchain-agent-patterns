#!/usr/bin/env python3
"""
Sign an Intent for Pattern1_PlannerExecutor.
"""

import json
import time
from eth_account import Account
from eth_account.messages import encode_typed_data

PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
CHAIN_ID = 1
CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000"

DOMAIN = {
    "name": "Pattern1_PlannerExecutor",
    "version": "1",
    "chainId": CHAIN_ID,
    "verifyingContract": CONTRACT_ADDRESS,
}

TYPES = {
    "Intent": [
        {"name": "target", "type": "address"},
        {"name": "value", "type": "uint256"},
        {"name": "data", "type": "bytes"},
        {"name": "nonce", "type": "uint256"},
        {"name": "deadline", "type": "uint256"},
    ]
}

def build_intent(target, value, data, nonce, ttl_seconds=300):
    return {
        "target": target,
        "value": value,
        "data": data,
        "nonce": nonce,
        "deadline": int(time.time()) + ttl_seconds,
    }

def sign_intent(private_key, intent):
    encoded = encode_typed_data(DOMAIN, TYPES, intent)
    signed = Account.sign_message(encoded, private_key=private_key)
    return signed.signature.hex()

def main():
    account = Account.from_key(PRIVATE_KEY)
    print(f"Signer address: {account.address}")

    intent = build_intent(
        target="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        value=0,
        data="0x",
        nonce=0,
    )

    print(f"\nIntent:\n{json.dumps(intent, indent=2)}")
    print(f"\nSignature:\n{sign_intent(PRIVATE_KEY, intent)}")

if __name__ == "__main__":
    main()
