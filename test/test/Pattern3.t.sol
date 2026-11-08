// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
// استفاده از مسیر مطلق برای جلوگیری از خطای مسیر
import "contracts/Pattern3_MultiAgentArbitration.sol";

contract Pattern3Test is Test {
    Pattern3_MultiAgentArbitration multiAgent;
    address arbiter;
    address signer;
    uint256 signerPrivateKey;
    address agent1;
    address agent2;
    address allowedTarget;

    function setUp() public {
        arbiter = address(this);
        (signer, signerPrivateKey) = makeAddrAndKey("signer");
        agent1 = makeAddr("agent1");
        agent2 = makeAddr("agent2");
        allowedTarget = address(new MockTarget());

        multiAgent = new Pattern3_MultiAgentArbitration(signer, arbiter);

        // افزودن ایجنت‌ها
        multiAgent.addAgent(agent1);
        multiAgent.addAgent(agent2);
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
                address(multiAgent)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _createProposal() internal returns (uint256) {
        Pattern1_PlannerExecutor.Intent memory intent = Pattern1_PlannerExecutor.Intent({
            target: allowedTarget,
            value: 0,
            data: "",
            nonce: 0,
            deadline: block.timestamp + 1 hours
        });
        bytes memory signature = _signIntent(intent);

        vm.prank(agent1);
        return multiAgent.propose(intent, signature);
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
    }

    function test_VoteOnProposal() public {
        uint256 proposalId = _createProposal();

        vm.prank(agent1);
        multiAgent.vote(proposalId, true);

        vm.prank(agent2);
        multiAgent.vote(proposalId, true);

        // بررسی آرا (حذف یک کامای اضافی)
        (,,, uint256 approvals,,) = multiAgent.proposals(proposalId);
        assertEq(approvals, 2);
    }

    function test_ArbitrationExecutesProposal() public {
        uint256 proposalId = _createProposal();

        // داور تصمیم می‌گیرد پیشنهاد اجرا شود
        multiAgent.resolveArbitration(proposalId, true);

        // بررسی اجرا (حذف یک کامای اضافی)
        (,,,,, bool executed) = multiAgent.proposals(proposalId);
        assertTrue(executed);
    }

    function test_RevertWhenNotArbiter() public {
        uint256 proposalId = _createProposal();

        vm.prank(agent1);
        vm.expectRevert(Pattern3_MultiAgentArbitration.NotArbiter.selector);
        multiAgent.resolveArbitration(proposalId, true);
    }
}

contract MockTarget {
    receive() external payable {}
}