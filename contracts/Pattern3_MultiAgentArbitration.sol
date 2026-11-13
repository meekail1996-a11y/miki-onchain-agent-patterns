
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pattern1_PlannerExecutor.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Pattern3_MultiAgentArbitration is
    Pattern1_PlannerExecutor,
    ReentrancyGuard
{
    enum ProposalStatus {
        Pending,
        Executed,
        Rejected
    }

    mapping(address => bool) public agents;
    mapping(address => uint256) public agentEpoch;

    uint256 public agentCount;
    address public arbiter;

    mapping(uint256 => bool) public nonceReserved;

    struct Proposal {
        Intent intent;
        bytes signature;
        address proposer;
        uint256 approvals;
        uint256 rejections;
        uint256 quorum;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support
    );
    event ProposalExecuted(uint256 indexed proposalId);
    event ArbitrationResolved(uint256 indexed proposalId, bool approved);

    error NotAgent();
    error AlreadyVoted();
    error ProposalAlreadyExecuted();
    error ProposalNotPending();
    error InsufficientVotes();
    error NotArbiter();
    error InvalidArbiter();
    error InvalidAgent();
    error InvalidProposal();
    error InvalidTarget();
    error NonceAlreadyProposed();
    error DirectExecutionDisabled();

    constructor(
        address _agentSigner,
        address _arbiter
    ) Pattern1_PlannerExecutor(_agentSigner) {
        if (_arbiter == address(0)) revert InvalidArbiter();
        arbiter = _arbiter;
    }

    modifier onlyAgent() {
        if (!agents[msg.sender]) revert NotAgent();
        _;
    }

    modifier onlyArbiter() {
        if (msg.sender != arbiter) revert NotArbiter();
        _;
    }

    function execute(
        Intent memory,
        bytes memory
    ) public pure override {
        revert DirectExecutionDisabled();
    }

    function addAgent(address _agent) external onlyArbiter {
        if (_agent == address(0)) revert InvalidAgent();

        if (!agents[_agent]) {
            agents[_agent] = true;
            agentCount++;

            // The agent can vote only on proposals created
            // at or after this registration epoch.
            agentEpoch[_agent] = proposalCount;

            emit AgentAdded(_agent);
        }
    }

    function removeAgent(address _agent) external onlyArbiter {
        if (agents[_agent]) {
            agents[_agent] = false;
            agentCount--;

            emit AgentRemoved(_agent);
        }
    }

    function propose(
        Intent calldata _intent,
        bytes calldata _signature
    ) external onlyAgent returns (uint256) {
        if (block.timestamp > _intent.deadline) revert IntentExpired();
        if (_intent.target == address(0)) revert InvalidTarget();
        if (_intent.nonce < nonce) revert InvalidNonce();

        // Validate the signature before reserving the nonce.
        _verifyIntentSignature(_intent, _signature);

        if (nonceReserved[_intent.nonce]) {
            revert NonceAlreadyProposed();
        }

        uint256 proposalId = proposalCount++;

        Proposal storage p = proposals[proposalId];

        p.intent = _intent;
        p.signature = _signature;
        p.proposer = msg.sender;
        p.quorum = (agentCount / 2) + 1;
        p.status = ProposalStatus.Pending;

        nonceReserved[_intent.nonce] = true;

        emit ProposalCreated(proposalId, msg.sender);

        return proposalId;
    }

    function vote(
        uint256 _proposalId,
        bool _support
    ) external onlyAgent {
        if (_proposalId >= proposalCount) revert InvalidProposal();

        Proposal storage p = proposals[_proposalId];

        if (p.status == ProposalStatus.Executed) {
            revert ProposalAlreadyExecuted();
        }
        if (p.status != ProposalStatus.Pending) {
            revert ProposalNotPending();
        }

        // Prevent agents added later from voting on old proposals.
        if (agentEpoch[msg.sender] > _proposalId) revert NotAgent();

        if (p.hasVoted[msg.sender]) revert AlreadyVoted();

        p.hasVoted[msg.sender] = true;

        if (_support) {
            p.approvals++;
        } else {
            p.rejections++;
        }

        emit VoteCast(_proposalId, msg.sender, _support);
    }

    function resolveArbitration(
        uint256 _proposalId,
        bool _approve
    ) external onlyArbiter nonReentrant {
        if (_proposalId >= proposalCount) revert InvalidProposal();

        Proposal storage p = proposals[_proposalId];

        if (p.status == ProposalStatus.Executed) {
            revert ProposalAlreadyExecuted();
        }
        if (p.status != ProposalStatus.Pending) {
            revert ProposalNotPending();
        }

        if (_approve) {
            if (p.approvals < p.quorum) revert InsufficientVotes();

            Intent memory intentCopy = p.intent;
            bytes memory signatureCopy = p.signature;

            if (intentCopy.nonce != nonce) revert InvalidNonce();

            // Effects before interaction. If execution fails,
            // the whole transaction, including these changes, reverts.
            p.status = ProposalStatus.Executed;
            nonceReserved[intentCopy.nonce] = false;

            _executeIntent(intentCopy, signatureCopy);

            emit ProposalExecuted(_proposalId);
        } else {
            p.status = ProposalStatus.Rejected;
            nonceReserved[p.intent.nonce] = false;
        }

        emit ArbitrationResolved(_proposalId, _approve);
    }
}
