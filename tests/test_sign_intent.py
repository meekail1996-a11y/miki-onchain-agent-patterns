
import os
import unittest
from unittest.mock import patch

from eth_account import Account
from eth_account.messages import encode_typed_data

from scripts.sign_intent import (
    MAX_UINT256,
    DOMAIN_NAME,
    DOMAIN_VERSION,
    TYPES,
    build_intent,
    positive_int_env,
    sign_intent,
)


class IntentValidationTests(unittest.TestCase):

    def test_build_intent_accepts_valid_input(self):
        intent = build_intent(
            target="0x0000000000000000000000000000000000000001",
            value=0,
            data="0x",
            nonce=0,
            ttl_seconds=300,
        )

        self.assertEqual(
            intent["target"],
            "0x0000000000000000000000000000000000000001",
        )
        self.assertEqual(intent["value"], 0)
        self.assertEqual(intent["data"], "0x")
        self.assertEqual(intent["nonce"], 0)
        self.assertGreater(intent["deadline"], 0)

    def test_rejects_negative_value(self):
        with self.assertRaisesRegex(ValueError, "INTENT_VALUE"):
            build_intent("target", -1, "0x", 0)

    def test_rejects_uint256_overflow(self):
        with self.assertRaisesRegex(ValueError, "INTENT_NONCE"):
            build_intent("target", 0, "0x", MAX_UINT256 + 1)

    def test_rejects_invalid_hex(self):
        with self.assertRaisesRegex(ValueError, "hexadecimal"):
            build_intent("target", 0, "0xzz", 0)

    def test_rejects_missing_required_nonce(self):
        with patch.dict(os.environ, {"INTENT_NONCE": ""}):
            with self.assertRaisesRegex(ValueError, "Missing required"):
                positive_int_env("INTENT_NONCE", allow_zero=True)

    def test_rejects_numeric_env_overflow(self):
        with patch.dict(
            os.environ,
            {"TEST_NUMBER": str(MAX_UINT256 + 1)},
        ):
            with self.assertRaisesRegex(ValueError, "uint256"):
                positive_int_env("TEST_NUMBER")

    def test_sign_intent_recovers_expected_signer(self):
        private_key = "0x" + "11" * 32

        domain = {
            "name": DOMAIN_NAME,
            "version": DOMAIN_VERSION,
            "chainId": 31337,
            "verifyingContract": (
                "0x0000000000000000000000000000000000001234"
            ),
        }

        intent = build_intent(
            target="0x0000000000000000000000000000000000000001",
            value=0,
            data="0x12345678",
            nonce=0,
            ttl_seconds=300,
        )

        signature = sign_intent(private_key, domain, intent)

        encoded = encode_typed_data(domain, TYPES, intent)

        recovered_address = Account.recover_message(
            encoded,
            signature=signature,
        )

        expected_address = Account.from_key(private_key).address

        self.assertEqual(recovered_address, expected_address)


if __name__ == "__main__":
    unittest.main()
