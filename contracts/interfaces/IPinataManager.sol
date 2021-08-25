// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPinataManager {
    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER,
        WINNERS_PENDING,
        READY
    }

    function startNewLottery(uint256 _closingTime, uint256 _drawingTime)
        external;

    function closePool() external;

    function calculateWinners() external;

    function winnersCalculated() external;
    
    function rewardDistributed() external;

    function getState() external view returns (LOTTERY_STATE);

    function getTimeline()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );

    function getVault() external view returns (address);

    function getStrategy() external view returns (address);

    function getPrizePool() external view returns (address);

    function getRandomNumberGenerator() external view returns (address);

    function getStrategist() external view returns (address);

    function getPinataFeeRecipient() external view returns (address);

    function getIsManager(address manager) external view returns (bool);

    function getIsTimekeeper(address timekeeper) external view returns (bool);

    function setVault(address _vault) external;

    function setStrategy(address _strategy) external;

    function setPrizePool(address _prizePool) external;

    function setRandomNumberGenerator(address _randomNumberGenerator) external;

    function setStrategist(address _strategist) external;

    function setPinataFeeRecipient(address _pinataFeeRecipient) external;

    function setManager(address _manager, bool status) external;
}
