// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Pattern1_PlannerExecutor is EIP712 {
    using ECDSA for bytes32;

    struct Intent {
        address target;
        uint256 value;
        bytes data;
        uint256 nonce;
        uint256 deadline;
    }

    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
    );

    address public immutable agentSigner;
    uint256 public nonce;

    event IntentExecuted(address indexed target, uint256 value, uint256 nonce);

    error IntentExpired();
    error InvalidNonce();
    error InvalidSignature();
    error CallFailed();

    constructor(address _agentSigner) EIP712("Pattern1_PlannerExecutor", "1") {
        agentSigner = _agentSigner;
    }

    function execute(Intent calldata intent, bytes calldata signature) external {
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (intent.nonce != nonce) revert InvalidNonce();

        bytes32 structHash = keccak256(
            abi.encode(
                INTENT_TYPEHASH,
                intent.target,
                intent.value,
                keccak256(intent.data),
                intent.nonce,
                intent.deadline
            )
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        if (digest.recover(signature) != agentSigner) revert InvalidSignature();

        nonce++;

        (bool ok, ) = intent.target.call{value: intent.value}(intent.data);
        if (!ok) revert CallFailed();

        emit IntentExecuted(intent.target, intent.value, intent.nonce);
    }

    receive() external payable {}
}
