// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";

contract FuzzEthReceiver {
    receive() external payable {}
}

/// @notice Fuzz coverage for Pattern 2's daily spending cap.
/// @dev These tests assert properties over random inputs rather than single
///      scenarios: the cap is never exceeded, accounting matches the value that
///      actually left the contract, and a rejected Intent changes no state.
contract Pattern2FuzzTest is Test {
    Pattern2_BoundedAutonomy bounded;
    FuzzEthReceiver receiver;

    address signer;
    uint256 signerPrivateKey;

    uint256 internal constant INITIAL_CAP = 10 ether;

    function setUp() public {
        (signer, signerPrivateKey) = makeAddrAndKey("signer");

        receiver = new FuzzEthReceiver();
        bounded = new Pattern2_BoundedAutonomy(signer, INITIAL_CAP);

        // The test contract is the deployer, so it is the admin.
        bounded.addTarget(address(receiver));

        vm.deal(address(bounded), 1_000 ether);
    }

    // ---------------------------------------------------------------- helpers

    function _sign(
        Pattern2_BoundedAutonomy instance,
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
                address(instance)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        return abi.encodePacked(r, s, v);
    }

    function _intent(
        uint256 value,
        uint256 nonce
    ) internal view returns (Pattern1_PlannerExecutor.Intent memory) {
        return Pattern1_PlannerExecutor.Intent({
            target: address(receiver),
            value: value,
            data: "",
            nonce: nonce,
            deadline: block.timestamp + 1 hours
        });
    }

    /// @dev Executes one Intent against `bounded`, signed for the current nonce.
    function _execute(uint256 value) internal {
        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            value,
            bounded.nonce()
        );
        bounded.execute(intent, _sign(bounded, intent));
    }

    // ------------------------------------------------------------------ fuzz

    /// @notice The cap holds across any sequence of Intents on the same day.
    function testFuzz_DailySpendingNeverExceedsCap(
        uint96 rawAmount,
        uint8 rawCount
    ) public {
        uint256 amount = bound(rawAmount, 0, INITIAL_CAP);
        uint256 count = bound(rawCount, 1, 12);

        uint256 expectedSpent = 0;
        uint256 expectedNonce = 0;

        for (uint256 i = 0; i < count; i++) {
            Pattern1_PlannerExecutor.Intent memory intent = _intent(
                amount,
                bounded.nonce()
            );

            try bounded.execute(intent, _sign(bounded, intent)) {
                expectedSpent += amount;
                expectedNonce++;
            } catch {
                // Rejected by the cap; neither accounting nor nonce may move.
            }

            assertLe(
                bounded.dailySpent(),
                INITIAL_CAP,
                "daily spend exceeded the cap"
            );
            assertEq(
                bounded.dailySpent(),
                expectedSpent,
                "accounting drifted from the value actually sent"
            );
            assertEq(
                bounded.nonce(),
                expectedNonce,
                "nonce advances only on successful execution"
            );
        }

        assertEq(
            address(receiver).balance,
            expectedSpent,
            "receiver balance must match recorded spend"
        );
    }

    /// @notice Spending never exceeds the cap even when each Intent is exactly
    ///         the remaining allowance.
    function testFuzz_RemainingAllowanceIsExact(
        uint96 rawValue,
        uint8 rawCount
    ) public {
        uint256 value = bound(rawValue, 1, INITIAL_CAP);
        uint256 count = bound(rawCount, 1, 10);

        uint256 successes = 0;

        for (uint256 i = 0; i < count; i++) {
            Pattern1_PlannerExecutor.Intent memory intent = _intent(
                value,
                bounded.nonce()
            );

            try bounded.execute(intent, _sign(bounded, intent)) {
                successes++;
            } catch {}
        }

        // At most floor(cap / value) executions can succeed.
        assertLe(successes, INITIAL_CAP / value, "too many executions");
        assertEq(
            bounded.dailySpent(),
            successes * value,
            "recorded spend must equal successful value transferred"
        );
        assertLe(bounded.dailySpent(), INITIAL_CAP);
    }

    /// @notice Accounting resets on a new day and the full cap becomes
    ///         available again.
    function testFuzz_NewDayRestoresFullCap(
        uint96 rawFirst,
        uint96 rawSecond
    ) public {
        uint256 first = bound(rawFirst, 0, INITIAL_CAP);
        uint256 second = bound(rawSecond, 0, INITIAL_CAP);

        _execute(first);
        assertEq(bounded.dailySpent(), first);

        vm.warp(block.timestamp + 1 days);

        _execute(second);
        assertEq(
            bounded.dailySpent(),
            second,
            "counter must reset before the first spend of the new day"
        );
        assertEq(bounded.lastSpendingResetDay(), block.timestamp / 1 days);
    }

    /// @notice An Intent above the cap reverts and leaves no state behind.
    function testFuzz_AboveCapRevertsWithoutStateChange(
        uint96 rawCap,
        uint96 rawValue
    ) public {
        uint256 cap = bound(rawCap, 1, 100 ether);
        uint256 value = bound(rawValue, cap + 1, cap + 100 ether);

        Pattern2_BoundedAutonomy fresh = new Pattern2_BoundedAutonomy(
            signer,
            cap
        );
        fresh.addTarget(address(receiver));
        vm.deal(address(fresh), type(uint128).max);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(value, 0);

        vm.expectRevert(
            Pattern2_BoundedAutonomy.SpendingCapExceeded.selector
        );
        fresh.execute(intent, _sign(fresh, intent));

        assertEq(fresh.dailySpent(), 0, "no spend recorded");
        assertEq(fresh.nonce(), 0, "nonce must not be consumed");
        assertEq(address(receiver).balance, 0, "no value transferred");
    }
}
