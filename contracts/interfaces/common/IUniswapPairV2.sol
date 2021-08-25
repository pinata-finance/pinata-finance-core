// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

interface IUniswapPairV2 {
    function token0() external view returns (address);
    
    function token1() external view returns (address);
}

