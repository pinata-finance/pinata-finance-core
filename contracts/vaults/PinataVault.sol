// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IPinataStrategy.sol";
import "../interfaces/IPinataPrizePool.sol";

import "../manager/PinataManageable.sol";

/**
 * @dev Implementation of a vault to deposit funds for yield optimizing and prize distribution.
 * This is the contract that receives funds and that users interface with.
 * The yield optimizing strategy and prize was implement in another contract such as 'Strategy.sol' and 'PrizePool.sol'
 */
contract PinataVault is ERC20, Ownable, ReentrancyGuard, PinataManageable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own receipt token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     * @param _manager the PinataManager serve as manager of
     * all contract in protocol related to each pool.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _manager
    ) public ERC20(_name, _symbol) PinataManageable(_manager) {}

    /**
     * @dev It simply return ERC20 token that vault want to hold.
     */
    function want() public view returns (IERC20) {
        return IERC20(IPinataStrategy(getStrategy()).want());
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     * It takes into account the vault contract balance, the strategy contract balance
     * and the balance deployed in other contracts as part of the strategy.
     * but ignore the balance inside PrizePool since it keeping as a prize for lucky stakers.
     */
    function balance() public view returns (uint256) {
        return
            want().balanceOf(address(this)).add(
                IPinataStrategy(getStrategy()).balanceOf()
            );
    }

    /**
     * @dev Custom logic in here for how much the vault allows to be borrowed.
     * We return 100% of tokens for now. Under certain conditions we might
     * want to keep some of the system funds at hand in the vault, instead
     * of putting them to work.
     */
    function available() public view returns (uint256) {
        return want().balanceOf(address(this));
    }

    /**
     * @dev Function to send funds into the strategy and put them to work. It's primarily called
     * by the vault's deposit() function.
     * This only available when this pool in other state rather than "CALCULATING_WINNER"
     * to make sure the prize doesn't mess up.
     */
    function earn()
        public
        whenNotInState(IPinataManager.LOTTERY_STATE.CALCULATING_WINNER)
    {
        uint256 _bal = available();
        want().safeTransfer(getStrategy(), _bal);
        IPinataStrategy(getStrategy()).deposit();
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     * This only available when this pool in "OPEN" state.
     * @param _amount is amount of token wish to deposit.
     */
    function deposit(uint256 _amount)
        public
        nonReentrant
        whenInState(IPinataManager.LOTTERY_STATE.OPEN)
    {
        uint256 _pool = balance();
        want().safeTransferFrom(msg.sender, address(this), _amount);
        earn();
        uint256 _after = balance();
        _amount = _after.sub(_pool); // Additional check for deflationary tokens
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_pool);
        }
        _mint(msg.sender, shares);

        IPinataPrizePool(IPinataManager(manager).getPrizePool()).addChances(
            msg.sender,
            shares
        );
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdrawAll()
        public
    {
        uint256 userShare = balanceOf(msg.sender);
        require(userShare > 0, "PinataVault: User don't have any share");
        uint256 r = (balance().mul(userShare)).div(totalSupply());
        _burn(msg.sender, userShare);

        uint256 b = want().balanceOf(address(this));
        if (b < r) {
            uint256 _withdraw = r.sub(b);
            IPinataStrategy(IPinataManager(manager).getStrategy()).withdraw(
                _withdraw
            );
            uint256 _after = want().balanceOf(address(this));
            uint256 _diff = _after.sub(b);
            if (_diff < _withdraw) {
                r = b.add(_diff);
            }
        }

        want().safeTransfer(msg.sender, r);
        IPinataPrizePool(IPinataManager(manager).getPrizePool()).withdraw(
            msg.sender
        );
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return
            totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }
}
