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
    uint256 private immutable signerKey;

    uint256 public ghost_executions;
    uint256 public ghost_valueTransferred;
    uint256 public ghost_blocked;

    constructor(
        Pattern2_BoundedAutonomy _bounded,
        InvariantTarget _target,
        address _stranger,
        address _signer,
        uint256 _signerKey
    ) {
        bounded = _bounded;
        target = _target;
        stranger = _stranger;
        signer = _signer;
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
        try bounded.execute(intent, _sign(intent)) {
            ghost_executions++;
            ghost_valueTransferred += value;
        } catch {
            ghost_blocked++;
        }
    }

    /// @notice The same flow against an address the admin never allowlisted.
    function executeStranger(uint96 value) external {
        value = uint96(bound(value, 0, 1 ether));
        Pattern1_PlannerExecutor.Intent memory intent = _intent(stranger, value);
        try bounded.execute(intent, _sign(intent)) {
            ghost_executions++;
            ghost_valueTransferred += value;
        } catch {
            ghost_blocked++;
        }
    }

    /// @notice The admin raises or lowers the cap between executions.
    function changeCap(uint96 newCap) external {
        bounded.setSpendingCap(bound(newCap, 0, 5 ether));
    }

    /// @notice Pause or resume between executions.
    function togglePause(bool paused) external {
        bounded.emergencyStop(paused);
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
            signerKey
        );
        targetContract(address(handler));
    }

    /// @notice The recorded spend can never exceed the cap in force.
    function invariant_DailySpendNeverExceedsCap() public view {
        assertLe(
            bounded.dailySpent(),
            bounded.spendingCapPerDay(),
            "dailySpent exceeded the cap"
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
