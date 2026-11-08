// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./Pattern1_PlannerExecutor.sol";

contract Pattern2_BoundedAutonomy is Pattern1_PlannerExecutor {
    // تنظیمات امنیتی
    uint256 public spendingCapPerDay;
    uint256 public spentToday;
    uint256 public lastResetDay;
    
    mapping(address => bool) public allowlistedTargets;
    bool public emergencyStopped;
    
    address public admin;

    // رویدادها
    event TargetAllowlisted(address indexed target);
    event TargetRemoved(address indexed target);
    event SpendingCapUpdated(uint256 newCap);
    event EmergencyStopped();
    event EmergencyResumed();

    // خطاها
    error NotAdmin();
    error TargetNotAllowed();
    error SpendingCapExceeded();
    error EmergencyStopActive();

    constructor(
        address _agentSigner,
        uint256 _initialSpendingCapPerDay
    ) Pattern1_PlannerExecutor(_agentSigner) {
        admin = msg.sender;
        spendingCapPerDay = _initialSpendingCapPerDay;
        lastResetDay = block.timestamp / 1 days;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier notStopped() {
        if (emergencyStopped) revert EmergencyStopActive();
        _;
    }

    // مدیریت لیست سفید
    function addTarget(address _target) external onlyAdmin {
        allowlistedTargets[_target] = true;
        emit TargetAllowlisted(_target);
    }

    function removeTarget(address _target) external onlyAdmin {
        allowlistedTargets[_target] = false;
        emit TargetRemoved(_target);
    }

    // مدیریت سقف هزینه
    function setSpendingCap(uint256 _newCap) external onlyAdmin {
        spendingCapPerDay = _newCap;
        emit SpendingCapUpdated(_newCap);
    }

    // توقف اضطراری
    function emergencyStop() external onlyAdmin {
        emergencyStopped = true;
        emit EmergencyStopped();
    }

    function resume() external onlyAdmin {
        emergencyStopped = false;
        emit EmergencyResumed();
    }

    // بازنویسی execute برای اعمال محدودیت‌ها
    function execute(
        Intent calldata intent,
        bytes calldata signature
    ) public override notStopped {
        // بررسی لیست سفید
        if (!allowlistedTargets[intent.target]) revert TargetNotAllowed();

        // بررسی سقف هزینه روزانه
        uint256 currentDay = block.timestamp / 1 days;
        if (currentDay > lastResetDay) {
            spentToday = 0;
            lastResetDay = currentDay;
        }

        if (spentToday + intent.value > spendingCapPerDay) {
            revert SpendingCapExceeded();
        }

        // فراخوانی تابع اصلی (Pattern 1)
        super.execute(intent, signature);

        // به‌روزرسانی هزینه
        spentToday += intent.value;
    }
}