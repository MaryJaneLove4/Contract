// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";

import "../../external/pancake/IMasterChef.sol";
import "../../libraries/FixedPoint.sol";
import "../RewardTokenFarmPool.sol";
import "./CakeFarmPancakePool.sol";

contract LPToCakeFarmPancakePool is RewardTokenFarmPool {
    //events
    event Harvested(uint256 amount);

    //struct
    //variables
    IERC20Upgradeable private constant CAKE = IERC20Upgradeable(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    uint256 public pid;
    CakeFarmPancakePool public hifCakePool;

    //initializer
    function initialize(address _comptroller, address _stakedToken, uint256 _pid, address _hifCakePool) public initializer {
        __RewardTokenFarmPool_init(_comptroller, _stakedToken, address(CAKE), 24 hours);
        pid = _pid;
        hifCakePool = CakeFarmPancakePool(_hifCakePool);
        performanceFeeFactorMantissa = 3e17; //0.3
    }

    //view functions
    function earned(address user) public virtual override view returns (uint256) {
        uint256 shareAmount = super.earned(user);
        return hifCakePool.amountOfShare(shareAmount);
    }
    
    function tvl() public view virtual override returns (uint256) {
        uint256 valueInUSD = super.tvl();

        uint256 shareAmount = _rewardBalance();
        uint256 cakeAmount = hifCakePool.amountOfShare(shareAmount);
        PriceInterface priceProvider = comptroller.priceProvider();
        (,uint256 rewardValueInUSD) = priceProvider.valueOfToken(rewardToken(), cakeAmount);

        return valueInUSD.add(rewardValueInUSD);
    }

    function apRY() public view virtual override returns (uint256, uint256) {
        PriceInterface priceProvider = comptroller.priceProvider();
        uint256 measureTotalSupply = totalShare();
        uint256 accPerSecond = hifCakePool.amountOfShare(rewardInfo.accPerSecond);
        uint256 accRewardPerSecondPerShareMantissa = FixedPoint.calculateMantissa(accPerSecond, measureTotalSupply > 0 ? measureTotalSupply : FixedPoint.SCALE);

        uint256 bnbPerShare = priceProvider.getBNBPerToken(stakedToken()); //scale e18
        uint256 bnbPerRewardToken = priceProvider.getBNBPerToken(rewardToken()); //scale e18

        //accBNBPerSecondPerShare = FixedPoint.multiplyUintByMantissa(accPerSecondPerShareMantissa, bnbPerRewardToken)
        uint256 rewardAPR = FixedPoint.multiplyUintByMantissa(bnbPerRewardToken, accRewardPerSecondPerShareMantissa).mul(1e18).mul(365 days).div(bnbPerShare);
        return (0, rewardAPR);
    }

    //restricted functions
    function setPid(uint256 _pid) external onlyOwner {
        pid = _pid;
    }

    //public functions
    function harvest() external {
        _unstakeFarm(0);
        uint256 rewardAmount = _rewardToken().balanceOf(address(this));
        emit Harvested(rewardAmount);
        //stake harvest
        _stakeHarvest();
    }

    //private functions
    function _stakeToFarm(uint256 amount) internal override returns (uint256) {
        _stakeFarm(amount);
        //stake harvest
        _stakeHarvest();

        return amount;
    }
    function _unStakeForWithdraw(uint256 amount) internal override returns (uint256) {
        _unstakeFarm(amount);
        //stake harvest
        _stakeHarvest();
        return amount;
    }

    function _balanceOfFarm() internal view override returns (uint256) {
        if (pid > 0) {
            (uint256 amount,) = CAKE_MASTER_CHEF.userInfo(pid, address(this));
            return amount;
        }
        return 0;
    }

    function _rewardBalance() internal view override returns (uint256) {
        return hifCakePool.shareOf(address(this));
    }

    function _convertAccrued(uint256 share) internal virtual override returns (uint256) {
        uint256 currentShare = MathUpgradeable.min(share, _rewardBalance());
        if (currentShare == 0) {
            return 0;
        }
        uint256 before = _rewardToken().balanceOf(address(this));
        hifCakePool.withdrawShare(currentShare);
        uint256 userRewardAmount = _rewardToken().balanceOf(address(this)).sub(before);
        return userRewardAmount;
    }

    function _transferOutReward(address user, uint256 amount) internal override returns (uint256) {
        if (amount > 0) {
            _rewardToken().safeTransfer(user, amount);
        }
        return amount;
    }

    function _stakeFarm(uint256 amount) internal {
        if (amount > 0 && pid > 0) {
            _approveTokenIfNeeded(_stakedToken(), address(CAKE_MASTER_CHEF), amount);
            CAKE_MASTER_CHEF.deposit(pid, amount);
        }
    }
    function _unstakeFarm(uint256 amount) internal {
        if (pid > 0) {
            CAKE_MASTER_CHEF.withdraw(pid, amount);
        }
    }

    function _stakeHarvest() internal {
        uint256 rewardAmount = _rewardToken().balanceOf(address(this));
        if (rewardAmount == 0) {
            return;
        }
        uint256 before = hifCakePool.shareOf(address(this));
        _approveTokenIfNeeded(_rewardToken(), address(hifCakePool), rewardAmount);
        hifCakePool.depositTokenTo(address(this), rewardAmount);
        uint256 amount = hifCakePool.shareOf(address(this)).sub(before);
        if (amount > 0) {
            _notifyReward(amount);
        }
    }
    //modifier
}

