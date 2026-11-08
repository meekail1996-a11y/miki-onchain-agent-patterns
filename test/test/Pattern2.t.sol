// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../contracts/Pattern2_BoundedAutonomy.sol";

contract Pattern2Test is Test {
    Pattern2_BoundedAutonomy bounded;
    address admin;
    address signer;
    uint256 signerPrivateKey;
    address allowedTarget;

    function setUp() public {
        admin = address(this);
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
        allowedTarget = address(new MockTarget());

        bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);

        // افزودن هدف مجاز به allowlist
        bounded.addTarget(allowedTarget);
    }

    function _signIntent(
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"),
                intent.target,
                intent.value,
                keccak256(intent.data),
                intent.nonce,
                intent.deadline
            )
        );
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Pattern1_PlannerExecutor")),
                keccak256(bytes("1")),
                block.chainid,
                address(bounded)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_ExecuteWithAllowlistedTarget() public {
        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: allowedTarget,
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signIntent(intent);

        // فقط بررسی می‌کنیم که اجرا بدون خطا انجام می‌شه
        bounded.execute(intent, signature);
    }

    function test_RevertWhenTargetNotAllowed() public {
        address badTarget = address(new MockTarget());

        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: badTarget,
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(Pattern2_BoundedAutonomy.TargetNotAllowed.selector);
        bounded.execute(intent, signature);
    }

    function test_RevertWhenSpendingCapExceeded() public {
        // سقف ۱ اتر است
        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: allowedTarget,
            value: 2 ether,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signIntent(intent);
        vm.deal(address(bounded), 5 ether); // به قرارداد ارز می‌دیم

        vm.expectRevert(Pattern2_BoundedAutonomy.SpendingCapExceeded.selector);
        bounded.execute(intent, signature);
    }

    function test_RevertWhenEmergencyStopped() public {
        bounded.emergencyStop();

        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: allowedTarget,
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(Pattern2_BoundedAutonomy.EmergencyStopActive.selector);
        bounded.execute(intent, signature);
    }
}

contract MockTarget {
    receive() external payable {}
}