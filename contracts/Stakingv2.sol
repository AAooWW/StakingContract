// pragma solidity ^0.8.13;


// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/math/SafeMath.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/utils/Context.sol";
// import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";



// /**
//   @title Staking implementation based on WiCrypt reward distribution model
//   @author tmortred
//   @notice implemented main interactive functions for staking
//  */
// contract StakingV2 is Ownable, ReentrancyGuard {
//   using SafeMath for uint256;
//   using SafeERC20 for IERC20;

//   struct UserInfo {
//     uint256[] stakingIds;
//     uint256 lastStakeTime;
//     uint256 rewardDebt;
//   }

//   uint256 constant MAX_BPS = 10_000;
//   uint256 constant WEEKS_OF_ONE_YEAR = 52;
//   uint256 constant ONE_MONTH = 30 * 24 * 60 * 60;
//   uint256 constant ONE_WEEK = 8 * 60 * 60;
//   uint256 constant MAX_APR = 25_000;
//   uint256 constant MIN_APR = 5_000;

//   enum LOCK_PERIOD {
//     NO_LOCK,
//     THREE_MONTHS,
//     SIX_MONTHS,
//     NINE_MONTHS,
//     TWELVE_MONTHS
//   }

//   address private _government;

//   IERC20 public token;
//   mapping (uint256 => uint256) public rewardDrop;


//   address[] public stakers;
//   mapping (address => UserInfo) public userInfo;
//   mapping (uint256 => uint256) public deposits;
//   mapping (uint256 => LOCK_PERIOD) public lockPeriod;
//   mapping (uint256 => address) public depositor;
//   mapping (uint256 => uint256) public stakeTime;
//   mapping (address => uint256) public unclaimed;

//   uint256 public lastRewardWeek;
//   uint256 immutable public startBlockTime;

//   uint256[] public scoreLevels;
//   mapping(uint256 => uint256) public rewardMultiplier;
//   uint256 public counter;
//   uint256 public reductionPercent = 3_000;
//   uint256 public lockTime = ONE_WEEK;           // 7 days
//   uint256 public actionLimit = 24 * 3600;           // 1 day
//   uint256 public maxActiveStake = 30;
//   uint256 public totalStaked;
//   uint256 public treasury;
//   mapping (uint256 => uint256) public totalWeightedScore;

//   modifier onlyGovernment {
//     require(msg.sender == _government, "!government");
//     _;
//   }

//   event Deposit(address indexed user, uint256 stakingId, uint256 amount, LOCK_PERIOD lockPeriod);
//   event Withdraw(address indexed user, uint256 amount, LOCK_PERIOD lockPeriod, uint256 rewardAmount);
//   event ForceUnlock(address indexed user, uint256 stakingId, uint256 amount, LOCK_PERIOD lockPeriod, uint256 offset);
//   event RewardClaim(address indexed user, uint256 amount);
//   event ReductionPercentChanged(uint256 oldReduction, uint256 newReduction);
//   event GovernanceTransferred(address oldGov, address newGov);
//   event LockTimeChanged(uint256 oldLockTime, uint256 newLockTime);
//   event ActionLimitChanged(uint256 oldActionLimit, uint256 newActionLimit);
//   event MaxActiveStakeUpdated(uint256 oldMaxActiveStake, uint256 newMaxActiveStake);
//   event RewardAdded(uint256 added, uint256 treasury);

//   constructor(address _token, uint256 _rewardDrop) public {
//     require(_rewardDrop != 0, "reward drop can't be zero");
//     token = IERC20(_token);
//     startBlockTime = block.timestamp;
//     rewardDrop[0] = _rewardDrop;

//     _government = msg.sender;

//     scoreLevels.push(0);
//     scoreLevels.push(500);
//     scoreLevels.push(1000);
//     scoreLevels.push(2000);
//     scoreLevels.push(4000);
//     scoreLevels.push(8000);
//     scoreLevels.push(16000);
//     scoreLevels.push(32000);
//     scoreLevels.push(50000);
//     scoreLevels.push(100000);
//     rewardMultiplier[scoreLevels[0]] = 1000;
//     rewardMultiplier[scoreLevels[1]] = 1025;
//     rewardMultiplier[scoreLevels[2]] = 1050;
//     rewardMultiplier[scoreLevels[3]] = 1100;
//     rewardMultiplier[scoreLevels[4]] = 1200;
//     rewardMultiplier[scoreLevels[5]] = 1400;
//     rewardMultiplier[scoreLevels[6]] = 1800;
//     rewardMultiplier[scoreLevels[7]] = 2600;
//     rewardMultiplier[scoreLevels[8]] = 3500;
//     rewardMultiplier[scoreLevels[9]] = 6000;
//   }

