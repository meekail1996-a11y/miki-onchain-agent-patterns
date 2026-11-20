// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern1_PlannerExecutor.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";
import "../contracts/Pattern3_MultiAgentArbitration.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

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

contract PermitMockToken is ERC20, ERC20Permit {
    constructor() ERC20("Permit Mock", "PMCK") ERC20Permit("Permit Mock") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// A spender that pulls with `transferFrom`, the shape a router, an aggregator or a
/// Permit2-style contract has: it needs an allowance granted beforehand, and it can spend
/// it in a transaction the executor never runs.
contract PullRouter {
    function pull(ERC20 token, address from, uint256 amount) external {
        token.transferFrom(from, address(this), amount);
    }
}

/// Takes `take` and hands back `give` inside the same call, so the gross outflow and the
/// net decrease of the caller's balance differ by construction.
contract RebateRouter {
    function run(ERC20 token, uint256 take, uint256 give) external {
        token.transferFrom(msg.sender, address(this), take);
        token.transfer(msg.sender, give);
    }
}

/// @notice Pins guarantees that docs/security.md claims but the existing suites
/// did not exercise: signature malleability, cross-chain replay, the inclusive
/// deadline boundary, expired-proposal recovery, nonce squatting, removed-agent
/// voting, the ERC-20 blind spot that the metered path closes, the refusal of `approve` on a
/// registered token, an allowance that exists before the policy is relied on, and the absence
/// of ERC-1271 in the executor.
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

    /// The blind spot the native cap always had, closed for a registered token: the whole
    /// balance cannot leave in one call, and a transfer within the token's own budget is
    /// charged to the token rather than to the native cap. This test used to assert the
    /// opposite — tokens moving at zero cap cost — and is the case the metered path replaces.
    function test_TokenTransfersAreBoundedByTheirOwnCap() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();

        token.mint(address(bounded), 1_000e18);

        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        uint256 capBefore = bounded.spendingCapPerDay();

        Pattern1_PlannerExecutor.Intent memory drain = _intent(
            address(token),
            0,
            abi.encodeCall(ERC20.transfer, (address(this), 1_000e18)),
            0,
            block.timestamp + 1 hours
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCapExceeded.selector);
        bounded.execute(drain, _sign(address(bounded), drain));

        assertEq(token.balanceOf(address(this)), 0, "the balance cannot leave in one call");
        assertEq(token.balanceOf(address(bounded)), 1_000e18, "nothing moved");
        assertEq(bounded.dailySpent(), 0, "native accounting untouched");
        assertEq(bounded.spendingCapPerDay(), capBefore, "the native cap is a separate budget");

        Pattern1_PlannerExecutor.Intent memory within = _intent(
            address(token),
            0,
            abi.encodeCall(ERC20.transfer, (address(this), 100e18)),
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(within, _sign(address(bounded), within));

        assertEq(token.balanceOf(address(this)), 100e18, "the registered budget is spendable");
        assertEq(bounded.tokenSpentToday(address(token)), 100e18, "charged to the token");
        assertEq(bounded.dailySpent(), 0, "still no native charge");
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

    // ------------------------------------------- coverage-gap scenarios

    /// Scenario 1: the executor accepts direct funding. `receive` exists because
    /// Intents may carry native value, so a deployment has to be funded somehow.
    function test_ReceiveAcceptsDirectFunding() public {
        Pattern1_PlannerExecutor executor = new Pattern1_PlannerExecutor(signer);

        vm.deal(address(this), 1 ether);
        assertEq(address(executor).balance, 0, "starts empty");

        (bool ok, ) = address(executor).call{value: 1 ether}("");

        assertTrue(ok, "direct transfer must succeed");
        assertEq(address(executor).balance, 1 ether, "executor is funded");
    }

    /// Scenario 2: a negative vote is recorded as a rejection, not as an approval.
    function test_RejectionVoteIncrementsRejections() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address voter = makeAddr("negativeVoter");
        vm.prank(arbiter);
        arbitration.addAgent(voter);

        ReviewReceiver target = new ReviewReceiver();
        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        vm.prank(voter);
        uint256 proposalId = arbitration.propose(
            intent,
            _sign(address(arbitration), intent)
        );

        vm.prank(voter);
        arbitration.vote(proposalId, false);

        (
            ,
            ,
            ,
            uint256 approvals,
            uint256 rejections,
            uint256 quorum,

        ) = arbitration.proposals(proposalId);

        assertEq(approvals, 0, "no approval recorded");
        assertEq(rejections, 1, "the negative vote is a rejection");
        assertEq(quorum, 1, "quorum is unaffected by votes");
    }

    /// Scenario 3: an executed proposal cannot be resolved a second time, so a
    /// single approval can never execute the same Intent twice.
    function test_RevertWhenResolvingExecutedProposal() public {
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

        vm.prank(arbiter);
        arbitration.resolveArbitration(proposalId, true);

        vm.prank(arbiter);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.ProposalAlreadyExecuted.selector
        );
        arbitration.resolveArbitration(proposalId, true);

        assertEq(target.calls(), 1, "executed exactly once");
    }

    /// Scenario 4: rejection is terminal for the arbiter too, not only for voters.
    function test_RevertWhenResolvingRejectedProposal() public {
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

        vm.prank(arbiter);
        arbitration.resolveArbitration(proposalId, false);

        vm.prank(arbiter);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.ProposalNotPending.selector
        );
        arbitration.resolveArbitration(proposalId, true);

        (
            ,
            ,
            ,
            ,
            ,
            ,
            Pattern3_MultiAgentArbitration.ProposalStatus status
        ) = arbitration.proposals(proposalId);

        assertEq(
            uint256(status),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Rejected),
            "rejection stays terminal after the failed resolve"
        );
        assertEq(target.calls(), 0, "rejected intent never executed");
        assertEq(arbitration.nonce(), 0, "executor nonce never advanced");
        assertFalse(arbitration.nonceReserved(0), "nonce stayed released");
    }

    /// Scenario 5: a zero-address signer would make every signature invalid while
    /// failing open in reviews, so the constructor rejects it.
    function test_RevertWhenAgentSignerIsZero() public {
        vm.expectRevert(Pattern1_PlannerExecutor.InvalidAgentSigner.selector);
        new Pattern1_PlannerExecutor(address(0));
    }

    /// Scenario 6: adding the zero address to the allowlist would authorise a
    /// target that cannot receive a meaningful call.
    function test_RevertWhenAddingZeroAddressTarget() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(
            signer,
            1 ether
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.InvalidTarget.selector);
        bounded.addTarget(address(0));
    }

    /// Scenario 7: without an arbiter nobody can resolve a proposal, so a
    /// zero-address arbiter is rejected at deployment.
    function test_RevertWhenArbiterIsZero() public {
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InvalidArbiter.selector
        );
        new Pattern3_MultiAgentArbitration(signer, address(0));
    }

    // ------------------------------------- combined-state interactions

    /// Rejections and approvals are counted independently: a proposal that reaches
    /// its quorum executes even when other agents voted against it.
    function test_RejectionsDoNotBlockExecutionAtQuorum() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address a1 = makeAddr("a1");
        address a2 = makeAddr("a2");
        address a3 = makeAddr("a3");

        vm.startPrank(arbiter);
        arbitration.addAgent(a1);
        arbitration.addAgent(a2);
        arbitration.addAgent(a3);
        vm.stopPrank();

        ReviewReceiver target = new ReviewReceiver();
        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(target),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        vm.prank(a1);
        uint256 proposalId = arbitration.propose(
            intent,
            _sign(address(arbitration), intent)
        );

        vm.prank(a1);
        arbitration.vote(proposalId, true);
        vm.prank(a2);
        arbitration.vote(proposalId, false);
        vm.prank(a3);
        arbitration.vote(proposalId, true);

        (
            ,
            ,
            ,
            uint256 approvals,
            uint256 rejections,
            uint256 quorum,

        ) = arbitration.proposals(proposalId);

        assertEq(quorum, 2, "strict majority of three agents");
        assertEq(approvals, 2, "two approvals");
        assertEq(rejections, 1, "one rejection is still recorded");

        vm.prank(arbiter);
        arbitration.resolveArbitration(proposalId, true);

        assertEq(target.calls(), 1, "quorum wins over the single rejection");
        assertEq(arbitration.nonce(), 1, "nonce advanced once");
    }

    /// A proposal for a future nonce can wait beside the current one and still
    /// execute once the executor nonce reaches it.
    function test_QueuedFutureNonceExecutesAfterEarlierIntent() public {
        (
            Pattern3_MultiAgentArbitration arbitration,
            address arbiter
        ) = _deployArbitration();

        address agent = makeAddr("agent");
        vm.prank(arbiter);
        arbitration.addAgent(agent);

        ReviewReceiver first = new ReviewReceiver();
        ReviewReceiver second = new ReviewReceiver();

        Pattern1_PlannerExecutor.Intent memory intentOne = _intent(
            address(second),
            0,
            "",
            1,
            block.timestamp + 1 hours
        );
        Pattern1_PlannerExecutor.Intent memory intentZero = _intent(
            address(first),
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        address[] memory agents = new address[](1);
        agents[0] = agent;

        // Queue the future nonce first: it is accepted but cannot execute yet.
        vm.prank(agent);
        uint256 queuedId = arbitration.propose(
            intentOne,
            _sign(address(arbitration), intentOne)
        );

        // Resolution checks quorum before the nonce, so the queued proposal needs
        // its votes first; only then does the stale-nonce rejection surface.
        _voteToQuorum(arbitration, queuedId, agents);
        vm.prank(arbiter);
        vm.expectRevert(Pattern1_PlannerExecutor.InvalidNonce.selector);
        arbitration.resolveArbitration(queuedId, true);

        vm.prank(agent);
        uint256 currentId = arbitration.propose(
            intentZero,
            _sign(address(arbitration), intentZero)
        );

        _voteToQuorum(arbitration, currentId, agents);
        vm.prank(arbiter);
        arbitration.resolveArbitration(currentId, true);

        assertEq(first.calls(), 1, "nonce 0 executed first");
        assertEq(arbitration.nonce(), 1, "nonce moved to 1");
        assertEq(second.calls(), 0, "queued intent still waiting");

        // The queued proposal kept its votes and now matches the executor nonce.
        vm.prank(arbiter);
        arbitration.resolveArbitration(queuedId, true);

        assertEq(second.calls(), 1, "queued intent executed after the nonce caught up");
        assertEq(arbitration.nonce(), 2, "nonce advanced once per execution");
    }

    /// Once an Intent has executed, the same signed payload cannot be proposed
    /// again: the executor nonce has moved past it.
    function test_ReplayAfterExecutionRevertsOnNonce() public {
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

        bytes memory signature = _sign(address(arbitration), intent);

        vm.prank(agent);
        uint256 proposalId = arbitration.propose(intent, signature);

        address[] memory agents = new address[](1);
        agents[0] = agent;
        _voteToQuorum(arbitration, proposalId, agents);

        vm.prank(arbiter);
        arbitration.resolveArbitration(proposalId, true);

        assertEq(target.calls(), 1, "executed once");
        assertEq(arbitration.nonce(), 1, "nonce consumed");

        vm.prank(agent);
        vm.expectRevert(Pattern1_PlannerExecutor.InvalidNonce.selector);
        arbitration.propose(intent, signature);
    }

    // ------------------------------------- Pattern 2 day-boundary behaviour

    function _boundedWithCap(
        uint256 cap,
        address target
    ) internal returns (Pattern2_BoundedAutonomy bounded) {
        bounded = new Pattern2_BoundedAutonomy(signer, cap);
        vm.deal(address(bounded), 20 ether);
        bounded.addTarget(target);
    }

    /// One second before the boundary still counts against the same day; the reset
    /// happens exactly when the timestamp crosses into the next day.
    function test_CapStillAppliesOneSecondBeforeDayBoundary() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        vm.warp(86_399);

        Pattern1_PlannerExecutor.Intent memory first = _intent(
            address(target),
            0.75 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(first, _sign(address(bounded), first));
        assertEq(bounded.dailySpent(), 0.75 ether, "spent on day zero");

        Pattern1_PlannerExecutor.Intent memory tooMuch = _intent(
            address(target),
            0.5 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.SpendingCapExceeded.selector);
        bounded.execute(tooMuch, _sign(address(bounded), tooMuch));

        vm.warp(86_400);
        Pattern1_PlannerExecutor.Intent memory afterReset = _intent(
            address(target),
            0.5 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        bounded.execute(afterReset, _sign(address(bounded), afterReset));

        assertEq(bounded.dailySpent(), 0.5 ether, "counter restarted for the new day");
        assertEq(bounded.lastSpendingResetDay(), 1, "day index advanced");
    }

    /// Idle days do not accumulate allowance: the counter resets to the current day
    /// and the cap applies once per day, not once per idle day.
    function test_DayResetDoesNotAccumulateAcrossIdleDays() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        vm.warp(2_000);
        Pattern1_PlannerExecutor.Intent memory early = _intent(
            address(target),
            0.4 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(early, _sign(address(bounded), early));

        vm.warp(1_000 + 5 * 1 days);

        Pattern1_PlannerExecutor.Intent memory later = _intent(
            address(target),
            0.9 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        bounded.execute(later, _sign(address(bounded), later));

        assertEq(bounded.dailySpent(), 0.9 ether, "only today's spend is counted");

        // Deployed at t=1000 (day 0); five days later the timestamp sits in day 5.
        uint256 expectedDay = 5;
        assertEq(
            bounded.lastSpendingResetDay(),
            expectedDay,
            "reset target is the current day, not an accumulation"
        );
    }

    /// The cap is per calendar day, so spending the whole cap just before midnight and
    /// again just after is allowed. This pins the documented consequence rather than
    /// leaving it implicit.
    function test_BoundaryStraddleAllowsTwoCapsCloseTogether() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        vm.warp(86_399);
        Pattern1_PlannerExecutor.Intent memory beforeMidnight = _intent(
            address(target),
            1 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(beforeMidnight, _sign(address(bounded), beforeMidnight));
        assertEq(bounded.dailySpent(), 1 ether, "cap fully used on day zero");

        vm.warp(86_400);
        Pattern1_PlannerExecutor.Intent memory afterMidnight = _intent(
            address(target),
            1 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        bounded.execute(afterMidnight, _sign(address(bounded), afterMidnight));

        assertEq(address(target).balance, 2 ether, "2x the cap moved within one second");
        assertEq(bounded.dailySpent(), 1 ether, "day one is back at its own cap");
    }

    // ------------------------------------------ Pattern 2 emergency stop

    /// A rejected Intent must not consume anything: the nonce stays put and the cap
    /// keeps its previous spend, so the same Intent can still run after a resume.
    function test_PausedRejectionLeavesNonceAndDailySpendUntouched() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        Pattern1_PlannerExecutor.Intent memory spent = _intent(
            address(target),
            0.4 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(spent, _sign(address(bounded), spent));
        assertEq(bounded.dailySpent(), 0.4 ether, "precondition: part of the cap is used");
        assertEq(bounded.nonce(), 1, "precondition: nonce advanced once");

        bounded.emergencyStop(true);

        Pattern1_PlannerExecutor.Intent memory blocked = _intent(
            address(target),
            0.6 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.ContractPaused.selector);
        bounded.execute(blocked, _sign(address(bounded), blocked));

        assertEq(bounded.nonce(), 1, "blocked Intent did not advance the nonce");
        assertEq(bounded.dailySpent(), 0.4 ether, "blocked Intent did not consume the cap");
        assertEq(address(target).balance, 0.4 ether, "no value moved while paused");
    }

    /// The pause check runs before the allowlist check, so a paused contract reports
    /// `ContractPaused` even for a target that is not allowed.
    function test_ContractPausedTakesPrecedenceOverTargetNotAllowed() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));
        bounded.emergencyStop(true);

        address stranger = makeAddr("not-allowlisted");
        Pattern1_PlannerExecutor.Intent memory toStranger = _intent(
            stranger,
            0,
            "",
            0,
            block.timestamp + 1 hours
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.ContractPaused.selector);
        bounded.execute(toStranger, _sign(address(bounded), toStranger));

        // Once resumed, the same target fails on the allowlist instead.
        bounded.emergencyStop(false);
        vm.expectRevert(Pattern2_BoundedAutonomy.TargetNotAllowed.selector);
        bounded.execute(toStranger, _sign(address(bounded), toStranger));
    }

    /// A rejected Intent keeps its signature: resuming lets the very same bytes through,
    /// which is what makes the pause safe rather than destructive.
    function test_ResumeExecutesTheSameSignedIntent() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        Pattern1_PlannerExecutor.Intent memory spent = _intent(
            address(target),
            0.4 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(spent, _sign(address(bounded), spent));

        bounded.emergencyStop(true);

        Pattern1_PlannerExecutor.Intent memory blocked = _intent(
            address(target),
            0.6 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        bytes memory blockedSignature = _sign(address(bounded), blocked);

        vm.expectRevert(Pattern2_BoundedAutonomy.ContractPaused.selector);
        bounded.execute(blocked, blockedSignature);

        bounded.emergencyStop(false);
        bounded.execute(blocked, blockedSignature);

        assertEq(bounded.nonce(), 2, "resumed Intent advanced the nonce");
        assertEq(bounded.dailySpent(), 1 ether, "resumed Intent consumed its value");
        assertEq(address(target).balance, 1 ether, "value reached the target after resume");
    }

    /// The day reset is lazy and happens inside `execute` after the pause check, so a
    /// pause across midnight leaves stale storage. The first execution afterwards must
    /// reset it and expose the full cap for the new day, not what yesterday left over.
    ///
    /// While paused, `dailySpent` still holds the previous day's figure: it must never be
    /// read as today's spend without comparing `lastSpendingResetDay` to the current day.
    function test_ResumeAfterMidnightDoesNotCarryYesterdaySpend() public {
        vm.warp(1_000);

        ReviewReceiver target = new ReviewReceiver();
        Pattern2_BoundedAutonomy bounded = _boundedWithCap(1 ether, address(target));

        Pattern1_PlannerExecutor.Intent memory fullCap = _intent(
            address(target),
            1 ether,
            "",
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(fullCap, _sign(address(bounded), fullCap));
        assertEq(bounded.dailySpent(), 1 ether, "cap fully used on day zero");

        bounded.emergencyStop(true);
        vm.warp(86_400);

        // Nothing ran across the boundary, so the stored counter is still yesterday's.
        assertEq(bounded.dailySpent(), 1 ether, "counter is stale while paused");
        assertEq(bounded.lastSpendingResetDay(), 0, "reset day is stale while paused");

        bounded.emergencyStop(false);

        Pattern1_PlannerExecutor.Intent memory nextDay = _intent(
            address(target),
            1 ether,
            "",
            1,
            block.timestamp + 1 hours
        );
        bounded.execute(nextDay, _sign(address(bounded), nextDay));

        assertEq(bounded.dailySpent(), 1 ether, "new day starts from zero, then records its spend");
        assertEq(bounded.lastSpendingResetDay(), 1, "reset advanced on the first execution");
        assertEq(address(target).balance, 2 ether, "full cap available on the new day");
    }

    // ------------------------------------------- ERC-20 accounting boundaries (M3)

    /// `approve` moves no balance, so no before/after reading of the executor's balance could
    /// price it, and the pull that spent the allowance landed in a later transaction the
    /// executor never saw. That is why it was pinned: it was an accounting problem, not a
    /// signature problem.
    ///
    /// Current behaviour: the Intent is refused with `TokenCallForbidden`, no allowance
    /// exists, and no nonce is consumed.
    function test_ApproveIsRefusedAndCreatesNoAllowance() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        address thief = makeAddr("approve-thief");
        uint256 balanceBefore = token.balanceOf(address(bounded));

        Pattern1_PlannerExecutor.Intent memory grant = _intent(
            address(token),
            0,
            abi.encodeCall(ERC20.approve, (thief, 1_000e18)),
            0,
            block.timestamp + 1 hours
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCallForbidden.selector);
        bounded.execute(grant, _sign(address(bounded), grant));

        assertEq(token.allowance(address(bounded), thief), 0, "no allowance exists");
        assertEq(
            token.balanceOf(address(bounded)),
            balanceBefore,
            "and no balance moved"
        );
        assertEq(bounded.nonce(), 0, "a refused intent consumes no nonce");
    }

    /// An allowance that already exists when the bounded policy is first relied on is not
    /// something the executor observes: the spend happens with no Intent, so no nonce is
    /// consumed and no counter moves. Revocation is a migration prerequisite, not an
    /// in-contract guarantee, and it is a different state from the one above.
    function test_PreExistingAllowanceIsPulledWithoutAnyExecution() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));

        address spender = makeAddr("pre-existing-spender");

        // State at activation time, not a call the agent is able to make.
        vm.prank(address(bounded));
        token.approve(spender, 1_000e18);

        uint256 nonceBefore = bounded.nonce();

        vm.prank(spender);
        token.transferFrom(address(bounded), spender, 1_000e18);

        assertEq(token.balanceOf(spender), 1_000e18, "pulled outside any execution");
        assertEq(bounded.nonce(), nonceBefore, "no Intent was consumed");
        assertEq(bounded.dailySpent(), 0, "there is no execution to charge");
    }

    /// The loss does not require the token to be the target: a target that pulls with
    /// `transferFrom` moves the executor's balance inside the executed call. This is the path
    /// a balance reading would see, and the scenario has to exist as a test before that
    /// accounting can be claimed.
    function test_IndirectPullDuringExecutionIsNotCharged() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();
        PullRouter router = new PullRouter();
        token.mint(address(bounded), 1_000e18);

        vm.prank(address(bounded));
        token.approve(address(router), 1_000e18);
        bounded.addTarget(address(router));

        Pattern1_PlannerExecutor.Intent memory pull = _intent(
            address(router),
            0,
            abi.encodeCall(PullRouter.pull, (token, address(bounded), 1_000e18)),
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(pull, _sign(address(bounded), pull));

        assertEq(token.balanceOf(address(router)), 1_000e18, "the executed call moved the tokens");
        assertEq(token.balanceOf(address(bounded)), 0, "the executor paid");
        assertEq(bounded.dailySpent(), 0, "no token charge exists to apply");
    }

    /// Net decrease and gross outflow are different numbers. Here 100e18 leaves and 90e18
    /// returns within one execution: the executor is 10e18 poorer, and 10e18 is all a
    /// before/after reading can charge. Bounding volume instead of loss would need per-call
    /// deltas and is a different guarantee, not a detail of this one.
    function test_OutAndBackLeavesTenUnitLossWithinOneExecution() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        MockToken token = new MockToken();
        RebateRouter rebate = new RebateRouter();
        token.mint(address(bounded), 100e18);
        token.mint(address(rebate), 90e18);

        vm.prank(address(bounded));
        token.approve(address(rebate), 100e18);
        bounded.addTarget(address(rebate));

        Pattern1_PlannerExecutor.Intent memory roundtrip = _intent(
            address(rebate),
            0,
            abi.encodeCall(RebateRouter.run, (token, 100e18, 90e18)),
            0,
            block.timestamp + 1 hours
        );
        bounded.execute(roundtrip, _sign(address(bounded), roundtrip));

        assertEq(token.balanceOf(address(bounded)), 90e18, "100e18 left and 90e18 came back");
        assertEq(token.balanceOf(address(rebate)), 100e18, "the router kept the 10e18 difference");
        assertEq(bounded.dailySpent(), 0, "no token charge exists to apply");
    }

    /// The documentation says the executor implements no ERC-1271. That is what this asserts:
    /// the selector is absent. It does not assert that every `permit` variant is closed. Paths
    /// that need ERC-1271 validation are blocked by this absence; token-specific permit or
    /// authorization mechanisms are a separate review and are not claimed here.
    function test_ExecutorDoesNotImplementERC1271() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);

        (bool ok, bytes memory returndata) = address(bounded).staticcall(
            abi.encodeWithSelector(0x1626ba7e, bytes32(0), hex"")
        );

        assertFalse(ok, "isValidSignature(bytes32,bytes) must not be answered");
        assertEq(returndata.length, 0, "and nothing is returned for it");
    }

    // ------------------------------------------------------- ERC-2612 permit checks

    function _permitSignature(
        PermitMockToken token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 ownerKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                spender,
                value,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        return vm.sign(ownerKey, digest);
    }

    /// Standard OpenZeppelin ERC20Permit uses ECDSA recovery.
    /// A signature from the agent cannot impersonate the executor contract as token owner.
    function test_PermitCannotBeSignedForExecutorContract() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        PermitMockToken token = new PermitMockToken();

        address spender = makeAddr("permit-spender");
        uint256 deadline = block.timestamp + 1 hours;
        uint256 amount = 100e18;

        token.mint(address(bounded), amount);

        (uint8 v, bytes32 r, bytes32 s) = _permitSignature(
            token,
            address(bounded),
            spender,
            amount,
            deadline,
            signerKey
        );

        bounded.addTarget(address(token));

        bytes memory permitData = abi.encodeCall(
            IERC20Permit.permit,
            (address(bounded), spender, amount, deadline, v, r, s)
        );

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            permitData,
            0,
            deadline
        );

        vm.expectRevert(Pattern1_PlannerExecutor.CallFailed.selector);
        bounded.execute(intent, _sign(address(bounded), intent));

        assertEq(token.allowance(address(bounded), spender), 0);
    }

    /// The permit selector is not blocked by Pattern2 and can execute for an EOA owner.
    /// The resulting allowance belongs to that EOA, not to the executor's token balance.
    function test_PermitThroughExecutorOnlyAuthorizesEOBOwnedTokens() public {
        Pattern2_BoundedAutonomy bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        PermitMockToken token = new PermitMockToken();

        address spender = makeAddr("permit-spender");
        uint256 amount = 100e18;
        uint256 executorBalance = 500e18;
        uint256 deadline = block.timestamp + 1 hours;

        token.mint(signer, amount);
        token.mint(address(bounded), executorBalance);
        bounded.addTarget(address(token));

        (uint8 v, bytes32 r, bytes32 s) = _permitSignature(
            token,
            signer,
            spender,
            amount,
            deadline,
            signerKey
        );

        bytes memory permitData = abi.encodeCall(
            IERC20Permit.permit,
            (signer, spender, amount, deadline, v, r, s)
        );

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            permitData,
            0,
            deadline
        );

        bounded.execute(intent, _sign(address(bounded), intent));

        assertEq(token.allowance(signer, spender), amount);
        assertEq(token.allowance(address(bounded), spender), 0);

        vm.prank(spender);
        token.transferFrom(signer, spender, amount);

        assertEq(token.balanceOf(spender), amount);
        assertEq(token.balanceOf(signer), 0);
        assertEq(token.balanceOf(address(bounded)), executorBalance);
    }

}
