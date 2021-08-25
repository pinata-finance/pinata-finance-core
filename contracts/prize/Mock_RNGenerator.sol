// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../interfaces/IPinataPrizePool.sol";

/**
 * @dev THIS CONTRACT IS FOR TESTING PURPOSES ONLY.
 */
contract Mock_RNGenerator {
    uint256 internal _randomness;
    bytes32 internal _requestId;
    uint256 internal roundId;

    address requester;
    address manager;

    function getRandomNumber(
        uint256 _roundId,
        uint256 _userProvidedSeed
    ) 
        public
        returns (bytes32 requestId) 
    {
        _randomness = _userProvidedSeed;
        roundId = _roundId;
        requester = msg.sender;
        _requestId = bytes32("MOCK_MOCK_MOCK");

        return _requestId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness) external {
        IPinataPrizePool(requester).numbersDrawn(
            _requestId,
            roundId,
            randomness
        );
    }
}
