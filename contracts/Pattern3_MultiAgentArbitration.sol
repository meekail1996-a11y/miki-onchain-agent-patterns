// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pattern1_PlannerExecutor.sol";

contract Pattern3_MultiAgentArbitration is Pattern1_PlannerExecutor {
    mapping(address => bool) public agents;
    uint256 public agentCount;

    address public arbiter;

    struct Proposal {
        Intent intent;
        bytes signature;
        address proposer;
        uint256 approvals;
        uint256 rejections;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    event AgentAdded(address indexed agent);
    event AgentRemoved(address indexed agent);
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event ArbitrationResolved(uint256 indexed proposalId, bool approved);

    error NotAgent();
    error AlreadyVoted();
    error ProposalAlreadyExecuted();
    error InsufficientVotes();
    error NotArbiter();

    constructor(
        address _agentSigner,
        address _arbiter
    ) Pattern1_PlannerExecutor(_agentSigner) {
        if (_arbiter == address(0)) revert InvalidAgentSigner();
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

    function addAgent(address _agent) external onlyArbiter {
        if (!agents[_agent]) {
            agents[_agent] = true;
            agentCount++;
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
        uint256 proposalId = proposalCount++;
        Proposal storage p = proposals[proposalId];
        p.intent = _intent;
        p.signature = _signature;
        p.proposer = msg.sender;

        emit ProposalCreated(proposalId, msg.sender);
        return proposalId;
    }

    function vote(uint256 _proposalId, bool _support) external onlyAgent {
        Proposal storage p = proposals[_proposalId];
        if (p.executed) revert ProposalAlreadyExecuted();
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
    ) external onlyArbiter {
        Proposal storage p = proposals[_proposalId];
        if (p.executed) revert ProposalAlreadyExecuted();

        if (_approve) {
            // کپی از storage به memory برای فراخوانی execute
            Intent memory intentCopy = p.intent;
            bytes memory signatureCopy = p.signature;
            
            super.execute(intentCopy, signatureCopy);
            p.executed = true;
            emit ProposalExecuted(_proposalId);
        }
        emit ArbitrationResolved(_proposalId, _approve);
    }
}