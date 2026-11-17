// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";

/// @notice Receives executed Intents and records what actually arrived.
contract InvariantTarget {
    uint256 public calls;
    uint256 public received;

    receive() external payable {
        calls++;
        received += msg.value;
    }
}

/// @notice Drives Pattern 2 with signed Intents across random values and days.
/// The fuzz suite checks single calls; this drives sequences, which is where the
/// day reset, the nonce and the accounting have to stay consistent together.
contract Pattern2Handler is Test {
    Pattern2_BoundedAutonomy public immutable bounded;
    InvariantTarget public immutable target;
    address public immutable stranger;
    address public immutable signer;
    address public immutable admin;
    uint256 private immutable signerKey;

    uint256 public ghost_executions;
    uint256 public ghost_valueTransferred;
    uint256 public ghost_blocked;
    uint256 public ghost_capChanges;
    uint256 public ghost_pauses;
    uint256 public ghost_executionsWhilePaused;
    uint256 public ghost_capViolationsAtExecution;

    constructor(
        Pattern2_BoundedAutonomy _bounded,
        InvariantTarget _target,
        address _stranger,
        address _signer,
        address _admin,
        uint256 _signerKey
    ) {
        bounded = _bounded;
        target = _target;
        stranger = _stranger;
        signer = _signer;
        admin = _admin;
        signerKey = _signerKey;
    }

    function _sign(
        Pattern1_PlannerExecutor.Intent memory intent
    ) private view returns (bytes memory) {
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
        bytes32 domain = keccak256(
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
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            signerKey,
            keccak256(abi.encodePacked("\x19\x01", domain, structHash))
        );
        return abi.encodePacked(r, s, v);
    }

    function _intent(
        address to,
        uint256 value
    ) private view returns (Pattern1_PlannerExecutor.Intent memory) {
        return
            Pattern1_PlannerExecutor.Intent({
                target: to,
                value: value,
                data: "",
                nonce: bounded.nonce(),
                deadline: block.timestamp + 1 hours
            });
    }

    /// @notice A signed Intent to an allowlisted target, at a random value and day.
    function executeAllowlisted(uint96 value, uint8 dayJumps) external {
        value = uint96(bound(value, 0, 4 ether));
        vm.warp(block.timestamp + bound(dayJumps, 0, 2) * 1 days);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(address(target), value);
        bool wasPaused = bounded.paused();
        try bounded.execute(intent, _sign(intent)) {
            ghost_executions++;
            ghost_valueTransferred += value;
            if (wasPaused) ghost_executionsWhilePaused++;
            _recordCapSnapshot();
        } catch {
            ghost_blocked++;
        }
    }

    /// @notice The same flow against an address the admin never allowlisted.
    function executeStranger(uint96 value) external {
        value = uint96(bound(value, 0, 1 ether));
        Pattern1_PlannerExecutor.Intent memory intent = _intent(stranger, value);
        bool wasPaused = bounded.paused();
        try bounded.execute(intent, _sign(intent)) {
            ghost_executions++;
            ghost_valueTransferred += value;
            if (wasPaused) ghost_executionsWhilePaused++;
            _recordCapSnapshot();
        } catch {
            ghost_blocked++;
        }
    }

    /// @dev Checked right after an execution, because the admin is allowed to lower the
    /// cap below the amount already spent. In that state `dailySpent > spendingCap` is a
    /// documented consequence of the admin's choice, not a new spend; what must never
    /// happen is an execution that leaves the recorded spend above the cap in force.
    function _recordCapSnapshot() private {
        if (bounded.dailySpent() > bounded.spendingCapPerDay()) {
            ghost_capViolationsAtExecution++;
        }
    }

    /// @notice The admin raises or lowers the cap between executions.
    /// @dev The handler is not the admin, so the call has to be pranked. Without this the
    /// function reverted on every call and the invariants never saw a cap change.
    function changeCap(uint96 newCap) external {
        vm.prank(admin);
        bounded.setSpendingCap(bound(newCap, 0, 5 ether));
        ghost_capChanges++;
    }

    /// @notice Pause or resume between executions, as the admin.
    function togglePause(bool paused) external {
        vm.prank(admin);
        bounded.emergencyStop(paused);
        ghost_pauses++;
    }
}

/// @notice Invariants over sequences of executions, not single calls.
contract Pattern2InvariantTest is Test {
    uint256 private constant FUNDING = 10 ether;
    uint256 private constant CAP = 1 ether;

    Pattern2_BoundedAutonomy private bounded;
    InvariantTarget private target;
    Pattern2Handler private handler;
    address private signer;
    uint256 private signerKey;

    function setUp() public {
        (signer, signerKey) = makeAddrAndKey("invariantSigner");
        bounded = new Pattern2_BoundedAutonomy(signer, CAP);
        target = new InvariantTarget();
        bounded.addTarget(address(target));
        vm.deal(address(bounded), FUNDING);

        handler = new Pattern2Handler(
            bounded,
            target,
            makeAddr("stranger"),
            signer,
            bounded.admin(),
            signerKey
        );
        targetContract(address(handler));
    }

    /// @notice No execution may leave the recorded spend above the cap in force at the
    /// moment it ran. Comparing the live values instead would flag the admin's documented
    /// ability to lower the cap below what is already spent, which is not a violation.
    function invariant_ExecutionNeverExceedsCap() public view {
        assertEq(
            handler.ghost_capViolationsAtExecution(),
            0,
            "an execution left dailySpent above the cap"
        );
    }

    /// @notice Every successful execution advanced the nonce by exactly one.
    function invariant_NonceMatchesExecutions() public view {
        assertEq(
            bounded.nonce(),
            handler.ghost_executions(),
            "nonce and successful executions disagree"
        );
    }

    /// @notice A paused contract never executes, whatever the rest of the state looks like.
    function invariant_NoExecutionWhilePaused() public view {
        assertEq(
            handler.ghost_executionsWhilePaused(),
            0,
            "an execution succeeded while paused"
        );
    }

    /// @notice The ether that left the contract equals the ether the tests saw arrive.
    function invariant_BalanceMatchesOutflow() public view {
        assertEq(
            address(bounded).balance,
            FUNDING - handler.ghost_valueTransferred(),
            "balance and recorded outflow disagree"
        );
        assertEq(
            target.received(),
            handler.ghost_valueTransferred(),
            "target received a different amount"
        );
    }
}
