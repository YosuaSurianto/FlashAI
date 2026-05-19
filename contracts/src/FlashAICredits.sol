// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FlashAICredits
 * @notice Pay-per-use AI credit system on Celo using cUSD
 * @dev Users top-up cUSD credits. Backend agent deducts per AI request (onchain tx).
 *
 * Architecture:
 *   User → topUp(amount)             → credits[user] += amount
 *   Backend → useCredit(user, cost)  → credits[user] -= cost  (1 tx per AI request)
 *   Owner → withdraw()               → pull cUSD platform fees
 */
contract FlashAICredits is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ─── State ────────────────────────────────────────────────────────────────

    IERC20 public immutable cUSD;
    address public owner;
    address public authorizedAgent; // Backend Golang wallet — only this can call useCredit()

    mapping(address => uint256) public credits; // user address → cUSD balance (18 decimals)

    // ─── Pricing Constants (in cUSD, 18 decimals) ─────────────────────────────

    uint256 public constant PRICE_TEXT_SHORT   = 0.02 ether; // 0.02 cUSD — text generation short
    uint256 public constant PRICE_TEXT_LONG    = 0.05 ether; // 0.05 cUSD — text generation long
    uint256 public constant PRICE_TRANSLATION  = 0.02 ether; // 0.02 cUSD — translation
    uint256 public constant PRICE_SUMMARIZER   = 0.03 ether; // 0.03 cUSD — summarizer
    uint256 public constant PRICE_IMAGE        = 0.10 ether; // 0.10 cUSD — image generation

    uint256 public constant MIN_TOPUP          = 0.10 ether; // min top-up 0.10 cUSD
    uint256 public constant MAX_TOPUP          = 100 ether;  // max top-up 100 cUSD per tx

    // ─── Events ───────────────────────────────────────────────────────────────

    event CreditToppedUp(address indexed user, uint256 amount, uint256 newBalance);
    event CreditUsed(address indexed user, uint256 cost, string serviceType, uint256 remainingBalance);
    event AuthorizedAgentSet(address indexed oldAgent, address indexed newAgent);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event Withdrawn(address indexed to, uint256 amount);

    // ─── Custom Errors ────────────────────────────────────────────────────────

    error NotOwner();
    error NotAgent();
    error ZeroAddress();
    error InsufficientCredits(uint256 available, uint256 required);
    error TopUpBelowMinimum(uint256 sent, uint256 minimum);
    error TopUpAboveMaximum(uint256 sent, uint256 maximum);
    error NoFundsToWithdraw();
    error AgentNotSet();

    // ─── Modifiers ────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyAgent() {
        if (authorizedAgent == address(0)) revert AgentNotSet();
        if (msg.sender != authorizedAgent) revert NotAgent();
        _;
    }

    // ─── Constructor ──────────────────────────────────────────────────────────

    /**
     * @param _cUSD cUSD token address
     *              Celo Mainnet: 0x765DE816845861e75A25fCA122bb6898B8B1282a
     *              Alfajores:    0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1
     */
    constructor(address _cUSD) {
        if (_cUSD == address(0)) revert ZeroAddress();
        cUSD = IERC20(_cUSD);
        owner = msg.sender;
    }

    // ─── User Functions ───────────────────────────────────────────────────────

    /**
     * @notice Top-up AI credits using cUSD
     * @dev User must call cUSD.approve(address(this), amount) first
     * @param amount Amount of cUSD to deposit (18 decimals, min 0.10 cUSD)
     */
    function topUp(uint256 amount) external nonReentrant {
        if (amount < MIN_TOPUP) revert TopUpBelowMinimum(amount, MIN_TOPUP);
        if (amount > MAX_TOPUP) revert TopUpAboveMaximum(amount, MAX_TOPUP);

        cUSD.safeTransferFrom(msg.sender, address(this), amount);
        credits[msg.sender] += amount;

        emit CreditToppedUp(msg.sender, amount, credits[msg.sender]);
    }

    /**
     * @notice Get a user's current credit balance
     * @param user Address to query
     * @return balance in cUSD (18 decimals)
     */
    function getBalance(address user) external view returns (uint256 balance) {
        return credits[user];
    }

    // ─── Agent Functions (Backend Golang Wallet) ──────────────────────────────

    /**
     * @notice Deduct credits for an AI service request — called by backend per request
     * @dev This creates 1 onchain tx per AI call — key for transaction count scoring
     * @param user Address of the user who made the AI request
     * @param cost Cost to deduct in cUSD (18 decimals) — use PRICE_* constants
     * @param serviceType Human-readable service name for event log ("text_short", "translate", etc.)
     */
    function useCredit(
        address user,
        uint256 cost,
        string calldata serviceType
    ) external onlyAgent nonReentrant {
        if (user == address(0)) revert ZeroAddress();
        if (credits[user] < cost) {
            revert InsufficientCredits(credits[user], cost);
        }

        credits[user] -= cost;

        emit CreditUsed(user, cost, serviceType, credits[user]);
    }

    /**
     * @notice Batch useCredit for multiple users — useful for bulk settlement
     * @dev Saves gas when processing multiple requests at once
     */
    function batchUseCredit(
        address[] calldata users,
        uint256[] calldata costs,
        string[] calldata serviceTypes
    ) external onlyAgent nonReentrant {
        require(
            users.length == costs.length && costs.length == serviceTypes.length,
            "FlashAI: array length mismatch"
        );

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 cost = costs[i];

            if (user == address(0)) revert ZeroAddress();
            if (credits[user] < cost) {
                revert InsufficientCredits(credits[user], cost);
            }

            credits[user] -= cost;
            emit CreditUsed(user, cost, serviceTypes[i], credits[user]);
        }
    }

    // ─── Owner Functions ──────────────────────────────────────────────────────

    /**
     * @notice Set the authorized backend agent wallet
     * @dev Call this right after deploy via SetAgent.s.sol
     * @param agent Address of the Golang backend wallet
     */
    function setAuthorizedAgent(address agent) external onlyOwner {
        if (agent == address(0)) revert ZeroAddress();

        address old = authorizedAgent;
        authorizedAgent = agent;

        emit AuthorizedAgentSet(old, agent);
    }

    /**
     * @notice Transfer contract ownership
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address old = owner;
        owner = newOwner;

        emit OwnershipTransferred(old, newOwner);
    }

    /**
     * @notice Withdraw all cUSD from contract to owner
     * @dev Platform revenue accumulates here from user top-ups minus what was used
     *      (cost charged to user > actual AI API cost = platform margin)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = cUSD.balanceOf(address(this));
        if (balance == 0) revert NoFundsToWithdraw();

        cUSD.safeTransfer(owner, balance);

        emit Withdrawn(owner, balance);
    }

    /**
     * @notice Withdraw a specific amount of cUSD to owner
     * @param amount Amount to withdraw
     */
    function withdrawAmount(uint256 amount) external onlyOwner nonReentrant {
        if (amount == 0) revert NoFundsToWithdraw();

        cUSD.safeTransfer(owner, amount);

        emit Withdrawn(owner, amount);
    }

    // ─── View Helpers ─────────────────────────────────────────────────────────

    /**
     * @notice Check how many requests a user can still make for a given service price
     * @param user User address
     * @param pricePerRequest Price per request (use PRICE_* constants)
     * @return Number of requests remaining
     */
    function remainingRequests(address user, uint256 pricePerRequest) external view returns (uint256) {
        if (pricePerRequest == 0) return 0;
        return credits[user] / pricePerRequest;
    }

    /**
     * @notice Total cUSD held in contract (sum of all user credits)
     */
    function totalDeposited() external view returns (uint256) {
        return cUSD.balanceOf(address(this));
    }
}
