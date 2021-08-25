// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../libraries/SortitionSumTreeFactory.sol";
import "../libraries/UniformRandomNumber.sol";

import "../interfaces/IRNGenerator.sol";
import "../interfaces/IPinataManager.sol";

import "../manager/PinataManageable.sol";

/**
 * @dev Implementation of a prize pool to holding funds that would be distributed as prize for lucky winners.
 * This is the contract that receives funds from strategy (when harvesting) and distribute it when drawing time come.
 */
contract PrizePool is PinataManageable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SortitionSumTreeFactory for SortitionSumTreeFactory.SortitionSumTrees;

    /* ========================== Variables ========================== */

    // Structure
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

    // Constant
    uint256 private constant MAX_TREE_LEAVES = 5;
    bytes32 public constant SUM_TREE_KEY = "PrizePool";

    IERC20 public prizeToken;

    // RandomNumberGenerator
    bytes32 internal _requestId;
    uint256 internal _randomness;

    // State
    SortitionSumTreeFactory.SortitionSumTrees private sortitionSumTrees;
    mapping(address => Entry) private entries;
    uint256 public numOfParticipants;
    uint8 public numOfWinners;
    uint256 public _totalChances;
    uint256 public currentRound;
    mapping(uint256 => History) public histories;
    uint256 public allocatedRewards;
    uint256 public claimedRewards;

    /* ========================== Events ========================== */

    /**
     * @dev Emitted when reward is claimed.
     */
    event RewardClaimed(address claimer, uint256 amount);

    /**
     * @dev Emitted when drawing reward.
     */
    event DrawReward(bytes32 requestId, uint256 round);

    /**
     * @dev Emitted when winners is selected.
     */
    event WinnersDrawn(uint256 round);

    /**
     * @dev Emitted when reward successfully distributed.
     */
    event RewardDistributed(uint256 round);

    /* ========================== Functions ========================== */

    /**
     * @dev Setting up contract's state, Manager contract which will be use to observe state.
     *  the prize token is token that would be distribute as prize, and number of winners in each round.
     *  also creating a new tree which will need to use.
     * @param _manager address of PinataManager contract.
     * @param _prizeToken address of token will be distribute as reward.
     * @param _numOfWinners is number of lucky winner in each round.
     */
    constructor(
        address _manager,
        address _prizeToken,
        uint8 _numOfWinners
    ) public PinataManageable(_manager) {
        prizeToken = IERC20(_prizeToken);
        numOfWinners = _numOfWinners;
        allocatedRewards = 0;
        claimedRewards = 0;
        _totalChances = 0;
        currentRound = 0;
        numOfParticipants = 0;
        sortitionSumTrees.createTree(SUM_TREE_KEY, MAX_TREE_LEAVES);
    }

    /**
     * @dev add chances to win for participant may only call by vault.
     * @param participant address participant.
     * @param _chances number of chances to win.
     */
    function addChances(address participant, uint256 _chances)
        external
        onlyVault
    {
        require(_chances > 0, "PrizePool: Chances cannot be less than zero");
        _totalChances = _totalChances.add(_chances);
        if (entries[participant].chances > 0) {
            entries[participant].lastEnterId = currentRound;
            entries[participant].lastDeposit = block.timestamp;
            entries[participant].chances = entries[participant].chances.add(
                _chances
            );
        } else {
            entries[participant] = Entry(
                participant,
                _chances,
                currentRound,
                block.timestamp,
                0
            );
            numOfParticipants = numOfParticipants.add(1);
        }

        sortitionSumTrees.set(
            SUM_TREE_KEY,
            entries[participant].chances,
            bytes32(uint256(participant))
        );
    }

    /**
     * @dev withdraw all of chances of participant.
     * @param participant address participant.
     */
    function withdraw(address participant) external onlyVault {
        require(
            entries[participant].chances > 0,
            "PrizePool: Chances of participant already less than zero"
        );
        _totalChances = _totalChances.sub(entries[participant].chances);
        numOfParticipants = numOfParticipants.sub(1);
        entries[participant].chances = 0;

        sortitionSumTrees.set(SUM_TREE_KEY, 0, bytes32(uint256(participant)));
    }

    /**
     * @dev get chances of participant.
     * @param participant address participant.
     */
    function chancesOf(address participant) public view returns (uint256) {
        return entries[participant].chances;
    }

    /**
     * @dev return owner of ticket id.
     * @param ticketId is ticket id wish to know owner.
     */
    function ownerOf(uint256 ticketId) public view returns (address) {
        if (ticketId >= _totalChances) {
            return address(0);
        }

        return address(uint256(sortitionSumTrees.draw(SUM_TREE_KEY, ticketId)));
    }

    /**
     * @dev draw number to be use in reward distribution process.
     *  calling RandomNumberGenerator and keep requestId to check later when result comes.
     *  only allow to be call by manager.
     */
    function drawNumber() external onlyManager {
        (uint256 openTime, , uint256 drawTime) = getTimeline();
        uint256 timeOfRound = drawTime.sub(openTime);
        require(timeOfRound > 0, "PrizePool: time of round is zeroes!");

        _requestId = IRNGenerator(getRandomNumberGenerator()).getRandomNumber(
            currentRound,
            block.difficulty
        );

        emit DrawReward(_requestId, currentRound);
    }

    /**
     * @dev callback function for RandomNumberGenerator to return randomness.
     *  after randomness is recieve this contract would use it to distribute rewards.
     *  from funds inside the contract.
     *  this function is only allow to be call from random generator to ensure fairness.
     */
    function numbersDrawn(
        bytes32 requestId,
        uint256 roundId,
        uint256 randomness
    ) external onlyRandomGenerator {
        require(requestId == _requestId, "PrizePool: requestId not match!");
        require(roundId == currentRound, "PrizePool: roundId not match!");

        _randomness = randomness;

        manager.winnersCalculated();

        emit WinnersDrawn(currentRound);
    }

    /**
     * @dev internal function to calculate rewards with randomness got from RandomNumberGenerator.
     */
    function distributeRewards()
        public
        onlyTimekeeper
        whenInState(IPinataManager.LOTTERY_STATE.WINNERS_PENDING)
        returns (address[] memory, uint256)
    {
        address[] memory _winners = new address[](numOfWinners);
        uint256 allocatablePrize = allocatePrize();
        uint256 roundReward = 0;

        if (allocatablePrize > 0 && _totalChances > 0) {
            for (uint8 winner = 0; winner < numOfWinners; winner++) {
                // Picking ticket index that won the prize.
                uint256 winnerIdx = _selectRandom(
                    uint256(keccak256(abi.encode(_randomness, winner)))
                );
                // Address of ticket owner
                _winners[winner] = ownerOf(winnerIdx);

                Entry storage _winner = entries[_winners[winner]];
                // allocated prize for reward winner
                uint256 allocatedRewardFor = _allocatedRewardFor(
                    _winners[winner],
                    allocatablePrize.div(numOfWinners)
                );
                // set claimableReward for winner
                _winner.claimableReward = _winner.claimableReward.add(
                    allocatedRewardFor
                );
                roundReward = roundReward.add(allocatedRewardFor);
            }
        }

        allocatedRewards = allocatedRewards.add(roundReward);

        histories[currentRound] = History(
            currentRound,
            _randomness,
            _winners,
            roundReward
        );
        currentRound = currentRound.add(1);

        manager.rewardDistributed();

        emit RewardDistributed(currentRound.sub(1));
    }

    /**
     * @dev internal function to calculate reward for each winner.
     */
    function _allocatedRewardFor(address _winner, uint256 _allocatablePrizeFor)
        internal
        returns (uint256)
    {
        uint256 calculatedReward = 0;

        (uint256 openTime, , uint256 drawTime) = getTimeline();
        if (entries[_winner].lastDeposit >= openTime) {
            // Check if enter before openning of current round.
            uint256 timeOfRound = drawTime.sub(openTime);
            uint256 timeStaying = drawTime.sub(entries[_winner].lastDeposit);
            calculatedReward = _allocatablePrizeFor.mul(timeStaying).div(
                timeOfRound
            );

            // left over reward will be send back to vault.
            prizeToken.safeTransfer(
                getVault(),
                _allocatablePrizeFor.sub(calculatedReward)
            );
        } else {
            calculatedReward = _allocatablePrizeFor;
        }

        return calculatedReward;
    }

    /**
     * @dev function for claming reward.
     * @param _amount is amount of reward to claim
     */
    function claimReward(uint256 _amount) public {
        Entry storage claimer = entries[msg.sender];

        if (_amount > claimer.claimableReward) {
            _amount = claimer.claimableReward;
        }

        claimedRewards = claimedRewards.add(_amount);
        claimer.claimableReward = claimer.claimableReward.sub(_amount);

        prizeToken.safeTransfer(msg.sender, _amount);

        emit RewardClaimed(msg.sender, _amount);
    }

    /**
     * @dev get allocatePrize for current round.
     */
    function allocatePrize() public view returns (uint256) {
        return
            prizeToken.balanceOf(address(this)).add(claimedRewards).sub(
                allocatedRewards
            );
    }

    /**
     * @dev Selects a random number in the range [0, randomness)
     * @param randomness total The upper bound for the random number.
     */
    function _selectRandom(uint256 randomness) internal view returns (uint256) {
        return UniformRandomNumber.uniform(randomness, _totalChances);
    }

    /**
     * @dev entry info of participant.
     */
    function getEntryInfo(address _entry) public view returns (Entry memory) {
        return entries[_entry];
    }

    /**
     * @dev return number of participant in prize pool.
     */
    function getNumOfParticipants() public view returns (uint256) {
        return numOfParticipants;
    }

    /**
     * @dev get history of reward round.
     * @param _round is round wish to know history
     */
    function getHistory(uint256 _round)
        public
        view
        returns (History memory history)
    {
        return histories[_round];
    }

    /**
     * @dev use when want to retire prize pool.
     *  transfer all of token that has not been distribute as reward yet to vault.
     */
    function retirePrizePool() external onlyManager {
        IERC20(prizeToken).transfer(getVault(), allocatePrize());
    }
}
