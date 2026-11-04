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


interface IDCAToken { function balanceOf(address) external view returns(uint256); function decimals() external view returns(uint8); }
contract DCABot is ReentrancyGuard, Ownable {
    struct Plan { address user;address token;uint256 amountPerInterval;uint256 intervalSeconds;uint256 lastExec;uint256 totalExecutions;uint256 maxExecutions;uint256 remaining;bool active; }
    struct Market { uint256 tokensPerBOT;uint256 reserve;uint256 proceeds; }
    Plan[] public plans;mapping(address=>Market) public markets;mapping(address=>uint256[]) public userPlans;mapping(uint256=>uint256) public minimumOutput;uint256 public planCount;
    event PlanCreated(uint256 indexed pid,address indexed user,address token,uint256 amount,uint256 interval);
    event PlanExecuted(uint256 indexed pid,address indexed user,uint256 amount);
    event TokensPurchased(uint256 indexed pid,address indexed token,uint256 tokens);
    event PlanPaused(uint256 indexed pid,address indexed user);event PlanResumed(uint256 indexed pid,address indexed user);event PlanCancelled(uint256 indexed pid,address indexed user,uint256 refund);
    event MarketConfigured(address indexed token,uint256 tokensPerBOT);event LiquidityAdded(address indexed token,uint256 amount);
    function _token(address token,bytes memory data) private { (bool ok,bytes memory out)=token.call(data);require(ok&&(out.length==0||abi.decode(out,(bool))),"Token transfer failed"); }
    function setMarket(address token,uint256 tokensPerBOT) external onlyOwner { require(token.code.length>0&&tokensPerBOT>0,"Invalid market");require(IDCAToken(token).decimals()==18,"Only 18-decimal assets supported");markets[token].tokensPerBOT=tokensPerBOT;emit MarketConfigured(token,tokensPerBOT); }
    function getMarket(address token) external view returns(uint256 tokensPerBOT,uint256 tokenReserve,uint256 proceedsBOT){Market storage m=markets[token];return(m.tokensPerBOT,m.reserve,m.proceeds);}
    function provideLiquidity(address token,uint256 amount) external onlyOwner nonReentrant { require(markets[token].tokensPerBOT>0&&amount>0,"Invalid liquidity");uint256 beforeBalance=IDCAToken(token).balanceOf(address(this));_token(token,abi.encodeWithSignature("transferFrom(address,address,uint256)",msg.sender,address(this),amount));require(IDCAToken(token).balanceOf(address(this))==beforeBalance+amount,"Unsupported transfer-fee token");markets[token].reserve+=amount;emit LiquidityAdded(token,amount); }
    function withdrawLiquidity(address token,uint256 amount) external onlyOwner nonReentrant { require(amount<=markets[token].reserve,"Insufficient liquidity");markets[token].reserve-=amount;_token(token,abi.encodeWithSignature("transfer(address,uint256)",owner(),amount)); }
    function withdrawProceeds(address token) external onlyOwner nonReentrant { uint256 amount=markets[token].proceeds;require(amount>0,"No proceeds");markets[token].proceeds=0;(bool ok,)=owner().call{value:amount}("");require(ok,"Transfer failed"); }
    function createPlan(address token,uint256 amountPerInterval,uint256 intervalSeconds,uint256 maxExecutions) external payable nonReentrant returns(uint256 pid) {
        require(amountPerInterval>0&&intervalSeconds>0&&maxExecutions>0,"Invalid plan");require(msg.value==amountPerInterval*maxExecutions,"Invalid prepayment");uint256 output=amountPerInterval*markets[token].tokensPerBOT/1 ether;require(output>0&&markets[token].reserve>=output,"Market unavailable");pid=plans.length;plans.push(Plan(msg.sender,token,amountPerInterval,intervalSeconds,block.timestamp,0,maxExecutions,msg.value,true));minimumOutput[pid]=output;userPlans[msg.sender].push(pid);planCount++;emit PlanCreated(pid,msg.sender,token,amountPerInterval,intervalSeconds);
    }
    function executePlan(uint256 pid) external nonReentrant {
        Plan storage p=plans[pid];require(p.active&&p.totalExecutions<p.maxExecutions,"Plan inactive");require(block.timestamp>=p.lastExec+p.intervalSeconds,"Interval not elapsed");require(p.remaining>=p.amountPerInterval,"Prepayment exhausted");Market storage m=markets[p.token];uint256 output=p.amountPerInterval*m.tokensPerBOT/1 ether;require(output>=minimumOutput[pid]&&output<=m.reserve,"Price or liquidity unavailable");p.lastExec=block.timestamp;p.totalExecutions++;p.remaining-=p.amountPerInterval;if(p.totalExecutions==p.maxExecutions)p.active=false;m.reserve-=output;m.proceeds+=p.amountPerInterval;_token(p.token,abi.encodeWithSignature("transfer(address,uint256)",p.user,output));emit TokensPurchased(pid,p.token,output);emit PlanExecuted(pid,p.user,p.amountPerInterval);
    }
    function cancelSubscription(uint256 pid) external nonReentrant { Plan storage p=plans[pid];require(msg.sender==p.user,"Not your plan");uint256 refund=p.remaining;require(refund>0,"No remaining funds");p.active=false;p.remaining=0;(bool ok,)=msg.sender.call{value:refund}("");require(ok,"Refund failed");emit PlanCancelled(pid,msg.sender,refund); }
    function pausePlan(uint256 pid) external { Plan storage p=plans[pid];require(msg.sender==p.user||msg.sender==owner(),"Not authorized");require(p.active,"Already paused");p.active=false;emit PlanPaused(pid,p.user); }
    function resumePlan(uint256 pid) external { Plan storage p=plans[pid];require(msg.sender==p.user||msg.sender==owner(),"Not authorized");require(!p.active&&p.remaining>0&&p.totalExecutions<p.maxExecutions,"Cannot resume");p.active=true;emit PlanResumed(pid,p.user); }
    function getPlan(uint256 pid) external view returns(address user,address token,uint256 amount,uint256 interval,uint256 lastExec,uint256 totalExec,uint256 maxExec,bool active) { Plan storage p=plans[pid];return(p.user,p.token,p.amountPerInterval,p.intervalSeconds,p.lastExec,p.totalExecutions,p.maxExecutions,p.active); }
    function getRemaining(uint256 pid) external view returns(uint256) { return plans[pid].remaining; }
}

