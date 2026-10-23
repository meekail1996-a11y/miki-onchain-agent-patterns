#!/usr/bin/env python3
"""
Build and sign an EIP-712 Intent for Pattern1_PlannerExecutor.

Required environment variables:
  PRIVATE_KEY       Dedicated signing key (never commit it)
  CHAIN_ID          Chain ID of the network where the executor is deployed
  CONTRACT_ADDRESS  Deployed Pattern1_PlannerExecutor address
  TARGET_ADDRESS    Contract the intent is allowed to call

Optional:
  INTENT_VALUE      Native currency value in wei (default: 0)
  INTENT_DATA       Hex calldata, e.g. 0x (default: 0x)
  INTENT_NONCE      Executor nonce (default: 0; set to the current on-chain nonce)
  INTENT_TTL        Intent lifetime in seconds (default: 300)
  ALLOW_MAINNET_SIGNING Set to 1 to explicitly permit signing for chain ID 1

This script only creates a signature; it does not submit a transaction.
"""

import json
import os
import time

from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import is_address, to_checksum_address


DOMAIN_NAME = "Pattern1_PlannerExecutor"
DOMAIN_VERSION = "1"
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

TYPES = {
    "Intent": [
        {"name": "target", "type": "address"},
        {"name": "value", "type": "uint256"},
        {"name": "data", "type": "bytes"},
        {"name": "nonce", "type": "uint256"},
        {"name": "deadline", "type": "uint256"},
    ]
}


def required_env(name):
    value = os.getenv(name, "").strip()
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def positive_int_env(name, default=None, allow_zero=False):
    raw = os.getenv(name, "")
    if not raw.strip():
        if default is None:
            raise ValueError(f"Missing required environment variable: {name}")
        value = default
    else:
        try:
            value = int(raw, 10)
        except ValueError as exc:
            raise ValueError(f"{name} must be an integer") from exc

    minimum = 0 if allow_zero else 1
    if value < minimum:
        raise ValueError(f"{name} must be {'zero or greater' if allow_zero else 'greater than zero'}")
    return value


def checked_address(name, value):
    if not is_address(value):
        raise ValueError(f"{name} is not a valid Ethereum address")
    address = to_checksum_address(value)
    if address == ZERO_ADDRESS:
        raise ValueError(f"{name} must not be the zero address")
    return address


def build_intent(target, value, data, nonce, ttl_seconds=300):
    if not isinstance(data, str) or not data.startswith("0x"):
        raise ValueError("INTENT_DATA must be hex data beginning with 0x")
    try:
        bytes.fromhex(data[2:])
    except ValueError as exc:
        raise ValueError("INTENT_DATA contains invalid hexadecimal characters") from exc
    if ttl_seconds <= 0:
        raise ValueError("INTENT_TTL must be greater than zero")

    return {
        "target": target,
        "value": value,
        "data": data,
        "nonce": nonce,
        "deadline": int(time.time()) + ttl_seconds,
    }


def sign_intent(private_key, domain, intent):
    encoded = encode_typed_data(domain, TYPES, intent)
    signed = Account.sign_message(encoded, private_key=private_key)
    return signed.signature.hex()


def main():
    private_key = required_env("PRIVATE_KEY")
    try:
        account = Account.from_key(private_key)
    except Exception as exc:
        raise ValueError("PRIVATE_KEY is invalid; provide a 32-byte hex private key") from exc

    chain_id = positive_int_env("CHAIN_ID")
    if chain_id == 1 and os.getenv("ALLOW_MAINNET_SIGNING") != "1":
        raise ValueError(
            "Signing for Ethereum mainnet is disabled by default. "
            "Use a test network, or explicitly set ALLOW_MAINNET_SIGNING=1 only if intended."
        )

    contract_address = checked_address(
        "CONTRACT_ADDRESS", required_env("CONTRACT_ADDRESS")
    )
    target_address = checked_address("TARGET_ADDRESS", required_env("TARGET_ADDRESS"))

    domain = {
        "name": DOMAIN_NAME,
        "version": DOMAIN_VERSION,
        "chainId": chain_id,
        "verifyingContract": contract_address,
    }

    intent = build_intent(
        target=target_address,
        value=positive_int_env("INTENT_VALUE", default=0, allow_zero=True),
        data=os.getenv("INTENT_DATA", "0x").strip(),
        nonce=positive_int_env("INTENT_NONCE", default=0, allow_zero=True),
        ttl_seconds=positive_int_env("INTENT_TTL", default=300),
    )

    print(f"Signer address: {account.address}")
    print(f"Chain ID: {chain_id}")
    print(f"Executor contract: {contract_address}")
    print(f"\nIntent:\n{json.dumps(intent, indent=2)}")
    print(f"\nSignature:\n{sign_intent(private_key, domain, intent)}")
    print("\nReminder: verify the chain ID, executor address, target, and nonce before use.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        raise SystemExit(f"Configuration error: {error}")
