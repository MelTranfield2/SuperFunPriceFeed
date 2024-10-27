pragma solidity 0.8.26;

import "@api3/contracts/api3-server-v1/proxies/interfaces/IProxy.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);  // Added return type
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);  // Added return type
    function balanceOf(address holder) external view returns (uint256);  // Changed to view function
}

contract Prediction is Ownable {
    struct Participant {
        uint256 amount;
        bool predictedHigher;
        bool hasDeposited;
        bool claimed;
    }

    // Constants
    uint256 public constant PREDICTION_LENGTH = 7 days;
    uint256 public constant PRICE_PREDICTION = 35000;   // 35,000 USD per BTC
    uint256 public constant MIN_USDC = 2 ether;        // Minimum bet amount
    uint256 public constant MAX_PARTICIPANTS = 10;      // Maximum participants

    // State variables
    uint256 public startBetTimestamp;
    uint256 public participantCount;
    uint256 public totalHigherAmount;
    uint256 public totalLowerAmount;
    bool public betInitiated;                          // Fixed capitalization

    address public immutable proxyAddress;             // Made immutable
    IERC20 public immutable USDC;                     // Made immutable

    // Mappings and arrays
    mapping(address => Participant) public participants;
    address[] public participantAddresses;

    // Events
    event ParticipantJoined(address indexed participant, uint256 amount, bool predictedHigher);
    event BetInitiated(uint256 timestamp);
    event BetClosed(uint256 finalPrice, bool higherWon);
    event RewardClaimed(address indexed participant, uint256 amount);

    constructor(address _proxyAddress, address _USDC) {
        require(_proxyAddress != address(0), "Invalid proxy address");
        require(_USDC != address(0), "Invalid USDC address");
        proxyAddress = _proxyAddress;
        USDC = IERC20(_USDC);
    }

    /// @notice Place a bet on the price movement
    function placeBet(bool predictHigher) external {
        require(!betInitiated || block.timestamp < startBetTimestamp + 1 days, "Betting period closed");
        require(participantCount < MAX_PARTICIPANTS, "Maximum participants reached");
        require(!participants[msg.sender].hasDeposited, "Already participated");

        require(USDC.transferFrom(msg.sender, address(this), MIN_USDC), "Transfer failed");

        participants[msg.sender] = Participant({
            amount: MIN_USDC,
            predictedHigher: predictHigher,
            hasDeposited: true,
            claimed: false
        });

        if (predictHigher) {
            totalHigherAmount += MIN_USDC;
        } else {
            totalLowerAmount += MIN_USDC;
        }

        participantAddresses.push(msg.sender);
        participantCount++;

        if (!betInitiated) {
            betInitiated = true;
            startBetTimestamp = block.timestamp;
            emit BetInitiated(startBetTimestamp);
        }

        emit ParticipantJoined(msg.sender, MIN_USDC, predictHigher);
    }

    /// @notice Close the prediction bet
    function closePrediction() external {
        require(betInitiated, "Bet not initiated");
        require(block.timestamp >= startBetTimestamp + PREDICTION_LENGTH, "Bet not finished");
        
        (uint256 price, uint256 priceTimestamp) = readDataFeed();
        require(priceTimestamp >= (block.timestamp - 3 minutes), "Price Stale");
        
        bool higherWon = price >= PRICE_PREDICTION;
        emit BetClosed(price, higherWon);

        betInitiated = false;
    }

    /// @notice Claim rewards for winners
    function claimReward() external {
        require(!betInitiated, "Bet still active");
        require(participants[msg.sender].hasDeposited, "Not a participant");
        require(!participants[msg.sender].claimed, "Already claimed!");

        (uint256 price, ) = readDataFeed();
        bool higherWon = price >= PRICE_PREDICTION;
        require(participants[msg.sender].predictedHigher == higherWon, "Did not win");

        uint256 totalPot = totalHigherAmount + totalLowerAmount;
        uint256 winningPot = higherWon ? totalHigherAmount : totalLowerAmount;
        
        uint256 reward = (participants[msg.sender].amount * totalPot) / winningPot;
        
        participants[msg.sender].claimed = true;
        require(USDC.transfer(msg.sender, reward), "Transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    /// @notice Read price feed data
    function readDataFeed() public view returns (uint256, uint256) {
        (int224 value, uint256 timestamp) = IProxy(proxyAddress).read();
        uint256 price = uint224(value);
        return (price, timestamp);
    }

    // Added helper functions
    function getParticipantCount() external view returns (uint256) {
        return participantCount;
    }

    function getBetStatus() external view returns (
        bool isActive,
        uint256 timeRemaining,
        uint256 currentPrice
    ) {
        (uint256 price, ) = readDataFeed();
        
        uint256 remaining = 0;
        if (betInitiated && block.timestamp < startBetTimestamp + PREDICTION_LENGTH) {
            remaining = startBetTimestamp + PREDICTION_LENGTH - block.timestamp;
        }
        
        return (betInitiated, remaining, price);
    }
}