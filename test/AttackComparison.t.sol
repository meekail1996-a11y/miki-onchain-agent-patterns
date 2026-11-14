// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern1_PlannerExecutor.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";
import "../contracts/Pattern3_MultiAgentArbitration.sol";

/// One threat, three patterns: the planner key is stolen.
///
/// Pattern 1 trusts the signature alone, so the key is the whole security model.
/// Pattern 2 keeps the same signature check but bounds what a stolen key can do.
/// Pattern 3 keeps it and additionally requires a second agent to agree.
///
/// These tests exist to make the difference executable rather than asserted: the
/// same attacker, the same 5 ETH balance, the same intent shape.
contract AttackComparisonTest is Test {
    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
    );

    uint256 internal plannerKey;
    address internal planner;
    address internal attacker;
    address internal treasury;
    address internal arbiter;

    function setUp() public {
        // The planner key is what the attacker holds: everything below is signed
        // with it, so every signature verifies.
        (planner, plannerKey) = makeAddrAndKey("compromised-planner");
        attacker = makeAddr("attacker");
        treasury = makeAddr("treasury");
        arbiter = makeAddr("arbiter");
    }

    // ---------------------------------------------------------------- helpers

    function _domain(address verifying) internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("Pattern1_PlannerExecutor")),
                    keccak256(bytes("1")),
                    block.chainid,
                    verifying
                )
            );
    }

    function _digest(
        address verifying,
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes32) {
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

        return keccak256(abi.encodePacked("\x19\x01", _domain(verifying), structHash));
    }

    function _sign(
        address verifying,
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            plannerKey,
            _digest(verifying, intent)
        );
        return abi.encodePacked(r, s, v);
    }

    function _intent(
        address target,
        uint256 value,
        uint256 nonce
    ) internal view returns (Pattern1_PlannerExecutor.Intent memory) {
        return
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: value,
                data: "",
                nonce: nonce,
                deadline: block.timestamp + 1 hours
            });
    }

    // ------------------------------------------------------------ Pattern 1

    /// Signature-only execution: whoever holds the key holds the balance.
    function test_StolenPlannerKey_DrainsPattern1() public {
        Pattern1_PlannerExecutor planner1 = new Pattern1_PlannerExecutor(planner);
        vm.deal(address(planner1), 5 ether);

        Pattern1_PlannerExecutor.Intent memory theft = _intent(
            attacker,
            5 ether,
            0
        );

        planner1.execute(theft, _sign(address(planner1), theft));

        assertEq(attacker.balance, 5 ether, "attacker received the whole balance");
        assertEq(address(planner1).balance, 0, "executor is empty");
        assertEq(planner1.nonce(), 1, "the legitimate nonce was consumed");
    }

    // ------------------------------------------------------------ Pattern 2

    /// The same key cannot send funds to a target the admin never allowlisted.
    /// It cannot send more than the daily cap either, so the loss is bounded even
    /// though the signature is perfectly valid.
    function test_StolenPlannerKey_IsBoundedInPattern2() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(
            planner,
            1 ether
        );
        vm.deal(address(bounded), 5 ether);
        bounded.addTarget(treasury);

        Pattern1_PlannerExecutor.Intent memory toAttacker = _intent(
            attacker,
            1 ether,
            0
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.TargetNotAllowed.selector);
        bounded.execute(toAttacker, _sign(address(bounded), toAttacker));

        Pattern1_PlannerExecutor.Intent memory overCap = _intent(
            treasury,
            5 ether,
            0
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.SpendingCapExceeded.selector);
        bounded.execute(overCap, _sign(address(bounded), overCap));

        Pattern1_PlannerExecutor.Intent memory withinCap = _intent(
            treasury,
            1 ether,
            0
        );
        bounded.execute(withinCap, _sign(address(bounded), withinCap));

        assertEq(attacker.balance, 0, "attacker received nothing");
        assertEq(treasury.balance, 1 ether, "stolen key moved only the daily cap");
        assertEq(address(bounded).balance, 4 ether, "the rest stayed in the contract");
    }

    /// The cap is a rate limit, not a lock: the attacker repeats the maximum
    /// allowed transfer on each new day and drains the contract over time. This
    /// is the honest boundary of Pattern 2 and the reason it is a mitigation,
    /// not a solution.
    function test_StolenPlannerKey_DrainsPattern2OverDays() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(
            planner,
            1 ether
        );
        vm.deal(address(bounded), 3 ether);
        bounded.addTarget(treasury);

        for (uint256 day = 0; day < 3; day++) {
            Pattern1_PlannerExecutor.Intent memory daily = _intent(
                treasury,
                1 ether,
                day
            );
            bounded.execute(daily, _sign(address(bounded), daily));

            vm.warp(block.timestamp + 1 days);
        }

        assertEq(treasury.balance, 3 ether, "the cap only slowed the drain down");
        assertEq(address(bounded).balance, 0, "the contract is empty after three days");
    }

    // ------------------------------------------------------------ Pattern 3

    /// Even a valid, correctly signed Intent cannot execute on one agent's word:
    /// the proposal needs a second approval, and the arbiter will not resolve it
    /// below quorum.
    function test_StolenPlannerKey_CannotExecuteAloneInPattern3() public {
        Pattern3_MultiAgentArbitration arbitration = new Pattern3_MultiAgentArbitration(
            planner,
            arbiter
        );
        vm.deal(address(arbitration), 5 ether);

        address secondAgent = makeAddr("second-agent");
        address thirdAgent = makeAddr("third-agent");
        vm.startPrank(arbiter);
        arbitration.addAgent(planner); // the compromised key is a legitimate agent
        arbitration.addAgent(secondAgent);
        arbitration.addAgent(thirdAgent);
        vm.stopPrank();

        Pattern1_PlannerExecutor.Intent memory theft = _intent(
            attacker,
            5 ether,
            0
        );

        vm.prank(planner);
        uint256 proposalId = arbitration.propose(theft, _sign(address(arbitration), theft));

        // The attacker's own vote is not enough: three agents means a quorum of two.
        vm.prank(planner);
        arbitration.vote(proposalId, true);

        vm.prank(arbiter);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InsufficientVotes.selector
        );
        arbitration.resolveArbitration(proposalId, true);

        assertEq(attacker.balance, 0, "nothing moved without a second approval");
        assertEq(address(arbitration).balance, 5 ether, "balance is intact");
        assertEq(arbitration.nonce(), 0, "no nonce was consumed");

        // Direct execution is disabled outright, so there is no shortcut.
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.DirectExecutionDisabled.selector
        );
        arbitration.execute(theft, _sign(address(arbitration), theft));
    }
}
