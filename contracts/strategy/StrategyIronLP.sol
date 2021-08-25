// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/utils/Pausable.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/iron/IIronMasterChef.sol";
import "../interfaces/iron/IIronSwap.sol";
import "../interfaces/iron/IIronSwapLP.sol";
import "../interfaces/common/IUniswapRouterV2.sol";

import "../strategy/FeeManager.sol";

/**
 * @dev Implementation of a yield optimizing strategy to manage yield reward funds. (Only on polygon chian)
 * This is the contract that control staking and distribute fees for a prize pool and any wallet such as 'harvester','strategist' and 'pinataFeeRecipient'.
 */
contract StrategyIronLP is Pausable, FeeManager {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /* ========================== Variables ========================== */

    // Tokens Contracts
    address public outputToken; // Address of the output token.
    address public lpWant; // Address of the lp token required by masterchef for staking.
    address public depositToken; // Address of the token to be deposited.
    address public constant usdcToken =
        address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174); // Address of the USDC token.

    // Third-party Contracts
    address public masterchef; // Address of the masterchef that this strategy will go farm.
    address public pool; // Address of pool that this strategy will go add liquidity.
    address public unirouter; // Address of uniswap router.

    // Other Variables
    uint256 public poolId; // Id of pool in masterchef that this strategy will stake.
    uint256 public poolSize; // Number of tokens in pool.
    uint8 public depositIndex; // Index of the deposit token in pool.

    // Routes
    address[] public outputToDepositRoute; // Route for exchange the output token to the deposit token.
    address[] public outputToUSDCRoute; // Route for exchange the output token to the USDC token.

    /* ========================== Events ========================== */

    /**
     * @dev Emitted when someone call harvest.
     */
    event StrategyHarvest(address indexed harvester);

    /* ========================== Functions ========================== */

    /**
     * @dev Setting up contract's state, then give allowances for masterchef.
     * @param _outputToken address of the output token.
     * @param _lpWant address of the lp token required by masterchef for staking.
     * @param _masterchef address of the masterchef that this strategy will go farm.
     * @param _unirouter address of uniswap router.
     * @param _poolId id of pool in masterchef that this strategy will stake.
     * @param _depositIndex index of the deposit token in pool.
     * @param _outputToDepositRoute route for exchange the output token to the deposit token.
     * @param _manager address of PinataManager contract.
     */
    constructor(
        address _outputToken,
        address _lpWant,
        address _masterchef,
        address _unirouter,
        uint256 _poolId,
        uint8 _depositIndex,
        address[] memory _outputToDepositRoute,
        address _manager
    ) public PinataManageable(_manager) {
        outputToken = _outputToken;
        lpWant = _lpWant;
        masterchef = _masterchef;
        unirouter = _unirouter;

        poolId = _poolId;

        pool = IIronSwapLP(lpWant).swap();
        poolSize = IIronSwap(pool).getNumberOfTokens();
        depositToken = IIronSwap(pool).getToken(_depositIndex);

        require(
            _outputToDepositRoute[0] == outputToken,
            "StrategyIronLP: outputToDepositRoute[0] != outputToken"
        );
        require(
            _outputToDepositRoute[_outputToDepositRoute.length - 1] ==
                depositToken,
            "StrategyIronLP: Not depositToken!"
        );
        outputToDepositRoute = _outputToDepositRoute;

        outputToUSDCRoute = [outputToken, usdcToken];

        _giveAllowances();
    }

    /**
     * @dev stakes the funds to work in masterchef.
     */
    function deposit() public whenNotPaused {
        uint256 lpWantBal = IERC20(lpWant).balanceOf(address(this));

        if (lpWantBal > 0) {
            IIronMasterChef(masterchef).deposit(
                poolId,
                lpWantBal,
                address(this)
            );
        }
    }

    /**
     * @dev withdraw lpWant via the vault.
     * @param _amount amount of lpWant that want to widthraw.
     *  only allow to be call by vault.
     */
    function withdraw(uint256 _amount) external onlyVault {
        uint256 lpWantBal = IERC20(lpWant).balanceOf(address(this));

        if (lpWantBal < _amount) {
            IIronMasterChef(masterchef).withdraw(
                poolId,
                _amount.sub(lpWantBal),
                address(this)
            );
            lpWantBal = IERC20(lpWant).balanceOf(address(this));
        }

        if (lpWantBal > _amount) {
            lpWantBal = _amount;
        }

        if (getIfManager(tx.origin) || paused()) {
            // no fee.
            IERC20(lpWant).safeTransfer(getVault(), lpWantBal);
        } else {
            // have fee.
            uint256 withdrawalFeeAmount = lpWantBal.mul(WITHDRAWAL_FEE).div(
                WITHDRAWAL_MAX
            );
            IERC20(lpWant).safeTransfer(
                getVault(),
                lpWantBal.sub(withdrawalFeeAmount)
            );
        }
    }

    /**
     * @dev compounds earnings and charges performance fee.
     *  only allow to be call by end user (harvester).
     */
    function harvest()
        external
        whenNotPaused
        whenNotInState(IPinataManager.LOTTERY_STATE.WINNERS_PENDING)
    {
        require(
            msg.sender == tx.origin || msg.sender == address(manager),
            "StrategyCake: Can't call via the contract!"
        );

        IIronMasterChef(masterchef).harvest(poolId, address(this));
        _chargeFees();
        _addLiquidity();
        deposit();

        emit StrategyHarvest(msg.sender);
    }

    /**
     * @dev internal function to calulate and distribute fees.
     */
    function _chargeFees() internal {
        address prizePool = getPrizePool();
        address strategist = getStrategist();
        address pinataFeeRecipient = getPinataFeeRecipient();

        uint256 outputTokenBal = IERC20(outputToken).balanceOf(address(this));

        // transfer fee to prizePool. [default 50% outputTokenBal]
        uint256 prizePoolFeeAmount = outputTokenBal.mul(prizePoolFee).div(
            BALANCE_MAX
        );
        IERC20(outputToken).safeTransfer(prizePool, prizePoolFeeAmount);

        // 4.5% iceBal for common fees.
        outputTokenBal = outputTokenBal.sub(prizePoolFeeAmount).mul(45).div(
            1000
        );

        // transfer fee to harvester. [default 90% of 4.5% outputTokenBal]
        uint256 harvestCallFeeFeeAmount = outputTokenBal
            .mul(harvestCallFee)
            .div(MAX_FEE);
        IERC20(outputToken).safeTransfer(msg.sender, harvestCallFeeFeeAmount);

        // transfer fee to strategist. [default 10% of 4.5% outputTokenBal]
        uint256 strategistFeeAmount = outputTokenBal.mul(STRATEGIST_FEE).div(
            MAX_FEE
        );
        IERC20(outputToken).safeTransfer(strategist, strategistFeeAmount);

        // transfer fee to pinataFeeRecipient. [default 0% of 4.5% outputTokenBal]
        uint256 pinataFeeAmount = outputTokenBal.mul(pinataFee).div(MAX_FEE);
        if (pinataFeeAmount > 0) {
            // transfer with the usdc token
            IUniswapRouterV2(unirouter).swapExactTokensForTokens(
                pinataFeeAmount,
                0,
                outputToUSDCRoute,
                address(this),
                block.timestamp
            );
            pinataFeeAmount = IERC20(usdcToken).balanceOf(address(this));
            IERC20(usdcToken).safeTransfer(pinataFeeRecipient, pinataFeeAmount);
        }
    }

    /**
     * @dev add liquidity to the pool and get 'lpWant'.
     */
    function _addLiquidity() internal {
        uint256 outputTokenBal = IERC20(outputToken).balanceOf(address(this));

        IUniswapRouterV2(unirouter).swapExactTokensForTokens(
            outputTokenBal,
            0,
            outputToDepositRoute,
            address(this),
            block.timestamp
        );

        uint256 depositTokenBal = IERC20(depositToken).balanceOf(address(this));

        uint256[] memory amounts = new uint256[](poolSize);
        amounts[depositIndex] = depositTokenBal;

        IIronSwap(pool).addLiquidity(amounts, 0, block.timestamp);
    }

    /**
     * @dev calculate the total underlaying 'lpWant' held by the strategy.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfLpWant().add(balanceOfPool());
    }

    /**
     * @dev calculate how much 'lpWant' this contract holds.
     */
    function balanceOfLpWant() public view returns (uint256) {
        return IERC20(lpWant).balanceOf(address(this));
    }

    /**
     * @dev calculate how much 'lpWant' the strategy has working in the farm.
     */
    function balanceOfPool() public view returns (uint256) {
        (uint256 _amount, ) = IIronMasterChef(masterchef).userInfo(
            poolId,
            address(this)
        );
        return _amount;
    }

    /**
     * @dev pending reward of strategy in masterchef.
     */
    function pendingReward() public view returns (uint256) {
        uint256 _pending = IIronMasterChef(masterchef).pendingReward(
            poolId,
            address(this)
        );
        return _pending;
    }

    /**
     * @dev return address of token that required by masterchef for staking.
     */
    function want() public view returns (address) {
        return lpWant;
    }

    /**
     * @dev called as part of strat migration. Sends all the available funds back to the vault.
     *  only allow to be call by vault.
     */
    function retireStrat() external onlyManager {
        IIronMasterChef(masterchef).emergencyWithdraw(poolId, address(this));

        uint256 lpWantBal = IERC20(lpWant).balanceOf(address(this));
        IERC20(lpWant).transfer(getVault(), lpWantBal);
    }

    /**
     * @dev pause deposits and withdraws all funds from the masterchef.
     *  only allow to be call by manager.
     */
    function panic() public onlyManager {
        pause();
        IIronMasterChef(masterchef).emergencyWithdraw(poolId, address(this));
    }

    /**
     * @dev pause this contract and remove allowance from related contracts.
     *  only allow to be call by manager.
     */
    function pause() public onlyManager {
        _pause();
        _removeAllowances();
    }

    /**
     * @dev unpause this contract, give allowances to related contracts and then continue staking in farm.
     *  only allow to be call by manager.
     */
    function unpause() external onlyManager {
        _unpause();
        _giveAllowances();
        deposit();
    }

    /**
     * @dev internal function to give allowances to related contracts.
     */
    function _giveAllowances() internal {
        IERC20(outputToken).safeApprove(unirouter, type(uint256).max);
        IERC20(lpWant).safeApprove(masterchef, type(uint256).max);
        IERC20(depositToken).safeApprove(pool, type(uint256).max);
    }

    /**
     * @dev internal function to remove allowance from related contracts.
     */
    function _removeAllowances() internal {
        IERC20(outputToken).safeApprove(unirouter, 0);
        IERC20(lpWant).safeApprove(masterchef, 0);
        IERC20(depositToken).safeApprove(pool, 0);
    }
}
