// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pattern1_PlannerExecutor.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Pattern2_BoundedAutonomy is Pattern1_PlannerExecutor, ReentrancyGuard {
    error TargetNotAllowed();
    error SpendingCapExceeded();
    error ContractPaused();
    error InvalidTarget();
    error NotAdmin();

    // M3 metered-token path
    error TokenNotRegistered();
    error TokenCallForbidden();
    error MalformedTokenCall();
    error TokenCapExceeded();
    error TokenCapBelowSpent();
    error InvalidToken();
    error TokenTransferFailed();

    // The four selectors that can create or spend an allowance.
    bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb;
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd;
    bytes4 private constant APPROVE_SELECTOR = 0x095ea7b3;
    bytes4 private constant INCREASE_ALLOWANCE_SELECTOR = 0x39509351;

    address public immutable admin;
    uint256 public spendingCapPerDay;
    uint256 public dailySpent;
    uint256 public lastSpendingResetDay;
    bool public paused;

    mapping(address => bool) public allowedTargets;

    // Metered tokens. The array is the published, append-only registry: there is no
    // removal function, and `setTokenCap(token, 0)` is how a token is stopped.
    address[] public meteredTokens;
    mapping(address => bool) public meteredTokenKnown;
    mapping(address => uint256) public tokenCapPerDay;
    mapping(address => uint256) public tokenSpentToday;
    mapping(address => uint256) public lastTokenResetDay;

    event TargetAdded(address indexed target);
    event TargetRemoved(address indexed target);
    event SpendingCapUpdated(uint256 newCap);
    event SpendingRecorded(uint256 amount, uint256 dailySpent);
    event EmergencyStop(bool status);
    event MeteredTokenAdded(address indexed token, uint256 capPerDay);
    event TokenCapUpdated(address indexed token, uint256 newCap);
    event TokenTransferRecorded(
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 spentToday
    );

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    // Constructor: (signer, spendingCap) - admin is msg.sender
    constructor(
        address _agentSigner,
        uint256 _spendingCapPerDay
    ) Pattern1_PlannerExecutor(_agentSigner) {
        admin = msg.sender;
        spendingCapPerDay = _spendingCapPerDay;
        lastSpendingResetDay = block.timestamp / 1 days;
    }

    function addTarget(address target) external onlyAdmin {
        if (target == address(0)) revert InvalidTarget();
        allowedTargets[target] = true;
        emit TargetAdded(target);
    }

    function removeTarget(address target) external onlyAdmin {
        allowedTargets[target] = false;
        emit TargetRemoved(target);
    }

    function setSpendingCap(uint256 _newCap) external onlyAdmin {
        spendingCapPerDay = _newCap;
        emit SpendingCapUpdated(_newCap);
    }

    function emergencyStop(bool stopped) external onlyAdmin {
        paused = stopped;
        emit EmergencyStop(stopped);
    }

    /// @notice Append a token to the metered registry. The registry only grows.
    /// @dev The token must already be an allowlisted target, so registration never grants
    /// reach on its own. Re-adding a known token is idempotent and updates its cap.
    function addMeteredToken(address token, uint256 capPerDay) external onlyAdmin {
        if (token == address(0) || token.code.length == 0) revert InvalidToken();
        if (!allowedTargets[token]) revert TargetNotAllowed();

        if (!meteredTokenKnown[token]) {
            meteredTokenKnown[token] = true;
            meteredTokens.push(token);
            lastTokenResetDay[token] = block.timestamp / 1 days;
        }

        tokenCapPerDay[token] = capPerDay;
        emit MeteredTokenAdded(token, capPerDay);
    }

    /// @notice Stop a token with a zero cap, or change its budget.
    /// @dev A positive cap below what the token has already spent today is refused, so
    /// `tokenSpentToday <= tokenCapPerDay` holds for every non-zero cap at every moment.
    function setTokenCap(address token, uint256 cap) external onlyAdmin {
        if (!meteredTokenKnown[token]) revert TokenNotRegistered();

        uint256 spentToday = block.timestamp / 1 days > lastTokenResetDay[token]
            ? 0
            : tokenSpentToday[token];

        if (cap != 0 && cap < spentToday) revert TokenCapBelowSpent();

        tokenCapPerDay[token] = cap;
        emit TokenCapUpdated(token, cap);
    }

    /// @notice How many tokens the registry holds. The list is never shortened.
    function meteredTokenCount() external view returns (uint256) {
        return meteredTokens.length;
    }

    // Override execute - must match Pattern1 visibility (public) and data location (memory)
    function execute(Intent memory intent, bytes memory signature) public override nonReentrant {
        if (paused) revert ContractPaused();
        if (!allowedTargets[intent.target]) revert TargetNotAllowed();

        bytes4 selector = _selectorOf(intent.data);
        if (_isMeteredSelector(selector)) {
            _executeMeteredTransfer(intent, signature, selector);
            return;
        }

        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastSpendingResetDay) {
            dailySpent = 0;
            lastSpendingResetDay = currentDay;
        }

        if (dailySpent + intent.value > spendingCapPerDay) {
            revert SpendingCapExceeded();
        }

        dailySpent += intent.value;
        emit SpendingRecorded(intent.value, dailySpent);

        // Delegate to Pattern1
        super.execute(intent, signature);
    }

    /// @notice The metered path: a direct, standard ERC-20 `transfer` out of the executor,
    /// charged against that token's own daily cap before the call is made.
    /// @dev Fail-closed by construction. Only `transfer` is accepted; `approve`,
    /// `increaseAllowance` and `transferFrom` are refused on the target, so this path cannot
    /// create an allowance or spend one. An allowance that already exists at activation time
    /// is a migration prerequisite, not something this path observes.
    function _executeMeteredTransfer(
        Intent memory intent,
        bytes memory signature,
        bytes4 selector
    ) private {
        if (intent.value != 0) revert TokenCallForbidden();
        if (selector != TRANSFER_SELECTOR) revert TokenCallForbidden();
        if (!meteredTokenKnown[intent.target]) revert TokenNotRegistered();
        if (intent.data.length != 68) revert MalformedTokenCall();

        bytes memory payload = intent.data;
        address to;
        uint256 amount;
        assembly {
            to := and(mload(add(payload, 36)), 0xffffffffffffffffffffffffffffffffffffffff)
            amount := mload(add(payload, 68))
        }

        _consumeIntent(intent, signature);

        address token = intent.target;
        _rollTokenDay(token);

        if (tokenSpentToday[token] + amount > tokenCapPerDay[token]) {
            revert TokenCapExceeded();
        }

        tokenSpentToday[token] += amount;
        emit TokenTransferRecorded(token, to, amount, tokenSpentToday[token]);

        (bool ok, bytes memory returndata) = token.call(payload);
        if (!ok || returndata.length != 32) revert TokenTransferFailed();

        uint256 returned;
        assembly {
            returned := mload(add(returndata, 32))
        }
        if (returned != 1) revert TokenTransferFailed();
    }

    /// @dev Deliberately duplicated from Pattern 1 rather than carved out of it. Pattern 1 is
    /// the reference the other patterns inherit, and its `_executeIntent` discards the
    /// callee's return value, which this path has to read. Two tests pin the equivalence of
    /// the deadline and nonce rules on both paths.
    function _consumeIntent(Intent memory intent, bytes memory signature) private {
        if (block.timestamp > intent.deadline) revert IntentExpired();
        if (intent.nonce != nonce) revert InvalidNonce();

        _verifyIntentSignature(intent, signature);

        nonce++;

        emit IntentExecuted(intent.target, intent.value, intent.nonce);
    }

    function _rollTokenDay(address token) private {
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastTokenResetDay[token]) {
            tokenSpentToday[token] = 0;
            lastTokenResetDay[token] = currentDay;
        }
    }

    function _selectorOf(bytes memory data) private pure returns (bytes4 selector) {
        if (data.length < 4) return selector;
        assembly {
            selector := mload(add(data, 32))
        }
    }

    function _isMeteredSelector(bytes4 selector) private pure returns (bool) {
        return
            selector == TRANSFER_SELECTOR ||
            selector == TRANSFER_FROM_SELECTOR ||
            selector == APPROVE_SELECTOR ||
            selector == INCREASE_ALLOWANCE_SELECTOR;
    }
}
