pragma solidity 0.8.26;

import "@api3/contracts/api3-server-v1/proxies/interfaces/IProxy.sol";
import "@openzeppelin/contracts@4.9.3/access/Ownable.sol";

interface IERC20 {
    function approve(address spender, uint256 amount) external;
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address holder) external view returns (uint256);
}

contract Prediction is Ownable {
    struct Participant {
        uint256 amount;
        bool predictedHigher;
        bool hasDeposited;
        bool claimed;
    }

    enum BetState { OPEN, ACTIVE, CLOSED }

    // Constants
    uint256 public constant PREDICTION_LENGTH = 5 minutes;  // Shortened for testing
    uint256 public constant PRICE_PREDICTION = 35000;      // 35,000 USD per BTC
    uint256 public constant MIN_USDC = 2 ether;           
    uint256 public constant MAX_PARTICIPANTS = 10;
    uint256 public constant MIN_PARTICIPANTS = 2;          // Added minimum participants

    // State variables
    uint256 public startBetTimestamp;
    uint256 public participantCount;
    uint256 public totalHigherAmount;
    uint256 public totalLowerAmount;
    BetState public betState;

    address public immutable proxyAddress;
    IERC20 public immutable USDC;

    mapping(address => Participant) public participants;
    address[] public participantAddresses;

    // Events
    event ParticipantJoined(address indexed participant, uint256 amount, bool predictedHigher);
    event BetStarted(uint256 timestamp, uint256 requiredParticipants);
    event BetActivated(uint256 timestamp, uint256 participants);
    event BetClosed(uint256 finalPrice, bool higherWon);
    event RewardClaimed(address indexed participant, uint256 amount);
    event DebugLog(string message, uint256 value);  // Debug event
    event PendingLog(string message, uint256 timestamp);
    event DebugClosePrediction(string message, uint256 value);

    constructor(address _proxyAddress, address _USDC) {
        require(_proxyAddress != address(0), "Invalid proxy address");
        require(_USDC != address(0), "Invalid USDC address");
        proxyAddress = _proxyAddress;
        USDC = IERC20(_USDC);
        betState = BetState.OPEN;
    }

    function placeBet(bool predictHigher) external {
        require(betState == BetState.OPEN, "Bet not open for new participants");
        require(participantCount < MAX_PARTICIPANTS, "Maximum participants reached");
        require(!participants[msg.sender].hasDeposited, "Already participated");

        emit DebugLog("Starting placeBet", participantCount);

        require(USDC.transferFrom(msg.sender, address(this), MIN_USDC), "Transfer failed");

        participants[msg.sender] = Participant({
            amount: MIN_USDC,
            predictedHigher: predictHigher,
            hasDeposited: true,
            claimed: false
        });

        if (predictHigher) {
            totalHigherAmount += 200;
        } else {
            totalLowerAmount += 200;
        }

        participantAddresses.push(msg.sender);
        participantCount++;

        emit ParticipantJoined(msg.sender, MIN_USDC, predictHigher);

        // Check if we have enough participants to start
        if (participantCount >= MIN_PARTICIPANTS) {
            betState = BetState.ACTIVE;
            startBetTimestamp = block.timestamp;
            emit BetActivated(startBetTimestamp, participantCount);
        }

        emit DebugLog("Completed placeBet", participantCount);
    }

    function closePrediction() external {
        emit PendingLog("Transaction started...", block.timestamp);
        //require(betState == BetState.ACTIVE, "Bet not active");
        //require(block.timestamp >= startBetTimestamp + PREDICTION_LENGTH, "Bet not finished");
        
        (uint256 price, uint256 priceTimestamp) = readDataFeed();
        //require(priceTimestamp >= (block.timestamp - 3 minutes), "Price Stale");
        
        bool higherWon = price >= PRICE_PREDICTION;
        betState = BetState.CLOSED;
        
        emit BetClosed(price, higherWon);
        emit DebugClosePrediction("Prediction closed succesfully", price);
    }

    function claimReward() external {
        //require(betState == BetState.CLOSED, "Bet not closed");
        //require(participants[msg.sender].hasDeposited, "Not a participant");
        //require(!participants[msg.sender].claimed, "Already claimed!");

        (uint256 price, ) = readDataFeed();
        bool higherWon = price >= PRICE_PREDICTION;
        //require(participants[msg.sender].predictedHigher == higherWon, "Did not win");

        uint256 totalPot = totalHigherAmount + totalLowerAmount +200;
        uint256 winningPot = higherWon ? totalHigherAmount : totalLowerAmount;
        
        uint256 reward = (participants[msg.sender].amount * totalPot) / winningPot;
        
        participants[msg.sender].claimed = true;
        //require(USDC.transfer(msg.sender, reward), "Transfer failed");

        emit RewardClaimed(msg.sender, reward);
    }

    function readDataFeed() public view returns (uint256, uint256) {
        (int224 value, uint256 timestamp) = IProxy(proxyAddress).read();
        uint256 price = uint224(value);
        return (price, timestamp);
    }

    // Added helper functions
    function getBetState() external view returns (
        BetState state,
        uint256 currentParticipants,
        uint256 timeRemaining,
        uint256 currentPrice,
        uint256 targetPrice
    ) {
        (uint256 price, ) = readDataFeed();
        
        uint256 remaining = 0;
        if (betState == BetState.ACTIVE) {
            if (block.timestamp < startBetTimestamp + PREDICTION_LENGTH) {
                remaining = startBetTimestamp + PREDICTION_LENGTH - block.timestamp;
            }
        }
        
        return (
            betState,
            participantCount,
            remaining,
            price,
            PRICE_PREDICTION
        );
    }

    function getParticipantInfo(address participant) external view returns (
        bool hasParticipated,
        bool predictedHigher,
        bool hasClaimed,
        uint256 amount
    ) {
        Participant memory p = participants[participant];
        return (
            p.hasDeposited,
            p.predictedHigher,
            p.claimed,
            p.amount
        );
    }

    // Emergency function to return funds if bet gets stuck
    function emergencyReturn() external onlyOwner {
        require(betState == BetState.OPEN || 
                (betState == BetState.ACTIVE && participantCount < MIN_PARTICIPANTS), 
                "Cannot emergency return in current state");
        
        for (uint i = 0; i < participantAddresses.length; i++) {
            address participant = participantAddresses[i];
            if (participants[participant].hasDeposited && !participants[participant].claimed) {
                uint256 amount = participants[participant].amount;
                participants[participant].claimed = true;
                require(USDC.transfer(participant, amount), "Transfer failed");
            }
        }
        
        betState = BetState.CLOSED;
    }
}