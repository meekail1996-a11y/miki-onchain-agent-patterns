// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pattern1_PlannerExecutor.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract Pattern2_BoundedAutonomy is Pattern1_PlannerExecutor, ReentrancyGuard {
    error TargetNotAllowed();
    error SpendingCapExceeded();
    error ContractPaused();
    error InvalidTarget();

    address public immutable admin;
    uint256 public spendingCapPerDay;
    uint256 public dailySpent;
    uint256 public lastSpendingResetDay;
    bool public paused;

    mapping(address => bool) public allowedTargets;

    event TargetAdded(address indexed target);
    event TargetRemoved(address indexed target);
    event SpendingCapUpdated(uint256 newCap);
    event SpendingRecorded(uint256 amount, uint256 dailySpent);
    event EmergencyStop(bool status);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
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

    // Override execute - must match Pattern1 visibility (public) and data location (memory)
    function execute(Intent memory intent, bytes memory signature) public override nonReentrant {
        if (paused) revert ContractPaused();
        if (!allowedTargets[intent.target]) revert TargetNotAllowed();

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
}
