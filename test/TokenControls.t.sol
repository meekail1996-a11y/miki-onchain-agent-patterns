// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Pattern2_BoundedAutonomy.sol";

/// A standard ERC-20 shape for the metered path: `transfer` returns `true` and moves the
/// declared amount.
contract MeterToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function increaseAllowance(address spender, uint256 added) external returns (bool) {
        allowance[msg.sender][spender] += added;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// The oldest token shape: `transfer` succeeds and returns nothing at all.
contract VoidReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }
}

/// Reports failure through the return value instead of reverting.
contract FalseReturnToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }
}

/// Returns a word that is neither `true` nor `false`.
contract NonBooleanReturnToken {
    function transfer(address, uint256) external pure returns (uint256) {
        return 2;
    }
}

/// @notice Pins the M3 controls: only a direct `transfer` on a registered token is allowed,
/// it is charged against that token's own daily cap before the call, and every other token
/// selector is refused. The five M3 cases in `SecurityReview.t.sol` record the behaviour this
/// suite replaces; the two that describe an allowance which already exists at activation time
/// stay there, because that state is a migration prerequisite and not something this path
/// can observe.
contract TokenControlsTest is Test {
    bytes32 private constant INTENT_TYPEHASH = keccak256(
        "Intent(address target,uint256 value,bytes data,uint256 nonce,uint256 deadline)"
    );

    bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd;
    bytes4 private constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 private constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;

    Pattern2_BoundedAutonomy private bounded;
    address private signer;
    uint256 private signerKey;
    address private recipient;

    function setUp() public {
        (signer, signerKey) = makeAddrAndKey("tokenSigner");
        bounded = new Pattern2_BoundedAutonomy(signer, 1 ether);
        vm.deal(address(bounded), 10 ether);
        recipient = makeAddr("recipient");
    }

    // ---------------------------------------------------------------- helpers

    function _domain() internal view returns (bytes32) {
        return
            keccak256(
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
    }

    function _sign(
        Pattern1_PlannerExecutor.Intent memory intent
    ) internal view returns (bytes memory) {
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
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", _domain(), structHash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _intent(
        address target,
        uint256 value,
        bytes memory data,
        uint256 nonce
    ) internal view returns (Pattern1_PlannerExecutor.Intent memory) {
        return
            Pattern1_PlannerExecutor.Intent({
                target: target,
                value: value,
                data: data,
                nonce: nonce,
                deadline: block.timestamp + 1 hours
            });
    }

    function _transferData(address to, uint256 amount) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount);
    }

    function _resize(
        bytes memory data,
        uint256 newLength
    ) internal pure returns (bytes memory out) {
        out = new bytes(newLength);
        uint256 limit = newLength < data.length ? newLength : data.length;
        for (uint256 i = 0; i < limit; i++) {
            out[i] = data[i];
        }
    }

    /// Run a metered transfer of `amount` as the current intent.
    function _meteredTransfer(
        address token,
        uint256 amount,
        uint256 nonce
    ) internal returns (bool ok) {
        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            token,
            0,
            _transferData(recipient, amount),
            nonce
        );
        try bounded.execute(intent, _sign(intent)) {
            return true;
        } catch {
            return false;
        }
    }

    // --------------------------------------------------------- selector policy

    /// `approve` on a registered token is refused, so the metered path cannot create the
    /// allowance the indirect route needs.
    function test_ApproveOnMeteredTokenReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        address thief = makeAddr("approve-thief");
        Pattern1_PlannerExecutor.Intent memory grant = _intent(
            address(token),
            0,
            abi.encodeCall(MeterToken.approve, (thief, 1_000e18)),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCallForbidden.selector);
        bounded.execute(grant, _sign(grant));

        assertEq(token.allowance(address(bounded), thief), 0, "no allowance was created");
        assertEq(bounded.nonce(), 0, "a refused intent consumes no nonce");
    }

    /// `increaseAllowance` is the second way to grow an existing allowance, refused for the
    /// same reason.
    function test_IncreaseAllowanceOnMeteredTokenReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        address spender = makeAddr("allowance-spender");
        Pattern1_PlannerExecutor.Intent memory grow = _intent(
            address(token),
            0,
            abi.encodeCall(MeterToken.increaseAllowance, (spender, 1e18)),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCallForbidden.selector);
        bounded.execute(grow, _sign(grow));

        assertEq(token.allowance(address(bounded), spender), 0, "no allowance was created");
    }

    /// `transferFrom` is refused on the token itself. This is the selector a router would use
    /// from inside its own call; here it is refused at the target, and the allowance route it
    /// depends on is documented as a migration prerequisite.
    function test_TransferFromOnMeteredTokenReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        // State at activation time: an allowance that already exists, not one this path can
        // create. The selector is refused regardless.
        vm.prank(address(bounded));
        token.approve(recipient, 1_000e18);

        Pattern1_PlannerExecutor.Intent memory pull = _intent(
            address(token),
            0,
            abi.encodeCall(
                MeterToken.transferFrom,
                (address(bounded), recipient, 1_000e18)
            ),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCallForbidden.selector);
        bounded.execute(pull, _sign(pull));

        assertEq(token.balanceOf(address(bounded)), 1_000e18, "nothing moved");
        assertEq(token.balanceOf(recipient), 0, "the recipient received nothing");
    }

    /// A token that is allowlisted but was never registered has no budget, so the transfer is
    /// refused rather than treated as unbounded. Fail-closed.
    function test_TransferOfUnregisteredTokenReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 10e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenNotRegistered.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(token.balanceOf(address(bounded)), 1_000e18, "nothing moved");
        assertEq(bounded.nonce(), 0, "a refused intent consumes no nonce");
    }

    // --------------------------------------------------------------- accounting

    /// The declared amount is what the cap counts, and the native counter stays untouched.
    function test_MeteredTransferChargesDeclaredAmount() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        assertTrue(_meteredTransfer(address(token), 40e18, 0), "transfer must execute");

        assertEq(token.balanceOf(recipient), 40e18, "the recipient was paid");
        assertEq(token.balanceOf(address(bounded)), 960e18, "the executor paid");
        assertEq(bounded.tokenSpentToday(address(token)), 40e18, "declared amount charged");
        assertEq(bounded.dailySpent(), 0, "the native counter does not move");
    }

    /// One budget per token and per day, not per intent: two separate calls share it.
    function test_TokenCapIsSharedAcrossIntents() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        assertTrue(_meteredTransfer(address(token), 60e18, 0), "first transfer executes");
        assertFalse(_meteredTransfer(address(token), 60e18, 1), "second exceeds the budget");

        assertEq(bounded.tokenSpentToday(address(token)), 60e18, "only the first was charged");
        assertEq(token.balanceOf(recipient), 60e18, "the second never moved tokens");
        assertEq(bounded.nonce(), 1, "the refused intent consumed no nonce");
    }

    /// Over-cap means nothing happens: the nonce, the charge and the balances all stay put.
    function test_OverCapTokenTransferRevertsAndRollsBack() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 10e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 11e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCapExceeded.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(bounded.tokenSpentToday(address(token)), 0, "no charge was kept");
        assertEq(bounded.nonce(), 0, "no nonce was consumed");
        assertEq(token.balanceOf(address(bounded)), 1_000e18, "the executor kept its balance");
        assertEq(token.balanceOf(recipient), 0, "the recipient received nothing");
    }

    /// Anything that is not exactly a two-word payload is refused before it is decoded.
    function test_MalformedTokenCallReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        bytes memory wellFormed = _transferData(recipient, 1e18);

        Pattern1_PlannerExecutor.Intent memory short = _intent(
            address(token),
            0,
            _resize(wellFormed, 67),
            0
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.MalformedTokenCall.selector);
        bounded.execute(short, _sign(short));

        bytes memory padded = abi.encodePacked(wellFormed, hex"00");
        Pattern1_PlannerExecutor.Intent memory long = _intent(
            address(token),
            0,
            padded,
            0
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.MalformedTokenCall.selector);
        bounded.execute(long, _sign(long));

        assertEq(bounded.nonce(), 0, "neither attempt consumed a nonce");
    }

    /// A token that reports failure through its return value is a failure here, not a
    /// success with no effect.
    function test_MeteredTransferFalseReturnReverts() public {
        FalseReturnToken token = new FalseReturnToken();
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenTransferFailed.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(bounded.tokenSpentToday(address(token)), 0, "the charge was rolled back");
    }

    /// The oldest tokens return nothing. `SafeERC20` treats that as success; this path does
    /// not, because the guarantee is stated for standard ERC-20 only.
    function test_MeteredTransferEmptyReturnReverts() public {
        VoidReturnToken token = new VoidReturnToken();
        token.mint(address(bounded), 100e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenTransferFailed.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(bounded.tokenSpentToday(address(token)), 0, "the charge was rolled back");
    }

    /// A return word that is neither zero nor one is refused explicitly. `abi.decode` would
    /// revert with its own error here, which is not the error this contract promises.
    function test_MeteredTransferNonBooleanReturnReverts() public {
        NonBooleanReturnToken token = new NonBooleanReturnToken();
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenTransferFailed.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(bounded.tokenSpentToday(address(token)), 0, "the charge was rolled back");
    }

    /// A token transfer carrying ether is not a standard ERC-20 call and would mix the two
    /// accounting domains, so it is refused.
    function test_NativeValueOnMeteredPathReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            1,
            _transferData(recipient, 1e18),
            0
        );

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCallForbidden.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(bounded.dailySpent(), 0, "no native spend was recorded");
    }

    // ------------------------------------------------------------- registration

    function test_AddMeteredTokenRejectsZeroAndCodelessAddress() public {
        vm.expectRevert(Pattern2_BoundedAutonomy.InvalidToken.selector);
        bounded.addMeteredToken(address(0), 1e18);

        address eoa = makeAddr("not-a-contract");
        vm.expectRevert(Pattern2_BoundedAutonomy.InvalidToken.selector);
        bounded.addMeteredToken(eoa, 1e18);

        assertEq(bounded.meteredTokenCount(), 0, "nothing was registered");
    }

    /// Registration never grants reach on its own: the token has to be an allowlisted target
    /// first.
    function test_AddMeteredTokenRequiresAllowlistedTarget() public {
        MeterToken token = new MeterToken();

        vm.expectRevert(Pattern2_BoundedAutonomy.TargetNotAllowed.selector);
        bounded.addMeteredToken(address(token), 1e18);

        assertFalse(bounded.meteredTokenKnown(address(token)), "not registered");
    }

    /// A token that was never registered has no entry to change, so setting a cap on it is
    /// refused instead of silently creating one.
    function test_SetTokenCapRejectsUnregisteredToken() public {
        MeterToken token = new MeterToken();
        bounded.addTarget(address(token));

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenNotRegistered.selector);
        bounded.setTokenCap(address(token), 10e18);

        assertEq(bounded.tokenCapPerDay(address(token)), 0, "no cap was created");
        assertFalse(bounded.meteredTokenKnown(address(token)), "still unregistered");
    }

    /// The registry only grows, and re-adding a known token does not duplicate it.
    function test_AddMeteredTokenIsAppendOnlyAndIdempotent() public {
        MeterToken token = new MeterToken();
        bounded.addTarget(address(token));

        bounded.addMeteredToken(address(token), 10e18);
        bounded.addMeteredToken(address(token), 20e18);

        assertEq(bounded.meteredTokenCount(), 1, "the registry holds one entry");
        assertEq(bounded.meteredTokens(0), address(token), "the entry is the token");
        assertEq(bounded.tokenCapPerDay(address(token)), 20e18, "the cap was updated");
    }

    // ------------------------------------------------------------- policy on cap

    function test_SetTokenCapRejectsBelowSpent() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);
        assertTrue(_meteredTransfer(address(token), 40e18, 0), "spend 40");

        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCapBelowSpent.selector);
        bounded.setTokenCap(address(token), 39e18);

        bounded.setTokenCap(address(token), 40e18);
        assertEq(bounded.tokenCapPerDay(address(token)), 40e18, "a cap equal to spend is allowed");
    }

    /// Zero is the stop switch, and it stays available after the token has spent today.
    function test_SetTokenCapZeroStopsTokenEvenAfterSpend() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);
        assertTrue(_meteredTransfer(address(token), 40e18, 0), "spend 40");

        bounded.setTokenCap(address(token), 0);
        assertEq(bounded.tokenSpentToday(address(token)), 40e18, "the record of the spend stays");

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            1
        );
        vm.expectRevert(Pattern2_BoundedAutonomy.TokenCapExceeded.selector);
        bounded.execute(intent, _sign(intent));

        assertEq(token.balanceOf(recipient), 40e18, "only the earlier transfer moved tokens");
    }

    /// Yesterday's spend is not today's, so a positive cap can be set on a new day without
    /// tripping the below-spent rule.
    function test_SetTokenCapPositiveAfterDayResetAllowsSpend() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);
        assertTrue(_meteredTransfer(address(token), 100e18, 0), "spend the whole budget");

        vm.warp(block.timestamp + 1 days);
        bounded.setTokenCap(address(token), 5e18);
        assertEq(bounded.tokenCapPerDay(address(token)), 5e18, "a new day starts from zero");

        assertTrue(_meteredTransfer(address(token), 5e18, 1), "the new budget is spendable");
        assertEq(bounded.tokenSpentToday(address(token)), 5e18, "today's spend is today's only");
    }

    /// Removing and re-adding a target is a policy change, not an accounting reset: the cap
    /// and the spend recorded against the token survive it.
    function test_RemoveAndReAddTargetDoesNotResetTokenSpend() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);
        assertTrue(_meteredTransfer(address(token), 40e18, 0), "spend 40");

        bounded.removeTarget(address(token));
        bounded.addTarget(address(token));

        assertTrue(bounded.meteredTokenKnown(address(token)), "still registered");
        assertEq(bounded.tokenCapPerDay(address(token)), 100e18, "the cap survived");
        assertEq(bounded.tokenSpentToday(address(token)), 40e18, "the spend survived");

        assertTrue(_meteredTransfer(address(token), 60e18, 1), "the remaining 60 is available");
        assertFalse(_meteredTransfer(address(token), 1, 2), "one more unit is over the cap");
    }

    // ------------------------------------------------------- intent equivalence

    /// The duplicated prologue keeps Pattern 1's deadline rule.
    function test_IntentExpiredOnMeteredPathReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            0
        );
        bytes memory signature = _sign(intent);

        vm.warp(intent.deadline + 1);

        vm.expectRevert(Pattern1_PlannerExecutor.IntentExpired.selector);
        bounded.execute(intent, signature);
    }

    /// And so does its nonce rule.
    function test_WrongNonceOnMeteredPathReverts() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 1e18),
            5
        );

        vm.expectRevert(Pattern1_PlannerExecutor.InvalidNonce.selector);
        bounded.execute(intent, _sign(intent));
    }

    /// The metered path emits the same intent event as the generic one, followed by the token
    /// record the cap is made of.
    function test_MeteredTransferEmitsIntentAndRecordedEvents() public {
        MeterToken token = new MeterToken();
        token.mint(address(bounded), 1_000e18);
        bounded.addTarget(address(token));
        bounded.addMeteredToken(address(token), 100e18);

        Pattern1_PlannerExecutor.Intent memory intent = _intent(
            address(token),
            0,
            _transferData(recipient, 40e18),
            0
        );

        vm.expectEmit(true, true, false, true, address(bounded));
        emit Pattern1_PlannerExecutor.IntentExecuted(address(token), 0, 0);
        vm.expectEmit(true, true, false, true, address(bounded));
        emit Pattern2_BoundedAutonomy.TokenTransferRecorded(
            address(token),
            recipient,
            40e18,
            40e18
        );
        bounded.execute(intent, _sign(intent));
    }
}
