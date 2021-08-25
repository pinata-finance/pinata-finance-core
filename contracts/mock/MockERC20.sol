// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev THIS CONTRACT IS FOR TESTING PURPOSES ONLY.
 */
contract MockERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 supply
    ) public ERC20(name, symbol) {
        _mint(msg.sender, supply);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @dev This function is only here to accommodate nested Link token 
     *      functionality required in mocking the random number calls.
     */
    function transferAndCall(
        address to, 
        uint256 value, 
        bytes calldata data
    ) 
        external 
        returns(bool success) 
    {
        return true;
    }
}