//   /**
//     @notice
//      a user can stake several times but only without lock period.
//      locked staking is possible only one time for one wallet.
//      locked staking and standard staking can't be combined.
//     @param _amount the amount of token to stake
//     @param _lockPeriod enum value for representing lock period
//    */
//   function stake(uint256 _amount, LOCK_PERIOD _lockPeriod) external nonReentrant {
//     // check if stake action valid
//     require(_amount > 0, "zero amount");
//     uint256 diff = block.timestamp.sub(userInfo[msg.sender].lastStakeTime);
//     require(diff > actionLimit, "staking too much in short period is not valid");
//     uint256[] memory stakingIds = userInfo[msg.sender].stakingIds;
//     if (stakingIds.length != 0) {
//       require(lockPeriod[stakingIds[0]] == LOCK_PERIOD.NO_LOCK && _lockPeriod == LOCK_PERIOD.NO_LOCK, "multi-staking works only for standard vault");
//       require(stakingIds.length < maxActiveStake, "exceed maxActiveStake");
//     }

//     // update state variables
//     counter = counter.add(1);
//     if (stakingIds.length == 0) {
//       stakers.push(msg.sender);
//     }
//     deposits[counter] = _amount;
//     totalStaked = totalStaked.add(_amount);
//     depositor[counter] = msg.sender;
//     stakeTime[counter] = block.timestamp;
//     userInfo[msg.sender].lastStakeTime = block.timestamp;
//     lockPeriod[counter] = _lockPeriod;
//     userInfo[msg.sender].stakingIds.push(counter);

//     // transfer tokens
//     token.safeTransferFrom(msg.sender, address(this), _amount);

//     emit Deposit(msg.sender, counter, _amount, _lockPeriod);
//   }

//   /**
//    * @notice
//    *  withdraw tokens with reward gain
//    *  users can't unstake partial amount
//    */
//   function unstake() external nonReentrant {
//     // check if unstake action is valid
//     require(userInfo[msg.sender].stakingIds.length > 0, "no active staking");
//     uint256 diff = block.timestamp.sub(userInfo[msg.sender].lastStakeTime);
//     require(diff > lockTime, "can't unstake within minimum lock time");
//     uint256 stakingId = userInfo[msg.sender].stakingIds[0];
//     uint256 lock = uint256(lockPeriod[stakingId]).mul(3).mul(ONE_MONTH);
//     require(diff > lock, "locked");
    
//     // calculate the reward amount
//     uint256 reward = _pendingReward(msg.sender).sub(userInfo[msg.sender].rewardDebt);
//     if (reward > treasury) {
//       unclaimed[msg.sender] = reward.sub(treasury);
//       reward = treasury;
//       treasury = 0;
//     } else {
//       treasury = treasury.sub(reward);
//     }
    
//     // transfer tokens to the msg.sender
//     uint256 stakeAmount = _getTotalStaked(msg.sender);
//     token.safeTransfer(msg.sender, stakeAmount.add(reward));

//     // update the state variables
//     totalStaked = totalStaked.sub(stakeAmount);
//     delete userInfo[msg.sender];
//     for (uint i = 0; i < stakers.length; i++) {
//       if (stakers[i] == msg.sender) {
//         stakers[i] = stakers[stakers.length - 1];
//         stakers.pop();
//         break;
//       }
//     }

//     emit Withdraw(msg.sender, stakeAmount, lockPeriod[stakingId], reward);
//   }

//   /**
//    * @notice
//    *  claim reward accumulated so far
//    * @dev
//    *  claimed reward amount is reflected when next claim reward or standard unstake action
//    */
//   function claimReward() external {
//     require(treasury > 0, "reward pool is empty");
    
//     uint256 claimed;
//     if (unclaimed[msg.sender] > 0) {
//       require(unclaimed[msg.sender] <= treasury, "insufficient");
//       token.safeTransfer(msg.sender, unclaimed[msg.sender]);
//       claimed = unclaimed[msg.sender];
//       delete unclaimed[msg.sender];
//     } else {
//       uint256 reward = _pendingReward(msg.sender).sub(userInfo[msg.sender].rewardDebt);
//       require(reward > 0, "pending reward amount is zero");

//       if (reward >= treasury) {
//         reward = treasury;
//         treasury = 0;
//       } else {
//         treasury = treasury.sub(reward);
//       }
      
//       token.safeTransfer(msg.sender, reward);
//       claimed = reward;
//       userInfo[msg.sender].rewardDebt = userInfo[msg.sender].rewardDebt.add(reward);
//     }
    
//     emit RewardClaim(msg.sender, claimed);
//   }

