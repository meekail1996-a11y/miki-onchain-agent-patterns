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
        bounded.emergencyStop(true);

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern2_BoundedAutonomy.ContractPaused.selector
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
        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(attacker.received(), 0.6 ether);

        assertTrue(attacker.reentryAttempted());
        assertFalse(attacker.reentrySucceeded());
    }

    function test_RevertWhenNonAdminAddsTarget() public {
        address unauthorized = makeAddr("unauthorized");
        address newTarget = address(new MockTarget());

        vm.prank(unauthorized);

        vm.expectRevert(
            "Not admin"
        );

        bounded.addTarget(newTarget);
    }

    function test_RevertWhenNonAdminChangesSpendingCap() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);

        vm.expectRevert(
            "Not admin"
        );

        bounded.setSpendingCap(10 ether);
    }

    function test_RevertWhenNonAdminResumesContract() public {
        bounded.emergencyStop(true);

        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);

        vm.expectRevert(
            "Not admin"
        );

        bounded.emergencyStop(false);
    }

    function test_AdminCanResumeContract() public {
        bounded.emergencyStop(true);

        assertTrue(bounded.paused());

        bounded.emergencyStop(false);

        assertFalse(bounded.paused());
    }

    function test_DailySpendingCapResetsOnNewDay() public {
        vm.deal(address(bounded), 2 ether);

        Pattern1_PlannerExecutor.Intent memory firstIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(firstIntent, _signIntent(firstIntent));

        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 1);

        uint256 nextDay =
            (block.timestamp / 1 days + 1) * 1 days;

        vm.warp(nextDay);

        Pattern1_PlannerExecutor.Intent memory secondIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(secondIntent, _signIntent(secondIntent));

        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 2);
        assertEq(
            bounded.lastSpendingResetDay(),
            block.timestamp / 1 days
        );
    }

    function test_MultipleTransactionsCannotExceedDailySpendingCap()
        public
    {
        vm.deal(address(bounded), 2 ether);

        Pattern1_PlannerExecutor.Intent memory firstIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(firstIntent, _signIntent(firstIntent));

        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 1);

        Pattern1_PlannerExecutor.Intent memory secondIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern2_BoundedAutonomy.SpendingCapExceeded.selector
        );

        bounded.execute(secondIntent, _signIntent(secondIntent));

        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 1);
    }

    function test_RevertWhenNonAdminTriggersEmergencyStop() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);

        vm.expectRevert(
            "Not admin"
        );

        bounded.emergencyStop(true);

        assertFalse(bounded.paused());
    }

    function test_RevertWhenNonAdminRemovesTarget() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);

        vm.expectRevert(
            "Not admin"
        );

        bounded.removeTarget(address(attacker));

        assertTrue(bounded.allowedTargets(address(attacker)));
    }

    function test_AdminCanRemoveTarget() public {
        assertTrue(bounded.allowedTargets(address(attacker)));

        bounded.removeTarget(address(attacker));

        assertFalse(bounded.allowedTargets(address(attacker)));
    }

    function test_AdminCanUpdateSpendingCap() public {
        assertEq(bounded.spendingCapPerDay(), 1 ether);

        bounded.setSpendingCap(2 ether);

        assertEq(bounded.spendingCapPerDay(), 2 ether);
    }

    function test_ExecuteAtExactDailySpendingCap() public {
        vm.deal(address(bounded), 1 ether);

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 1 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(intent, _signIntent(intent));

        assertEq(bounded.dailySpent(), 1 ether);
        assertEq(bounded.nonce(), 1);
        assertEq(attacker.received(), 1 ether);
    }

    function test_RevertWhenTargetCallFailsAndRollsBackState()
        public
    {
        RevertingTarget failingTarget = new RevertingTarget();

        bounded.addTarget(address(failingTarget));

        vm.deal(address(bounded), 1 ether);

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(failingTarget),
                value: 0.4 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern1_PlannerExecutor.CallFailed.selector
        );
        bounded.execute(intent, _signIntent(intent));

        assertEq(bounded.dailySpent(), 0);
        assertEq(bounded.nonce(), 0);
        assertEq(address(bounded).balance, 1 ether);
    }

    function test_ReducingSpendingCapBelowSpentAmountBlocksFurtherSpending()
        public
    {
        vm.deal(address(bounded), 1 ether);

        Pattern1_PlannerExecutor.Intent memory firstIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.6 ether,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bounded.execute(firstIntent, _signIntent(firstIntent));

        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 1);

        // The admin may lower the cap below the amount already spent today.
        bounded.setSpendingCap(0.5 ether);

        assertEq(bounded.spendingCapPerDay(), 0.5 ether);
        assertEq(bounded.dailySpent(), 0.6 ether);

        Pattern1_PlannerExecutor.Intent memory secondIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0.01 ether,
                data: "",
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });

        vm.expectRevert(
            Pattern2_BoundedAutonomy.SpendingCapExceeded.selector
        );

        bounded.execute(secondIntent, _signIntent(secondIntent));

        // A rejected execution must not change the spending total or nonce.
        assertEq(bounded.dailySpent(), 0.6 ether);
        assertEq(bounded.nonce(), 1);
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

contract RevertingTarget {
    error TargetRejected();

    fallback() external payable {
        revert TargetRejected();
    }

    receive() external payable {
        revert TargetRejected();
    }
}
