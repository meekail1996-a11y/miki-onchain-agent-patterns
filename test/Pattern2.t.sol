
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";

contract Pattern2Test is Test {
    Pattern2_BoundedAutonomy bounded;

    address admin;
    address signer;
    uint256 signerPrivateKey;
    ReentrancyAttacker attacker;

    function setUp() public {
        admin = address(this);

        (signer, signerPrivateKey) = makeAddrAndKey("signer");

        bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);

        attacker = new ReentrancyAttacker(address(bounded));

        bounded.addTarget(address(attacker));
    }

    function _signIntent(
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
                keccak256(bytes("Pattern1_PlannerExecutor")),
                keccak256(bytes("1")),
                block.chainid,
                address(bounded)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signerPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function test_ExecuteWithAllowlistedTarget() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(intent, _signIntent(intent));
    }

    function test_RevertWhenTargetNotAllowed() public {
        address badTarget = address(new MockTarget());

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: badTarget,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern2_BoundedAutonomy.TargetNotAllowed.selector
        );

        bounded.execute(intent, _signIntent(intent));
    }

    function test_RevertWhenSpendingCapExceeded() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 2 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        vm.deal(address(bounded), 5 ether);

        vm.expectRevert(
            Pattern2_BoundedAutonomy.SpendingCapExceeded.selector
        );

        bounded.execute(intent, _signIntent(intent));
    }

    function test_RevertWhenEmergencyStopped() public {
        bounded.emergencyStop();

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern2_BoundedAutonomy.EmergencyStopActive.selector
        );

        bounded.execute(intent, _signIntent(intent));
    }

    function test_ReentrancyCannotExceedDailySpendingCap() public {
        vm.deal(address(bounded), 2 ether);

        Pattern1_PlannerExecutor.Intent memory secondIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });

        attacker.configure(
            secondIntent,
            _signIntent(secondIntent)
        );

        Pattern1_PlannerExecutor.Intent memory firstIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(
            firstIntent,
            _signIntent(firstIntent)
        );

        assertEq(bounded.nonce(), 1);
        assertEq(bounded.spentToday(), 0.6 ether);
        assertEq(attacker.received(), 0.6 ether);

        assertTrue(attacker.reentryAttempted());
        assertFalse(attacker.reentrySucceeded());
    }
}

contract ReentrancyAttacker {
    Pattern2_BoundedAutonomy public immutable bounded;

    Pattern1_PlannerExecutor.Intent private secondIntent;
    bytes private secondSignature;

    bool private attackEnabled;
    bool private attacked;

    bool public reentryAttempted;
    bool public reentrySucceeded;

    uint256 public received;

    constructor(address _bounded) {
        bounded = Pattern2_BoundedAutonomy(payable(_bounded));
    }

    function configure(
        Pattern1_PlannerExecutor.Intent memory _intent,
        bytes memory _signature
    ) external {
        secondIntent = _intent;
        secondSignature = _signature;
        attackEnabled = true;
        attacked = false;
        reentryAttempted = false;
        reentrySucceeded = false;
    }

    receive() external payable {
        received += msg.value;

        if (attackEnabled && !attacked) {
            attacked = true;
            reentryAttempted = true;

            (bool success, ) = address(bounded).call(
                abi.encodeWithSelector(
                    bounded.execute.selector,
                    secondIntent,
                    secondSignature
                )
            );

            reentrySucceeded = success;
        }
    }
}

contract MockTarget {
    receive() external payable {}
}