//   /**
//    * @notice 
//    *  a user can unstake before lock time ends but original fund is 
//    *  reducted by up to 30 percent propertional to the end of lockup
//    * @dev can't call this function when lockup released
//    * @param stakingId staking id to unlock
//    */
//   function forceUnlock(uint256 stakingId) external nonReentrant {
//     // check if it is valid
//     require(msg.sender == depositor[stakingId], "!depositor");
//     uint256 diff = block.timestamp.sub(stakeTime[stakingId]);
//     require(diff > lockTime, "can't unstake within minimum lock time");

//     uint256 lock = uint256(lockPeriod[stakingId]).mul(3).mul(ONE_MONTH);
//     require(diff < lock, "unlocked status");
//     uint256 offset = lock.sub(diff);
//     //  deposits * 30% * offset / lock
//     uint256 reduction = deposits[stakingId].mul(reductionPercent).div(MAX_BPS).mul(offset).div(lock);
    
//     token.safeTransfer(msg.sender, deposits[stakingId].sub(reduction));
    
//     emit ForceUnlock(msg.sender, stakingId, deposits[stakingId], lockPeriod[stakingId], offset);

//     // update the state variables
//     totalStaked = totalStaked.sub(deposits[stakingId]);
//     deposits[stakingId] = 0;
//     delete userInfo[msg.sender];
//     for (uint i = 0; i < stakers.length; i++) {
//       if (stakers[i] == msg.sender) {
//         stakers[i] = stakers[stakers.length - 1];
//         stakers.pop();
//         break;
//       }
//     }
//   }

//   /**
//    * @notice
//    *  reflect the total weighted score calculated from the external script(off-chain) to the contract.
//    *  this function supposed to be called every week.
//    *  only goverment can call this function
//    * @param _totalWeightedScore total weighted score
//    * @param weekNumber the week counter
//    */
//   function updatePool(uint256 _totalWeightedScore, uint256 weekNumber) external onlyGovernment {
//     require(weekNumber > lastRewardWeek, "invalid call");
    
//     for (uint256 i = lastRewardWeek + 1; i <= weekNumber; i++) {
//       totalWeightedScore[i - 1] = _totalWeightedScore;
//       rewardDrop[i] = rewardDrop[i-1].sub(rewardDrop[i-1].div(100));
//       uint256 _apr = rewardDrop[i].mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
//       if (_apr > MAX_APR) {
//         rewardDrop[i] = totalStaked.mul(MAX_APR).div(WEEKS_OF_ONE_YEAR).div(MAX_BPS);
//       } else if (_apr < MIN_APR) {
//         rewardDrop[i] = totalStaked.mul(MIN_APR).div(WEEKS_OF_ONE_YEAR).div(MAX_BPS).add(1);
//       }
//     }

//     lastRewardWeek = weekNumber;
//   }

//   //////////////////////////////////////
//   ////        View functions        ////
//   //////////////////////////////////////

  
//   /**
//    * @notice
//    *  apy value from the staking logic model
//    * @dev can't be over `MAX_APY`
//    * @return _apr annual percentage yield
//    */
//   function apr() external view returns (uint256) {
//     uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
//     uint256 _apr;
//     if (totalStaked == 0) {
//       _apr = MAX_APR;
//     } else {
//       _apr = rewardDrop[current].mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
//     }
    
//     return _apr;
//   }

//   function getLengthOfStakers() external view returns (uint256) {
//     return stakers.length;
//   }

//   function getTotalStaked(address user) external view returns (uint256) {
//     return _getTotalStaked(user);
//   }

//   function getStakingIds(address user) external view returns (uint256[] memory) {
//     return userInfo[user].stakingIds;
//   }

//   function getStakingInfo(uint256 stakingId) external view returns (address, uint256, uint256, LOCK_PERIOD) {
//     return (depositor[stakingId], deposits[stakingId], stakeTime[stakingId], lockPeriod[stakingId]);
//   }

//   function getWeightedScore(address _user, uint256 weekNumber) external view returns (uint256) {
//     return _getWeightedScore(_user, weekNumber);
//   }

//   function pendingReward(address _user) external view returns (uint256) {
//     if (unclaimed[_user] > 0) {
//       return unclaimed[_user];
//     } else {
//       return _pendingReward(_user).sub(userInfo[_user].rewardDebt);
//     }
//   }

//   function government() external view returns (address) {
//     return _government;
//   }

//   //////////////////////////////
//   ////    Admin functions   ////
//   //////////////////////////////

//   function addReward(uint256 amount) external onlyOwner {
//     require(IERC20(token).balanceOf(msg.sender) >= amount, "not enough tokens to deliver");
//     IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
//     treasury = treasury.add(amount);

