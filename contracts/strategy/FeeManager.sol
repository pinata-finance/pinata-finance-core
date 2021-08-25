// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../manager/PinataManageable.sol";

/**
 * @dev Base contract for strategy contract.
 * main purpose of it was to simply enable easier ways for setting any fees for the strategy.
 */
abstract contract FeeManager is PinataManageable {
    /* ========================== Variables ========================== */
    // Withdrawal fee
    uint256 public constant WITHDRAWAL_MAX = 1000;
    uint256 public constant WITHDRAWAL_FEE = 1;

    // Priza pool fee
    uint256 public constant BALANCE_MAX = 1000;
    uint256 public constant MAX_PRIZE_POOL_FEE = 500;
    uint256 public prizePoolFee = 500;

    // Common fee
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant MAX_HARVEST_CALL_FEE = 900;
    uint256 public harvestCallFee = 900;
    uint256 public constant STRATEGIST_FEE = 100;
    uint256 public pinataFee = MAX_FEE - STRATEGIST_FEE - harvestCallFee;

    /* ========================== Functions ========================== */

    /**
     * @dev set new prizePoolFee.
     * @param _prizePoolFee new value of prizePoolFee.
     *  only allow to be call by manager.
     */
    function setPrizePoolFee(uint256 _prizePoolFee) external onlyManager {
        require(_prizePoolFee <= MAX_PRIZE_POOL_FEE, "FeeManager: Not cap!");

        prizePoolFee = _prizePoolFee;
    }

    /**
     * @dev set new harvestCallFee.
     * @param _harvestCallFee new value of harvestCallFee.
     *  only allow to be call by manager.
     */
    function setHarvestCallFee(uint256 _harvestCallFee) external onlyManager {
        require(
            _harvestCallFee <= MAX_HARVEST_CALL_FEE,
            "FeeManager: Not cap!"
        );

        harvestCallFee = _harvestCallFee;
        pinataFee = MAX_FEE - STRATEGIST_FEE - harvestCallFee;
    }
}
