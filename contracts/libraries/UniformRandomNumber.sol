// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.8.0;

/**
  This contract is copied from https://github.com/pooltogether/pooltogether-pool-contracts/blob/v1/contracts/UniformRandomNumber.sol
 */

library UniformRandomNumber {
  /// @author Brendan Asselstine
  /// @notice Select a random number without modulo bias using a random seed and upper bound
  /// @param _entropy The seed for randomness
  /// @param _upperBound The upper bound of the desired number
  /// @return A random number less than the _upperBound
  function uniform(uint256 _entropy, uint256 _upperBound) internal pure returns (uint256) {
    uint256 min = -_upperBound % _upperBound;
    uint256 random = _entropy;
    while (true) {
      if (random >= min) {
        break;
      }
      random = uint256(keccak256(abi.encodePacked(random)));
    }
    return random % _upperBound;
  }
}