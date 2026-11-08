// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern1_PlannerExecutor.sol";

contract BadTarget {
    function someOtherFunction() public pure returns (uint256) {
        return 42;
    }
}

contract SecurityTests is Test {
    Pattern1_PlannerExecutor executor;
    address signer;
    uint256 signerPrivateKey;

    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
        executor = new Pattern1_PlannerExecutor(signer);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Pattern1_PlannerExecutor")),
                keccak256(bytes("1")),
                block.chainid,
                address(executor)
            )
        );
    }

    function _signIntent(
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes memory) {
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
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_RevertWhenSignatureIsInvalid() public {
        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: address(this),
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        // یک کلید خصوصی جعلی (نه signer اصلی)
        (, uint256 fakeKey) = makeAddrAndKey("fakeSigner");

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
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domainSeparator(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(fakeKey, digest);
        bytes memory badSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(Pattern1_PlannerExecutor.InvalidSignature.selector);
        executor.execute(intent, badSignature);
    }

    function test_RevertWhenTargetCallFails() public {
        BadTarget badTarget = new BadTarget();

        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: address(badTarget),
            value: 0,
            data: hex"12345678", // فراخوانی تابع ناموجود
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(Pattern1_PlannerExecutor.CallFailed.selector);
        executor.execute(intent, signature);
    }

    function test_RevertWhenDeadlinePassed() public {
        vm.warp(block.timestamp + 2 hours);

        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: address(this),
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp - 1
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(Pattern1_PlannerExecutor.IntentExpired.selector);
        executor.execute(intent, signature);
    }
}