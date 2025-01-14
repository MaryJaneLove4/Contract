// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.7.0;

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";

import "../../external/pancake/IMasterChef.sol";
import "../../libraries/FixedPoint.sol";
import "../../libraries/Helper.sol";
import "../ShareTokenFarmPool.sol";

contract CakeFarmPancakePool is ShareTokenFarmPool {
    //events
    event Harvested(uint256 amount);

    //struct
    //variables
    uint256 private constant pid = 0;
    IERC20Upgradeable private constant CAKE = IERC20Upgradeable(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
    IMasterChef private constant CAKE_MASTER_CHEF = IMasterChef(0x73feaa1eE314F8c655E354234017bE2193C9E24E);
    uint256 private constant blockPerYear = 10512000;

    //initializer
    function initialize(address _comptroller) public initializer {
        __ShareTokenFarmPool_init(_comptroller, address(CAKE));
        performanceFeeFactorMantissa = 3e17; //0.3
    }

    //view functions
    function apRY() public view virtual override returns (uint256, uint256) {
        //PriceInterface priceProvider = comptroller.priceProvider();
        (, uint allocPoint,,) = CAKE_MASTER_CHEF.poolInfo(pid);
        uint256 cakePerYear = CAKE_MASTER_CHEF.cakePerBlock().mul(blockPerYear).mul(allocPoint).div(CAKE_MASTER_CHEF.totalAllocPoint());
        //scale e18
        uint256 totalMasterCake = CAKE.balanceOf(address(CAKE_MASTER_CHEF));
        if (totalMasterCake == 0) {
            return (0, 0);
        }
        uint256 rewardAPR = cakePerYear.mul(1e18).div(totalMasterCake);
        uint256 rewardAPY = Helper.compoundingAPY(rewardAPR, 1 days);
        return (0, rewardAPY);
    }

    //restricted functions

    //public functions
    function harvest() external {
        CAKE_MASTER_CHEF.leaveStaking(0);
        uint256 balance = _stakedToken().balanceOf(address(this));
        emit Harvested(balance);
        _stakeFarm(balance);
    }

    //private functions
    function _stakeToFarm(uint256 amount) internal override returns (uint256) {
        _stakeFarm(amount);
        //restake harvest
        _stakeFarm(_stakedToken().balanceOf(address(this)));

        return amount;
    }

    function _unStakeForWithdraw(uint256 amount) internal override returns (uint256) {
        uint256 balance = _stakedToken().balanceOf(address(this));
        uint256 left = 0;
        if (amount > balance) {
            uint256 availableAmount = balance.add(_pendingFarmReward());
            uint256 unstakeAmount = amount > availableAmount ? amount.sub(availableAmount) : 0;
            CAKE_MASTER_CHEF.leaveStaking(unstakeAmount);
            uint256 collectAmount = _stakedToken().balanceOf(address(this)).sub(balance);
            left = collectAmount.sub(amount);
        } else {
            left = balance.sub(amount);
        }

        //restake left
        _stakeFarm(left);
        return amount;
    }

    function _balance() internal virtual override view returns (uint256) {
        (uint256 amount,) = CAKE_MASTER_CHEF.userInfo(pid, address(this));
        return amount;
    }

    function _pendingFarmReward() internal view returns (uint256) {
        return CAKE_MASTER_CHEF.pendingCake(pid, address(this));
    }

    function _stakeFarm(uint256 amount) internal {
        if (amount > 0) {
            _approveTokenIfNeeded(_stakedToken(), address(CAKE_MASTER_CHEF), amount);
            CAKE_MASTER_CHEF.enterStaking(amount);
        }
    }

    //modifier
}


