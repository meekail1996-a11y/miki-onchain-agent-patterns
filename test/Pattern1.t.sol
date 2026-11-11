// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern1_PlannerExecutor.sol";

contract Pattern1Test is Test {
    Pattern1_PlannerExecutor executor;
    uint256 constant SIGNER_PK = 0xA11CE;
    address signer;
    address target = address(0xBEEF);

    function setUp() public {
        signer = vm.addr(SIGNER_PK);
        executor = new Pattern1_PlannerExecutor(signer);
    }

    function test_ExecuteValidIntent() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        executor.execute(intent, _sign(intent));
        assertEq(executor.nonce(), 1);
    }

    function test_RevertWhenExpired() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp - 1
            });

        vm.expectRevert();
        executor.execute(intent, _sign(intent));
    }

    function test_RevertWhenWrongNonce() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: 0,
                data: "",
                nonce: 5,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert();
        executor.execute(intent, _sign(intent));
    }

    function test_RevertWhenReplayingUsedIntent() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory signature = _sign(intent);

        executor.execute(intent, signature);

        vm.expectRevert(
            Pattern1_PlannerExecutor.InvalidNonce.selector
        );
        executor.execute(intent, signature);
    }

function test_RevertWhenSignatureIsInvalid() public {
    Pattern1_PlannerExecutor.Intent memory intent =
        Pattern1_PlannerExecutor.Intent({
            target: target,
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

    uint256 wrongPrivateKey = 0xB0B;
    bytes32 digest = keccak256("invalid signature");

    (uint8 v, bytes32 r, bytes32 s) =
        vm.sign(wrongPrivateKey, digest);

    bytes memory invalidSignature = abi.encodePacked(r, s, v);

    vm.expectRevert(
        Pattern1_PlannerExecutor.InvalidSignature.selector
    );

    executor.execute(intent, invalidSignature);
}

    function _sign(
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
                ),
                intent.target,
                intent.value,
                keccak256(intent.data),
                intent.nonce,
                intent.deadline
            )
        );

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("Pattern1_PlannerExecutor"),
                keccak256("1"),
                block.chainid,
                address(executor)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PK, digest);

        return abi.encodePacked(r, s, v);
    }
}
