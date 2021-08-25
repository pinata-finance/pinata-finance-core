// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IRNGenerator {
    function getRandomNumber(uint256 _roundId, uint256 _userProvidedSeed)
        external
        returns (bytes32 requestId);
}
