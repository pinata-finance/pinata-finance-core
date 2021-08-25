// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

import "../interfaces/IPinataPrizePool.sol";

/**
 * @dev Implementation of a Random Number Generator to ensure random number is really fair.
 * This contract is VRFConsumerBase which using Chainlink VRF as a source of VRF Number Generator.
 * We only allowed to request random number from PrizePool(s) since every called cost LINK.
 */
contract VRFRandomGenerator is VRFConsumerBase, Ownable {
    bytes32 internal keyHash;
    uint256 internal fee;

    struct Request {
        address requester;
        uint256 roundId;
    }
    mapping(bytes32 => Request) public requests;
    mapping(address => bool) public prizePools;

    /* ========================== Events ========================== */

    /**
     * @dev Emitted when randomness is requested.
     */
    event RequestRandomness(
        bytes32 indexed requestId,
        bytes32 keyHash,
        uint256 seed
    );

    /**
     * @dev Emitted when successfully response randomness to requester.
     */
    event RequestRandomnessFulfilled(
        address requester,
        uint256 randomness
    );

    /* ========================== Modifier ========================== */

    /**
     * @dev Modifier to make a function callable only when called by PrizePool.
     *
     * Requirements:
     *
     * - The caller have to be setted as prize pool.
     */
    modifier onlyPrizePool {
        require(
            prizePools[msg.sender],
            "RNGenerator: Requester may only be PrizePool."
        );
        _;
    }

    /* ========================== Functions ========================== */

    /**
     * @dev Setting up contract for using with Chainlink's VRF.
     * @param _vrfCoordinator address of the Chainlink's VRF Coordinator.
     * @param _linkToken address of LINK token.
     */
    constructor(address _vrfCoordinator, address _linkToken)
        public
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        keyHash = 0xc251acd21ec4fb7f31bb8868288bfdbaeb4fbfec2df3735ddbd4f7dc8d60103c;
        fee = 0.2 * 10**18; // 0.2 LINK (Varies by network)
    }

    /**
     * @dev Function using to requesting for randomness
     *  can only be call from Prize Pool
     * @param roundId is current round of requesting prize pool.
     * @param seed is an user provided seed for random number.
     */
    function getRandomNumber(uint256 roundId, uint256 seed)
        public
        onlyPrizePool
        returns (bytes32 requestId)
    {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        bytes32 _requestId = requestRandomness(keyHash, fee, seed);

        requests[_requestId] = Request(msg.sender, roundId);

        emit RequestRandomness(_requestId, keyHash, seed);

        return _requestId;
    }

    /**
     * @dev A Callback function which calling by Chainlink to
     *  serve the randomness to us
     * Then return randomness to corresponding requester
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        Request memory _request = requests[requestId];

        IPinataPrizePool(_request.requester).numbersDrawn(
            requestId,
            _request.roundId,
            randomness
        );

        emit RequestRandomnessFulfilled(_request.requester, randomness);

        delete requests[requestId];
    }

    /* ========================== Admin Setter ========================== */

    /**
     * @dev A function use to set Chainlink VRF keyhash only allow by owner of the contract.
     */
    function setKeyHash(bytes32 _keyHash) external onlyOwner {
        keyHash = _keyHash;
    }

    /**
     * @dev A function use to set Chainlink VRF fee only allow by owner of the contract.
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @dev A function use to set prize pool activation.
     * only allow by owner of the contract
     */
    function setPrizePool(address _prizePoolAddress, bool activate)
        external
        onlyOwner
    {
        prizePools[_prizePoolAddress] = activate;
    }
}
