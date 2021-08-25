// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IPinataStrategy {
    function deposit() external;

    function withdraw(uint256 _amount) external;

    function harvest() external;

    function balanceOf() external view returns (uint256);

    function balanceOfLpWant() external view returns (uint256);

    function balanceOfPool() external view returns (uint256);

    function want() external view returns(address);

    function retireStrat() external;

    function panic() external;

    function pause() external;

    function unpause() external;
}