//     emit RewardAdded(amount, treasury);
//   }

//   function setLockTime(uint256 _lockTime) external onlyOwner {
//     require(_lockTime != 0, "!zero");
//     emit LockTimeChanged(lockTime, _lockTime);
//     lockTime = _lockTime;
//   }

//   function setReductionPercent(uint256 _reductionPercent) external onlyOwner {
//     require(_reductionPercent < MAX_BPS, "overflow");
//     emit ReductionPercentChanged(reductionPercent, _reductionPercent);
//     reductionPercent = _reductionPercent;
//   }

//   function setRewardDrop(uint256 _rewardDrop) external onlyOwner {
//     uint256 _apr = _rewardDrop.mul(WEEKS_OF_ONE_YEAR).mul(MAX_BPS).div(totalStaked);
//     require(_apr >= MIN_APR, "not meet MIN APR");
//     require(_apr <= MAX_APR, "not meet MAX APR");
//     uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
//     rewardDrop[current] = _rewardDrop;    // check carefully later whether current or current - 1
//   }

//   function transferGovernance(address _newGov) external onlyOwner {
//     require(_newGov != address(0), "new governance is the zero address");
//     emit GovernanceTransferred(_government, _newGov);
//     _government = _newGov;
//   }

//   function setActionLimit(uint256 _actionLimit) external onlyOwner {
//     require(_actionLimit != 0, "!zero");
//     emit ActionLimitChanged(actionLimit, _actionLimit);
//     actionLimit = _actionLimit;
//   }

//   function setMaxActiveStake(uint256 _maxActiveStake) external onlyOwner {
//     require(_maxActiveStake !=0, "!zero");
//     emit MaxActiveStakeUpdated(maxActiveStake, _maxActiveStake);
//     maxActiveStake = _maxActiveStake;
//   }

//   /////////////////////////////////
//   ////    Internal functions   ////
//   /////////////////////////////////

//   // get the total staked amount of user
//   function _getTotalStaked(address user) internal view returns (uint256) {
//     uint256 _totalStaked = 0;
//     uint256[] memory stakingIds = userInfo[user].stakingIds;
//     for (uint i = 0; i < stakingIds.length; i++) {
//       uint256 stakingId = stakingIds[i];
//       _totalStaked = _totalStaked.add(deposits[stakingId]);
//     }

//     return _totalStaked;
//   }

//   function _pendingReward(address _user) internal view returns (uint256) {
//     uint256 reward = 0;
//     uint256 current = block.timestamp.sub(startBlockTime).div(ONE_WEEK);
//     for (uint i = 0; i < current; i++) {
//       uint256 weightedScore = _getWeightedScore(_user, i);
//       if (totalWeightedScore[i] != 0) {
//         reward = reward.add(rewardDrop[i].mul(weightedScore).div(totalWeightedScore[i]));
//       }
//     }
//     return reward;
//   }

//   function _getWeightedScore(address _user, uint256 weekNumber) internal view returns (uint256) {
//     // calculate the basic score
//     uint256 score = 0;
//     uint256[] memory stakingIds = userInfo[_user].stakingIds;
//     for (uint i = 0; i < stakingIds.length; i++) {
//       uint256 stakingId = stakingIds[i];
//       uint256 _score = getScore(stakingId, weekNumber);
//       score = score.add(_score);
//     }

//     // calculate the weighted score
//     if (score == 0) return 0;

//     uint256 weightedScore = 0;
//     for (uint i = 0; i < scoreLevels.length; i++) {
//       if (score > scoreLevels[i]) {
//         weightedScore = score.mul(rewardMultiplier[scoreLevels[i]]);
//       } else {
//         return weightedScore;
//       }
//     }

//     return weightedScore;

//   }

//   function getScore(uint256 stakingId, uint256 weekNumber) internal view returns (uint256) {
//     uint256 score = 0;
//     uint256 stakeWeek = stakeTime[stakingId].sub(startBlockTime).div(ONE_WEEK);
//     if (stakeWeek > weekNumber) return 0;
//     uint256 diff = weekNumber.sub(stakeWeek) > WEEKS_OF_ONE_YEAR ? WEEKS_OF_ONE_YEAR : weekNumber.sub(stakeWeek);
//     uint256 lockScore = deposits[stakingId].mul(uint256(lockPeriod[stakingId])).mul(3).div(12);
//     score = deposits[stakingId].mul(diff + 1).div(WEEKS_OF_ONE_YEAR).add(lockScore);
//     if (score > deposits[stakingId]) {
//       score = deposits[stakingId].div(1e18);
//     } else {
//       score = score.div(1e18);
//     }

//     return score;
//   }
// }