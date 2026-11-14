// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern1_PlannerExecutor.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";
import "../contracts/Pattern3_MultiAgentArbitration.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ReviewReceiver {
    uint256 public calls;

    receive() external payable {
        calls++;
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Pins guarantees that docs/security.md claims but the existing suites
/// did not exercise: signature malleability, cross-chain replay, the inclusive
/// deadline boundary, expired-proposal recovery, nonce squatting, removed-agent
/// voting, and the documented ERC-20 blind spot of the native spending cap.
contract SecurityReviewTest is Test {
    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
    );

    uint256 private constant SECP256K1_N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    address private signer;
    uint256 private signerKey;

    function setUp() public {
        (signer, signerKey) = makeAddrAndKey("reviewSigner");
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, _digest(verifying, intent));
        return abi.encodePacked(r, s, v);
    }

    function _intent(
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce,
        uint256 deadline
    ) internal pure returns (Pattern1_PlannerExecutor.Intent memory) {
        return
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: value,
                data: data,
                nonce: nonce,
                deadline: deadline
            });
    }

    // ------------------------------------------------------- Pattern 1 checks

    /// ECDSA signatures are malleable: (r, s, v) and (r, n-s, v^1) are both
    /// valid for the same message. tryRecover must reject the high-s form, or a
    /// submitted Intent could be mutated while remaining "the same" signature.
    function test_RejectsMalleableHighSSignature() public {
        ReviewReceiver target = new ReviewReceiver();
        Pattern1_PlannerExecutor executor = new Pattern1_PlannerExecutor(signer);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            _digest(address(executor), intent)
        );

        bytes memory malleable = abi.encodePacked(
            r,
            bytes32(SECP256K1_N - uint256(s)),
            v == 27 ? uint8(28) : uint8(27)
        );

        vm.expectRevert(Pattern1_PlannerExecutor.InvalidSignature.selector);
        executor.execute(intent, malleable);
    }

    /// The EIP-712 domain binds chainId, so a signature produced on one chain
    /// must not authorise the same Intent on another.
    function test_RejectsSignatureFromAnotherChain() public {
        ReviewReceiver target = new ReviewReceiver();
        Pattern1_PlannerExecutor executor = new Pattern1_PlannerExecutor(signer);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        bytes memory signature = _sign(address(executor), intent);

        vm.chainId(block.chainid + 1);

        vm.expectRevert(Pattern1_PlannerExecutor.InvalidSignature.selector);
        executor.execute(intent, signature);
    }

    /// The deadline check is `block.timestamp > intent.deadline`, so the exact
    /// deadline second is still valid and one second later is not.
    function test_DeadlineBoundaryIsInclusive() public {
        ReviewReceiver target = new ReviewReceiver();
        Pattern1_PlannerExecutor executor = new Pattern1_PlannerExecutor(signer);

        uint256 deadline = block.timestamp + 10;

        Pattern1_PlannerExecutor.Intent memory atDeadline = _intent(
            address(target),
            0,
            "",
            0,
            deadline
        );

        vm.warp(deadline);
        executor.execute(atDeadline, _sign(address(executor), atDeadline));
        assertEq(target.calls(), 1, "intent at the exact deadline must execute");

        Pattern1_PlannerExecutor.Intent memory pastDeadline = _intent(
            address(target),
            0,
            "",
            1,
            deadline
        );

        vm.warp(deadline + 1);
        vm.expectRevert(Pattern1_PlannerExecutor.IntentExpired.selector);
        executor.execute(pastDeadline, _sign(address(executor), pastDeadline));
    }

    // ------------------------------------------------------- Pattern 2 checks

    /// Documented limitation, made executable: the cap only counts native value,
    /// so an allowed token contract can be drained of tokens at zero cap cost.
    function test_TokenTransfersAreNotBoundedByTheNativeCap() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();

        token.mint(address(bounded), 1_000e18);

        bounded.addTarget(address(token));

        uint256 capBefore = bounded.spendingCapPerDay();

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            abi.encodeCall(ERC20.transfer, (address(this), 1_000e18)),
            0,
            block.timestamp + 1 hours
        );

        bounded.execute(intent, _sign(address(bounded), intent));

        assertEq(token.balanceOf(address(this)), 1_000e18, "tokens moved");
        assertEq(bounded.dailySpent(), 0, "native accounting untouched");
        assertEq(bounded.spendingCapPerDay(), capBefore, "cap unchanged");
    }

    // ------------------------------------------------------- Pattern 3 checks

    function _deployArbitration()
        internal
        returns (Pattern3_MultiAgentArbitration arbitration, address arbiter)
    {
        arbiter = makeAddr("arbiter");
        arbitration = new Pattern3_MultiAgentArbitration(signer, arbiter);
    }

    function _voteToQuorum(
        Pattern3_MultiAgentArbitration arbitration,
        uint256 proposalId,
        address[] memory agents
    ) internal {
        for (uint256 i = 0; i < agents.length; i++) {
            vm.prank(agents[i]);
            arbitration.vote(proposalId, true);
        }
    }

    /// An Intent can pass the deadline check at proposal time and expire before
    /// resolution. Approval must then revert, and rejecting must still be
    /// possible so the reserved nonce is released.
    function test_ExpiredProposalCannotExecuteButCanBeRejected() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address agent = makeAddr("agent");
        vm.prank(arbiter);
        arbitration.addAgent(agent);

        ReviewReceiver target = new ReviewReceiver();

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        vm.prank(agent);
        uint256 proposalId = arbitration.propose(
            intent,
            _sign(address(arbitration), intent)
        );

        address[] memory agents = new address[](1);
        agents[0] = agent;
        _voteToQuorum(arbitration, proposalId, agents);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(arbiter);
        vm.expectRevert(Pattern1_PlannerExecutor.IntentExpired.selector);
        arbitration.resolveArbitration(proposalId, true);

        assertTrue(arbitration.nonceReserved(0), "nonce stays reserved while pending");

        vm.prank(arbiter);
        arbitration.resolveArbitration(proposalId, false);

        assertFalse(arbitration.nonceReserved(0), "rejection releases the nonce");
        assertEq(arbitration.nonce(), 0, "executor nonce never advanced");
    }

    /// A resident proposal on the current nonce blocks every other Intent with
    /// that nonce; only an arbiter rejection frees it. This is the documented
    /// arbiter-dependent liveness property.
    function test_SquattedNonceStallsPipelineUntilArbiterRejects() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address squatter = makeAddr("squatter");
        address competitor = makeAddr("competitor");

        vm.startPrank(arbiter);
        arbitration.addAgent(squatter);
        arbitration.addAgent(competitor);
        vm.stopPrank();

        ReviewReceiver firstTarget = new ReviewReceiver();
        ReviewReceiver secondTarget = new ReviewReceiver();

        Pattern1_PlannerExecutor.Intent memory squat = _intent(
            address(firstTarget),
            0,
            "",
            0,
            block.timestamp + 1 days
        );

        vm.prank(squatter);
        uint256 squattedId = arbitration.propose(squat, _sign(address(arbitration), squat));

        Pattern1_PlannerExecutor.Intent memory competing = _intent(
            address(secondTarget),
            0,
            "",
            0,
            block.timestamp + 1 days
        );

        vm.prank(competitor);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.NonceAlreadyProposed.selector
        );
        arbitration.propose(competing, _sign(address(arbitration), competing));

        vm.prank(arbiter);
        arbitration.resolveArbitration(squattedId, false);

        vm.prank(competitor);
        uint256 recoveredId = arbitration.propose(
            competing,
            _sign(address(arbitration), competing)
        );

        assertEq(recoveredId, squattedId + 1, "nonce is reusable after rejection");

        // Both registered agents are needed: quorum is agentCount / 2 + 1 = 2.
        address[] memory agents = new address[](2);
        agents[0] = competitor;
        agents[1] = squatter;
        _voteToQuorum(arbitration, recoveredId, agents);

        vm.prank(arbiter);
        arbitration.resolveArbitration(recoveredId, true);

        assertEq(secondTarget.calls(), 1, "queued intent executes after release");
        assertEq(arbitration.nonce(), 1, "nonce advances exactly once");
    }

    /// Removal blocks future votes even for an agent that was registered when
    /// the proposal was created.
    function test_RemovedAgentCannotVoteOnExistingProposal() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address removed = makeAddr("removedAgent");
        address remaining = makeAddr("remainingAgent");

        vm.startPrank(arbiter);
        arbitration.addAgent(removed);
        arbitration.addAgent(remaining);
        vm.stopPrank();

        ReviewReceiver target = new ReviewReceiver();

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        vm.prank(remaining);
        uint256 proposalId = arbitration.propose(
            intent,
            _sign(address(arbitration), intent)
        );

        vm.prank(arbiter);
        arbitration.removeAgent(removed);

        vm.prank(removed);
        vm.expectRevert(Pattern3_MultiAgentArbitration.NotAgent.selector);
        arbitration.vote(proposalId, true);
    }
}
