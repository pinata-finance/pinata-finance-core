// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../interfaces/IPinataPrizePool.sol";
import "../interfaces/IPinataStrategy.sol";
import "../interfaces/IPinataVault.sol";

/**
 * @dev Implementation of a manager for each pool of Pinata Finance protocol.
 * This is the contract that using to managing state, permission.
 * and also managing contract in which is part of each pool.
 */
contract PinataManager {
    using SafeMath for uint256;

    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER,
        WINNERS_PENDING,
        READY
    }

    /* ========================== Variables ========================== */
    address public manager; // The current manager.
    address public pendingManager; // The address pending to become the manager once accepted.
    address public timeKeeper; // keeper of pool state.

    uint256 public openTime;
    uint256 public closingTime;
    uint256 public drawingTime;
    bool public allowCloseAnytime;
    bool public allowDrawAnytime;
    LOTTERY_STATE public lotteryState;

    // Contracts
    address public vault;
    address public strategy;
    address public prizePool;
    address public randomNumberGenerator;

    // Fee Receiver
    address public strategist; // Address of the strategy author/deployer where strategist fee will go.
    address public pinataFeeRecipient; // Address where to send pinata's fees (fund of platform).

    /* ========================== Events ========================== */

    /**
     * @dev Emitted when Pool is open ready to deposit.
     */
    event PoolOpen();

    /**
     * @dev Emitted when Pool is closed deposit will not be allowed.
     */
    event PoolClosed();

    /**
     * @dev Emitted when Pool is calculating for lucky winners.
     */
    event PoolCalculatingWinners();

    /**
     * @dev Emitted when Pool is getting numbers from Chainlink and waiting for reward distribution.
     */
    event PoolWinnersPending();

    /**
     * @dev Emitted when Pool is ready to be open.
     */
    event PoolReady();

    /**
     * @dev Emitted when address of vault is setted.
     */
    event VaultSetted(address vault);

    /**
     * @dev Emitted when address of strategy is setted.
     */
    event StrategySetted(address strategy);

    /**
     * @dev Emitted when address of prize pool is setted.
     */
    event PrizePoolSetted(address prizePool);

    /**
     * @dev Emitted when address of random number generator is setted.
     */
    event RandomNumberGeneratorSetted(address randomNumberGenerator);

    /**
     * @dev Emitted when address of strategist (dev) is setted.
     */
    event StrategistSetted(address strategist);

    /**
     * @dev Emitted when address of pinataFeeRecipient (treasury) is setted.
     */
    event PinataFeeRecipientSetted(address pinataFeeRecipient);

    /**
     * @dev Emitted when manager is setted.
     */
    event ManagerSetted(address manager);

    /**
     * @dev Emitted when pending manager is setted.
     */
    event PendingManagerSetted(address pendingManager);

    /**
     * @dev Emitted when time keeper is setted.
     */
    event TimeKeeperSetted(address timeKeeper);

    /**
     * @dev Emitted when changing allowCloseAnytime or allowDrawAnytime.
     */
    event PoolTimerSetted(bool allowCloseAnytime, bool allowDrawAnytime);
    /**

    /* ========================== Modifier ========================== */

    /**
     * @dev Modifier to make a function callable only when called by time keeper.
     *
     * Requirements:
     *
     * - The caller have to be setted as time keeper.
     */
    modifier onlyTimeKeeper() {
        require(
            msg.sender == timeKeeper,
            "PinataManager: Only Timekeeper allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when called by manager.
     *
     * Requirements:
     *
     * - The caller have to be setted as manager.
     */
    modifier onlyManager() {
        require(msg.sender == manager, "PinataManager: Only Manager allowed!");
        _;
    }

    /* ========================== Functions ========================== */

    /**
     * @dev Setting up contract's state, permission is setted to deployer as default.
     * @param _allowCloseAnytime boolean in which is pool allowed to be closed any time.
     * @param _allowDrawAnytime boolean in which is pool allowed to be able to draw rewards any time.
     */
    constructor(bool _allowCloseAnytime, bool _allowDrawAnytime) public {
        allowCloseAnytime = _allowCloseAnytime;
        allowDrawAnytime = _allowDrawAnytime;
        lotteryState = LOTTERY_STATE.READY;

        manager = msg.sender;
        pendingManager = address(0);
        vault = address(0);
        timeKeeper = msg.sender;
    }

    /**
     * @dev Start new lottery round set lottery state to open. only allow when lottery is in ready state.
     *  only allow by address setted as time keeper.
     * @param _closingTime timestamp of desired closing time.
     * @param _drawingTime timestamp of desired drawing time.
     */
    function startNewLottery(uint256 _closingTime, uint256 _drawingTime)
        public
        onlyTimeKeeper
    {
        require(
            lotteryState == LOTTERY_STATE.READY,
            "PinataManager: can't start a new lottery yet!"
        );
        drawingTime = _drawingTime;
        openTime = block.timestamp;
        closingTime = _closingTime;
        lotteryState = LOTTERY_STATE.OPEN;

        emit PoolOpen();
    }

    /**
     * @dev Closing ongoing lottery set status of pool to closed.
     *  only allow by address setted as time keeper.
     */
    function closePool() public onlyTimeKeeper {
        if (!allowCloseAnytime) {
            require(
                block.timestamp >= closingTime,
                "PinataManager: cannot be closed before closing time!"
            );
        }
        lotteryState = LOTTERY_STATE.CLOSED;

        emit PoolClosed();
    }

    /**
     * @dev Picking winners for this round calling harvest on strategy to ensure reward is updated.
     *  calling drawing number on prize pool to calculating for lucky winners.
     *  only allow by address setted as time keeper.
     */
    function calculateWinners() public onlyTimeKeeper {
        if (!allowDrawAnytime) {
            require(
                block.timestamp >= drawingTime,
                "PinataManager: cannot be calculate winners before drawing time!"
            );
        }

        IPinataStrategy(strategy).harvest();

        IPinataPrizePool(prizePool).drawNumber();
        lotteryState = LOTTERY_STATE.CALCULATING_WINNER;

        emit PoolCalculatingWinners();
    }

    /**
     * @dev Called when winners is calculated only allow to be called from prize pool.
     *  setting the lottery state winners pending since reward need to be distributed.
     * @dev process have to be seperated since Chainlink VRF only allow 200k for gas limit.
     */
    function winnersCalculated() external {
        require(
            msg.sender == prizePool,
            "PinataManager: Caller need to be PrizePool"
        );

        lotteryState = LOTTERY_STATE.WINNERS_PENDING;

        emit PoolWinnersPending();
    }

    /**
     * @dev Called when winners is calculated only allow to be called from prize pool.
     *  setting the lottery state to ready for next round.
     */
    function rewardDistributed() external {
        require(
            msg.sender == prizePool,
            "PinataManager: Caller need to be PrizePool"
        );

        lotteryState = LOTTERY_STATE.READY;

        emit PoolReady();
    }

    /* ========================== Getter Functions ========================== */

    /**
     * @dev getting current state of the pool.
     */
    function getState() public view returns (LOTTERY_STATE) {
        return lotteryState;
    }

    /**
     * @dev getting timeline of current round setted when new lottery started.
     */
    function getTimeline()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        return (openTime, closingTime, drawingTime);
    }

    /**
     * @dev get address of vault setted.
     */
    function getVault() external view returns (address) {
        return vault;
    }

    /**
     * @dev get address of strategy setted.
     */
    function getStrategy() external view returns (address) {
        return strategy;
    }

    /**
     * @dev get address of prize pool setted.
     */
    function getPrizePool() external view returns (address) {
        return prizePool;
    }

    /**
     * @dev get address of random number generator setted.
     */
    function getRandomNumberGenerator() external view returns (address) {
        return randomNumberGenerator;
    }

    /**
     * @dev get address of strategist (dev) setted.
     */
    function getStrategist() external view returns (address) {
        return strategist;
    }

    /**
     * @dev get address of pinata fee recipient (treasury) setted.
     */
    function getPinataFeeRecipient() external view returns (address) {
        return pinataFeeRecipient;
    }

    /**
     * @dev get manager status of address provided.
     * @param _manager is address want to know status of.
     */
    function getIsManager(address _manager) external view returns (bool) {
        return _manager == manager;
    }

    /**
     * @dev get timekeeper status of address provided.
     * @param _timeKeeper is address want to know status of.
     */
    function getIsTimekeeper(address _timeKeeper) external view returns (bool) {
        return _timeKeeper == timeKeeper;
    }

    /* ========================== Admin Setter Functions ========================== */

    /**
     * @dev setting address of vault.
     * @param _vault is address of vault.
     */
    function setVault(address _vault) external onlyManager {
        require(vault == address(0), "PinataManager: Vault already set!");
        vault = _vault;

        emit VaultSetted(vault);
    }

    /**
     * @dev setting address of strategy. perform retireStrat operation to withdraw the fund from
     *  old strategy to new strategy.
     * @param _strategy is address of strategy.
     */
    function setStrategy(address _strategy) external onlyManager {
        if (strategy != address(0)) {
            IPinataStrategy(strategy).retireStrat();
        }
        strategy = _strategy;

        IPinataVault(vault).earn();

        emit StrategySetted(strategy);
    }

    /**
     * @dev setting address of prize pool. perform retirePrizePool operation to withdraw the fund from
     *  old prizePool to vault. but the allocated reward is remain in the old prize pool.
     *  participant will have to withdraw and deposit again to participate in new prize pool.
     * @param _prizePool is address of new prize pool.
     */
    function setPrizePool(address _prizePool) external onlyManager {
        require(
            lotteryState == LOTTERY_STATE.READY,
            "PinataManager: only allow to set prize pool in ready state!"
        );
        if (prizePool != address(0)) {
            IPinataPrizePool(prizePool).retirePrizePool();
        }
        prizePool = _prizePool;

        emit PrizePoolSetted(prizePool);
    }

    /**
     * @dev setting address of random number generator.
     * @param _randomNumberGenerator is address of random number generator.
     */
    function setRandomNumberGenerator(address _randomNumberGenerator)
        external
        onlyManager
    {
        randomNumberGenerator = _randomNumberGenerator;

        emit RandomNumberGeneratorSetted(randomNumberGenerator);
    }

    /**
     * @dev setting address of strategist.
     * @param _strategist is address of strategist.
     */
    function setStrategist(address _strategist) external onlyManager {
        strategist = _strategist;

        emit StrategistSetted(strategist);
    }

    /**
     * @dev setting address of pinataFeeRecipient.
     * @param _pinataFeeRecipient is address of pinataFeeRecipient.
     */
    function setPinataFeeRecipient(address _pinataFeeRecipient)
        external
        onlyManager
    {
        pinataFeeRecipient = _pinataFeeRecipient;

        emit PinataFeeRecipientSetted(pinataFeeRecipient);
    }

    /**
     * @dev Set the pending manager, which will be the manager once accepted.
     * @param _pendingManager The address to become the pending governor.
     */
    function setPendingManager(address _pendingManager) external onlyManager {
        pendingManager = _pendingManager;

        emit PendingManagerSetted(_pendingManager);
    }

    /**
     * @dev Set the pending manager, which will be the manager once accepted.
     * @param _accept is to accept role as manager or not.
     */
    function acceptManager(bool _accept) external {
        require(
            msg.sender == pendingManager,
            "PinataManager: not the pending manager"
        );
        pendingManager = address(0);
        if (_accept) {
            manager = msg.sender;

            emit ManagerSetted(msg.sender);
        }
    }

    /**
     * @dev setting status of time keeper.
     * @param _timeKeeper is address wish to changing status.
     */
    function setTimeKeeper(address _timeKeeper) external onlyManager {
        timeKeeper = _timeKeeper;

        emit TimeKeeperSetted(_timeKeeper);
    }

    /**
     * @dev setting pool to beable to close or draw anytime or only when past time setted.
     * @param _allowCloseAnytime is address wish to changing status.
     * @param _allowDrawAnytime is address wish to changing status.
     */
    function setPoolAllow(bool _allowCloseAnytime, bool _allowDrawAnytime) external onlyManager {
        allowCloseAnytime = _allowCloseAnytime;
        allowDrawAnytime = _allowDrawAnytime;

        emit PoolTimerSetted(allowCloseAnytime, allowDrawAnytime);
    }
    
    /**
     * @dev use for emergency in case state got stuck.
     *  state of the pool should progress automatically.
     *  this function is provided just in case.
     */
    function setStateToReady() external onlyManager {
        lotteryState = LOTTERY_STATE.READY;

        emit PoolReady();
    }
}
