// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPinataVault {
    function want() external view returns (IERC20);

    function balance() external view returns (uint256);

    function available() external view returns (uint256);

    function earn() external;

    function deposit(uint256 _amount) external;

    function withdrawAll() external;

    function getPricePerFullShare() external view returns (uint256);
}
