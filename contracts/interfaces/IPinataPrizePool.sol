// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

interface IPinataPrizePool {
    struct Entry {
        address addr;
        uint256 chances;
        uint256 lastEnterId;
        uint256 lastDeposit;
        uint256 claimableReward;
    }

    struct History {
        uint256 roundId;
        uint256 rewardNumber;
        address[] winners;
        uint256 roundReward;
    }

    function addChances(address participant, uint256 _chances) external;

    function withdraw(address participant)
        external;
    
    function chancesOf(address participant) external view returns (uint256);

    function ownerOf(uint256 ticketId) external view returns (address);

    function drawNumber() external;

    function numbersDrawn(
        bytes32 requestId,
        uint256 roundId,
        uint256 randomness
    ) external;

    function claimReward(uint256 _amount) external;

    function getEntryInfo(address _entry) external view returns (Entry memory);

    function getNumOfParticipants() external view returns (uint256);

    function getHistory(uint256 _round)
        external
        view
        returns (History memory history);

    function setRandomGenerator(address randomGenerator) external;
    
    function setVault(address vault) external;

    function retirePrizePool() external;
}
