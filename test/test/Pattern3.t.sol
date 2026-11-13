
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "contracts/Pattern3_MultiAgentArbitration.sol";

contract Pattern3Test is Test {
    Pattern3_MultiAgentArbitration multiAgent;
    address arbiter;
    address signer;
    uint256 signerPrivateKey;

    address agent1;
    address agent2;
    address agent3;

    address allowedTarget;

    function setUp() public {
        arbiter = address(this);

        (signer, signerPrivateKey) = makeAddrAndKey("signer");

        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        agent3 = makeAddr("agent3");

        allowedTarget = address(new MockTarget());

        multiAgent = new Pattern3_MultiAgentArbitration(
            signer,
            arbiter
        );

        multiAgent.addAgent(agent1);
        multiAgent.addAgent(agent2);
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
                address(multiAgent)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(signerPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function _createProposalWithNonce(
        uint256 intentNonce
    ) internal returns (uint256) {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: allowedTarget,
                value: 0,
                data: "",
                nonce: intentNonce,
                deadline: block.timestamp + 1 hours
            });

        bytes memory signature = _signIntent(intent);

        vm.prank(agent1);
        return multiAgent.propose(intent, signature);
    }

    function _createProposal() internal returns (uint256) {
        return _createProposalWithNonce(0);
    }

    function _approveProposal(uint256 proposalId) internal {
        vm.prank(agent1);
        multiAgent.vote(proposalId, true);

        vm.prank(agent2);
        multiAgent.vote(proposalId, true);
    }

    function test_AddAndRemoveAgents() public {
        assertTrue(multiAgent.agents(agent1));
        assertTrue(multiAgent.agents(agent2));

        multiAgent.removeAgent(agent1);

        assertFalse(multiAgent.agents(agent1));
    }

    function test_CreateProposal() public {
        uint256 proposalId = _createProposal();

        assertEq(proposalId, 0);
        assertEq(multiAgent.proposalCount(), 1);
        assertTrue(multiAgent.nonceReserved(0));
    }

    function test_VoteOnProposal() public {
        uint256 proposalId = _createProposal();

        _approveProposal(proposalId);

        (,,, uint256 approvals,,,) = multiAgent.proposals(proposalId);

        assertEq(approvals, 2);
    }

    function test_ArbitrationExecutesProposal() public {
        uint256 proposalId = _createProposal();

        _approveProposal(proposalId);

        multiAgent.resolveArbitration(proposalId, true);

        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus status) =
            multiAgent.proposals(proposalId);

        assertEq(
            uint256(status),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Executed)
        );

        assertFalse(multiAgent.nonceReserved(0));
        assertEq(multiAgent.nonce(), 1);
    }

    function test_RevertWhenApprovingWithoutQuorum() public {
        uint256 proposalId = _createProposal();

        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InsufficientVotes.selector
        );

        multiAgent.resolveArbitration(proposalId, true);
    }

    function test_RevertWhenNotArbiter() public {
        uint256 proposalId = _createProposal();

        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.NotArbiter.selector
        );

        multiAgent.resolveArbitration(proposalId, true);
    }

    function test_RevertWhenVotingTwice() public {
        uint256 proposalId = _createProposal();

        vm.prank(agent1);
        multiAgent.vote(proposalId, true);

        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.AlreadyVoted.selector
        );

        multiAgent.vote(proposalId, true);
    }

    function test_RevertWhenVotingAfterExecution() public {
        uint256 proposalId = _createProposal();

        _approveProposal(proposalId);
        multiAgent.resolveArbitration(proposalId, true);

        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.ProposalAlreadyExecuted.selector
        );

        multiAgent.vote(proposalId, true);
    }

    function test_RevertWhenUnauthorizedAgentVotes() public {
        uint256 proposalId = _createProposal();

        vm.prank(agent3);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.NotAgent.selector
        );

        multiAgent.vote(proposalId, true);
    }

    function test_RejectedProposalReleasesNonce() public {
        uint256 proposalId = _createProposal();

        multiAgent.resolveArbitration(proposalId, false);

        assertFalse(multiAgent.nonceReserved(0));

        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus status) =
            multiAgent.proposals(proposalId);

        assertEq(
            uint256(status),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Rejected)
        );

        uint256 newProposalId = _createProposal();

        assertEq(newProposalId, 1);
        assertTrue(multiAgent.nonceReserved(0));
    }

    function test_RevertWhenVotingOnRejectedProposal() public {
        uint256 proposalId = _createProposal();

        multiAgent.resolveArbitration(proposalId, false);

        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.ProposalNotPending.selector
        );

        multiAgent.vote(proposalId, true);
    }

    function test_RevertWhenDirectExecutionIsAttempted() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: allowedTarget,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory signature = _signIntent(intent);

        vm.expectRevert(
            Pattern3_MultiAgentArbitration.DirectExecutionDisabled.selector
        );

        multiAgent.execute(intent, signature);
    }

    function test_RevertWhenProposalTargetIsZero() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: address(0),
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory signature = _signIntent(intent);

        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InvalidTarget.selector
        );

        multiAgent.propose(intent, signature);
    }

    function test_RevertWhenVotingOnUnknownProposal() public {
        vm.prank(agent1);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InvalidProposal.selector
        );

        multiAgent.vote(99, true);
    }

    function test_RemovingAgentDoesNotLowerExistingProposalQuorum() public {
        uint256 proposalId = _createProposal();

        multiAgent.removeAgent(agent2);

        vm.prank(agent1);
        multiAgent.vote(proposalId, true);

        vm.expectRevert(
            Pattern3_MultiAgentArbitration.InsufficientVotes.selector
        );

        multiAgent.resolveArbitration(proposalId, true);
    }

    function test_NewAgentCannotVoteOnOldProposal() public {
        uint256 proposalId = _createProposal();

        multiAgent.removeAgent(agent2);
        multiAgent.addAgent(agent3);

        vm.prank(agent3);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.NotAgent.selector
        );

        multiAgent.vote(proposalId, true);
    }

    function test_RevertWhenProposalSignatureIsInvalid() public {
        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: allowedTarget,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory invalidSignature = new bytes(65);

        vm.prank(agent1);
        vm.expectRevert(
            Pattern1_PlannerExecutor.InvalidSignature.selector
        );

        multiAgent.propose(intent, invalidSignature);

        assertEq(multiAgent.proposalCount(), 0);
        assertFalse(multiAgent.nonceReserved(0));
    }

    function test_RevertWhenNonceIsAlreadyReserved() public {
        _createProposal();

        Pattern1_PlannerExecutor.Intent memory intent =
            Pattern1_PlannerExecutor.Intent({
                target: allowedTarget,
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory signature = _signIntent(intent);

        vm.prank(agent2);
        vm.expectRevert(
            Pattern3_MultiAgentArbitration.NonceAlreadyProposed.selector
        );

        multiAgent.propose(intent, signature);

        assertEq(multiAgent.proposalCount(), 1);
        assertTrue(multiAgent.nonceReserved(0));
    }

    // Future nonce tests

    function test_CanProposeFutureNonceBeforeCurrentNonce() public {
        uint256 proposalId = _createProposalWithNonce(1);

        assertEq(proposalId, 0);
        assertEq(multiAgent.nonce(), 0);
        assertTrue(multiAgent.nonceReserved(1));
        assertEq(multiAgent.proposalCount(), 1);
    }

    function test_RevertWhenExecutingFutureNonceBeforeCurrentNonce()
        public
    {
        uint256 proposalId = _createProposalWithNonce(1);

        _approveProposal(proposalId);

        vm.expectRevert(
            Pattern1_PlannerExecutor.InvalidNonce.selector
        );

        multiAgent.resolveArbitration(proposalId, true);

        assertEq(multiAgent.nonce(), 0);
        assertTrue(multiAgent.nonceReserved(1));

        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus status) =
            multiAgent.proposals(proposalId);

        assertEq(
            uint256(status),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Pending)
        );
    }

    function test_CanExecuteFutureNonceAfterCurrentNonce() public {
        uint256 firstProposalId = _createProposalWithNonce(0);
        uint256 secondProposalId = _createProposalWithNonce(1);

        _approveProposal(firstProposalId);
        _approveProposal(secondProposalId);

        // Execute nonce 0 first.
        multiAgent.resolveArbitration(firstProposalId, true);

        assertEq(multiAgent.nonce(), 1);
        assertFalse(multiAgent.nonceReserved(0));
        assertTrue(multiAgent.nonceReserved(1));

        // Nonce 1 is now current and can be executed.
        multiAgent.resolveArbitration(secondProposalId, true);

        assertEq(multiAgent.nonce(), 2);
        assertFalse(multiAgent.nonceReserved(1));

        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus firstStatus) =
            multiAgent.proposals(firstProposalId);

        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus secondStatus) =
            multiAgent.proposals(secondProposalId);

        assertEq(
            uint256(firstStatus),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Executed)
        );

        assertEq(
            uint256(secondStatus),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Executed)
        );
    }

    function test_ReentrancyCannotExecuteSecondProposal() public {
        // Deploy a contract that is both arbiter and execution target.
        ReentrantArbiterTarget attacker = new ReentrantArbiterTarget();

        multiAgent = new Pattern3_MultiAgentArbitration(
            signer,
            address(attacker)
        );

        attacker.setMultiAgent(multiAgent);

        attacker.addAgent(agent1);
        attacker.addAgent(agent2);

        // First proposal: nonce 0, target is the attacker contract.
        Pattern1_PlannerExecutor.Intent memory firstIntent =
            Pattern1_PlannerExecutor.Intent({
                target: address(attacker),
                value: 0,
                data: "",
                nonce: 0,
                deadline: block.timestamp + 1 hours
            });

        bytes memory firstSignature = _signIntent(firstIntent);

        vm.prank(agent1);
        uint256 firstProposalId =
            multiAgent.propose(firstIntent, firstSignature);

        // Second proposal: nonce 1, should remain pending during reentry.
        Pattern1_PlannerExecutor.Intent memory secondIntent =
            Pattern1_PlannerExecutor.Intent({
                target: allowedTarget,
                value: 0,
                data: "",
                nonce: 1,
                deadline: block.timestamp + 1 hours
            });

        bytes memory secondSignature = _signIntent(secondIntent);

        vm.prank(agent1);
        uint256 secondProposalId =
            multiAgent.propose(secondIntent, secondSignature);

        _approveProposal(firstProposalId);
        _approveProposal(secondProposalId);

        // During execution of proposal 0, attacker tries to execute proposal 1.
        attacker.setNestedProposalId(secondProposalId);

        attacker.resolveProposal(firstProposalId);

        // The nested call must have failed.
        assertTrue(attacker.reentryAttempted());
        assertTrue(attacker.reentryBlocked());

        // Proposal 1 must remain pending and its nonce must remain reserved.
        (,,,,,, Pattern3_MultiAgentArbitration.ProposalStatus status) =
            multiAgent.proposals(secondProposalId);

        assertEq(
            uint256(status),
            uint256(Pattern3_MultiAgentArbitration.ProposalStatus.Pending)
        );

        assertEq(multiAgent.nonce(), 1);
        assertTrue(multiAgent.nonceReserved(1));
    }
}

contract MockTarget {
    receive() external payable {}
}

contract ReentrantArbiterTarget {
    Pattern3_MultiAgentArbitration public multiAgent;

    uint256 public nestedProposalId;

    bool public reentryAttempted;
    bool public reentryBlocked;

    function setMultiAgent(
        Pattern3_MultiAgentArbitration _multiAgent
    ) external {
        multiAgent = _multiAgent;
    }

    function addAgent(address agent) external {
        multiAgent.addAgent(agent);
    }

    function setNestedProposalId(uint256 proposalId) external {
        nestedProposalId = proposalId;
    }

    function resolveProposal(uint256 proposalId) external {
        multiAgent.resolveArbitration(proposalId, true);
    }

    receive() external payable {
        reentryAttempted = true;

        (bool success, ) = address(multiAgent).call(
            abi.encodeWithSelector(
                multiAgent.resolveArbitration.selector,
                nestedProposalId,
                true
            )
        );

        reentryBlocked = !success;
    }
}
