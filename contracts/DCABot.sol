// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

abstract contract ReentrancyGuard {
    bool private _nonReentrant;
    constructor() { _nonReentrant = false; }
    modifier nonReentrant() {
        require(!_nonReentrant, "ReentrancyGuard: reentrant call");
        _nonReentrant = true;
        _;
        _nonReentrant = false;
    }
}
abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor() { _owner = msg.sender; emit OwnershipTransferred(address(0), _owner); }
    modifier onlyOwner() { require(_owner == msg.sender, "Ownable: caller is not the owner"); _; }
    function owner() public view returns (address) { return _owner; }
}

contract DCABot is ReentrancyGuard, Ownable {
    struct Plan {
        address user;
        address token;
        uint256 amountPerInterval;
        uint256 intervalSeconds;
        uint256 lastExec;
        uint256 totalExecutions;
        uint256 maxExecutions;
        uint256 remaining; // ADD: unspent prepaid balance refundable on cancel
        bool active;
    }
    Plan[] public plans;
    mapping(address => uint256[]) public userPlans;
    uint256 public planCount;

    event PlanCreated(uint256 indexed pid, address indexed user, address token, uint256 amount, uint256 interval);
    event PlanExecuted(uint256 indexed pid, address indexed user, uint256 amount);
    event PlanPaused(uint256 indexed pid, address indexed user);
    event PlanResumed(uint256 indexed pid, address indexed user);
    event PlanCancelled(uint256 indexed pid, address indexed user, uint256 refund);

    function createPlan(address token, uint256 amountPerInterval, uint256 intervalSeconds, uint256 maxExecutions)
        external payable nonReentrant returns (uint256) {
        require(amountPerInterval > 0, "Zero amount");
        require(intervalSeconds > 0, "Zero interval");
        require(maxExecutions > 0, "Zero max executions");
        // FIX: was onlyOwner with no funds — a DCA plan is created by the user
        // whose deposit is being managed (user plane, rule 4). Also require the
        // full upfront prepayment (amountPerInterval * maxExecutions) so every
        // planned buy is actually funded; previously plans were pure paper.
        require(msg.value == amountPerInterval * maxExecutions, "Invalid prepayment");
        Plan storage p = plans.push();
        p.user = msg.sender;
        p.token = token;
        p.amountPerInterval = amountPerInterval;
        p.intervalSeconds = intervalSeconds;
        p.lastExec = block.timestamp;
        p.totalExecutions = 0;
        p.maxExecutions = maxExecutions;
        p.remaining = msg.value;
        p.active = true;
        uint256 pid = plans.length - 1;
        planCount = pid + 1;
        userPlans[msg.sender].push(pid);
        emit PlanCreated(pid, msg.sender, token, amountPerInterval, intervalSeconds);
        return pid;
    }

    function executePlan(uint256 pid) external nonReentrant {
        Plan storage p = plans[pid];
        require(p.active, "Plan inactive");
        require(p.totalExecutions < p.maxExecutions, "Max executions reached");
        require(block.timestamp >= p.lastExec + p.intervalSeconds, "Interval not elapsed");
        require(p.remaining >= p.amountPerInterval, "Prepaid funds exhausted"); // defensive
        p.lastExec = block.timestamp;
        p.totalExecutions += 1;
        // FIX: prepaid balance was never decremented (no deposit system existed
        // and no funds flowed). Deduct one installment per executed buy so the
        // unspent remainder is always well defined.
        p.remaining -= p.amountPerInterval;
        if (p.totalExecutions == p.maxExecutions) p.active = false;
        emit PlanExecuted(pid, p.user, p.amountPerInterval);
    }

    function cancelSubscription(uint256 pid) external nonReentrant {
        // FIX: no cancel path existed — unspent prepaid funds were permanently
        // stuck. Refund them to the plan owner and deactivate.
        Plan storage p = plans[pid];
        require(p.user == msg.sender, "Not your plan");
        p.active = false;
        uint256 refund = p.remaining;
        p.remaining = 0;
        (bool ok, ) = msg.sender.call{value: refund}("");
        require(ok, "ETH transfer failed");
        emit PlanCancelled(pid, msg.sender, refund);
    }

    function pausePlan(uint256 pid) external {
        // FIX: was onlyOwner — pausing one's own DCA plan is a user action, not
        // protocol administration. Owner retained as admin fallback.
        Plan storage p = plans[pid];
        require(p.user == msg.sender || msg.sender == owner(), "Not authorized");
        require(p.active, "Already paused");
        p.active = false;
        emit PlanPaused(pid, p.user);
    }

    function resumePlan(uint256 pid) external {
        // FIX: was onlyOwner — plan owner may resume their own plan.
        Plan storage p = plans[pid];
        require(p.user == msg.sender || msg.sender == owner(), "Not authorized");
        require(!p.active, "Already active");
        p.active = true;
        emit PlanResumed(pid, p.user);
    }

    function getPlan(uint256 pid) external view returns (address user, address token, uint256 amount, uint256 interval, uint256 lastExec, uint256 totalExec, uint256 maxExec, bool active) {
        Plan storage p = plans[pid];
        return (p.user, p.token, p.amountPerInterval, p.intervalSeconds, p.lastExec, p.totalExecutions, p.maxExecutions, p.active);
    }
    // ADD: exposes the refundable prepaid balance without changing getPlan's ABI.
    function getRemaining(uint256 pid) external view returns (uint256) { return plans[pid].remaining; }
}
