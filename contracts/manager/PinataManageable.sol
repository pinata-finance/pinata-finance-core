// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../interfaces/IPinataManager.sol";

/**
 * @dev Base contract for every contract which is part of Pinata Finance's Prize Farming Game pool.
 *  main purpose of it was to simply enable easier ways for reading PinataManager state.
 */
abstract contract PinataManageable {
    /* ========================== Variables ========================== */

    IPinataManager public manager; // PinataManager contract

    /* ========================== Constructor ========================== */

    /**
     * @dev Modifier to make a function callable only when called by random generator.
     *
     * Requirements:
     *
     * - The caller have to be setted as random generator.
     */
    modifier onlyRandomGenerator() {
        require(
            msg.sender == getRandomNumberGenerator(),
            "PinataManageable: Only random generator allowed!"
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
        require(
            msg.sender == address(manager) || manager.getIsManager(msg.sender),
            "PinataManageable: Only PinataManager allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when called by timekeeper.
     *
     * Requirements:
     *
     * - The caller have to be setted as timekeeper.
     */
    modifier onlyTimekeeper() {
        require(
            msg.sender == address(manager) || manager.getIsTimekeeper(msg.sender),
            "PinataManageable: Only Timekeeper allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when called by Vault.
     *
     * Requirements:
     *
     * - The caller have to be setted as vault.
     */
    modifier onlyVault() {
        require(
            msg.sender == getVault(),
            "PinataManageable: Only vault allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when called by prize pool.
     *
     * Requirements:
     *
     * - The caller have to be setted as prize pool.
     */
    modifier onlyPrizePool() {
        require(
            msg.sender == getPrizePool(),
            "PinataManageable: Only prize pool allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when called by strategy.
     *
     * Requirements:
     *
     * - The caller have to be setted as strategy.
     */
    modifier onlyStrategy() {
        require(
            msg.sender == getStrategy(),
            "PinataManageable: Only strategy allowed!"
        );
        _;
    }

    /**
     * @dev Modifier to make a function callable only when pool is not in undesired state.
     *
     * @param state is state wish to not allow.
     *
     * Requirements:
     *
     * - Must calling when pool is not in undesired state.
     *
     */
    modifier whenNotInState(IPinataManager.LOTTERY_STATE state) {
        require(getState() != state, "PinataManageable: Not in desire state!");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when pool is in desired state.
     *
     * @param state is state wish to allow.
     *
     * Requirements:
     *
     * - Must calling when pool is in desired state.
     *
     */
    modifier whenInState(IPinataManager.LOTTERY_STATE state) {
        require(getState() == state, "PinataManageable: Not in desire state!");
        _;
    }

    /* ========================== Functions ========================== */

    /**
     * @dev Linking to manager wishes to read its state.
     * @param _manager address of manager contract.
     */
    constructor(address _manager) public {
        manager = IPinataManager(_manager);
    }

    /* ========================== Getter Functions ========================== */

    /**
     * @dev Read current state of pool.
     */
    function getState() public view returns (IPinataManager.LOTTERY_STATE) {
        return manager.getState();
    }

    /**
     * @dev Read if address was manager.
     * @param _manager address wish to know.
     */
    function getIfManager(address _manager) public view returns (bool) {
        return manager.getIsManager(_manager);
    }

    /**
     * @dev Get current timeline of pool (openning, closing, drawing).
     */
    function getTimeline() public view returns (uint256, uint256, uint256) {
        return manager.getTimeline();
    }

    /**
     * @dev Read vault contract address.
     */
    function getVault() public view returns (address) {
        return manager.getVault();
    }

    /**
     * @dev Read strategy contract address.
     */
    function getStrategy() public view returns (address) {
        return manager.getStrategy();
    }

    /**
     * @dev Read prize pool contract address.
     */
    function getPrizePool() public view returns (address) {
        return manager.getPrizePool();
    }

    /**
     * @dev Read random number generator contract address.
     */
    function getRandomNumberGenerator() public view returns (address) {
        return manager.getRandomNumberGenerator();
    }

    /**
     * @dev Read strategist address.
     */
    function getStrategist() public view returns (address) {
        return manager.getStrategist();
    }

    /**
     * @dev Read pinata fee recipient address.
     */
    function getPinataFeeRecipient() public view returns (address) {
        return manager.getPinataFeeRecipient();
    }
}
