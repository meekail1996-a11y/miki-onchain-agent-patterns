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
    error InvalidAgentSigner();

    constructor(address _agentSigner) EIP712("Pattern1_PlannerExecutor", "1") {
        if (_agentSigner == address(0)) revert InvalidAgentSigner();
        agentSigner = _agentSigner;
    }

    // تغییر: calldata به memory
    function execute(Intent memory intent, bytes memory signature) public virtual {
        _executeIntent(intent, signature);
    }

    function _intentDigest(Intent memory intent) internal view returns (bytes32) {
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

        return _hashTypedDataV4(structHash);
    }

    function _verifyIntentSignature(
        Intent memory intent,
        bytes memory signature
    ) internal view {
        (address recovered, ECDSA.RecoverError err, ) =
            _intentDigest(intent).tryRecover(signature);

        if (err != ECDSA.RecoverError.NoError || recovered != agentSigner) {
            revert InvalidSignature();
        }
    }

    function _executeIntent(
        Intent memory intent,
        bytes memory signature
    ) internal {
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (intent.nonce != nonce) revert InvalidNonce();

        _verifyIntentSignature(intent, signature);

        nonce++;

        emit IntentExecuted(intent.target, intent.value, intent.nonce);

        (bool ok, ) = intent.target.call{value: intent.value}(intent.data);
        if (!ok) revert CallFailed();
    }

    receive() external payable {}
}