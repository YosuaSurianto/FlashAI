// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FlashAICredits.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// ─── Mock cUSD ────────────────────────────────────────────────────────────────

contract MockCUSD is ERC20 {
    constructor() ERC20("Celo Dollar", "cUSD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// ─── Main Test Contract ───────────────────────────────────────────────────────

contract FlashAICreditsTest is Test {
    // Re-declare events for vm.expectEmit (Solidity 0.8.20 limitation)
    event CreditToppedUp(address indexed user, uint256 amount, uint256 newBalance);
    event CreditUsed(address indexed user, uint256 cost, string serviceType, uint256 remainingBalance);
    event AuthorizedAgentSet(address indexed oldAgent, address indexed newAgent);

    FlashAICredits public flashai;
    MockCUSD       public cusd;

    address public owner   = address(0xABCD);
    address public agent   = address(0xBEEF);
    address public alice   = address(0x1111);
    address public bob     = address(0x2222);
    address public charlie = address(0x3333);
    address public nobody  = address(0x9999);

    uint256 constant INITIAL_BALANCE = 100 ether; // 100 cUSD each

    // ─── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        // Deploy mock cUSD
        cusd = new MockCUSD();

        // Deploy contract as owner
        vm.prank(owner);
        flashai = new FlashAICredits(address(cusd));

        // Set authorized agent
        vm.prank(owner);
        flashai.setAuthorizedAgent(agent);

        // Mint cUSD to users
        cusd.mint(alice,   INITIAL_BALANCE);
        cusd.mint(bob,     INITIAL_BALANCE);
        cusd.mint(charlie, INITIAL_BALANCE);
    }

    // ─── Constructor Tests ────────────────────────────────────────────────────

    function test_Constructor_SetsOwner() public view {
        assertEq(flashai.owner(), owner);
    }

    function test_Constructor_SetsCUSD() public view {
        assertEq(address(flashai.cUSD()), address(cusd));
    }

    function test_Constructor_RevertsZeroAddress() public {
        vm.expectRevert(FlashAICredits.ZeroAddress.selector);
        new FlashAICredits(address(0));
    }

    function test_InitialAgentSet() public view {
        assertEq(flashai.authorizedAgent(), agent);
    }

    // ─── TopUp Tests ──────────────────────────────────────────────────────────

    function test_TopUp_Success() public {
        uint256 amount = 1 ether; // 1 cUSD

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);
        flashai.topUp(amount);
        vm.stopPrank();

        assertEq(flashai.getBalance(alice), amount);
        assertEq(cusd.balanceOf(address(flashai)), amount);
        assertEq(cusd.balanceOf(alice), INITIAL_BALANCE - amount);
    }

    function test_TopUp_EmitsEvent() public {
        uint256 amount = 0.5 ether;

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);

        vm.expectEmit(true, false, false, true);
        emit CreditToppedUp(alice, amount, amount);

        flashai.topUp(amount);
        vm.stopPrank();
    }

    function test_TopUp_MultipleTopUps_Accumulate() public {
        vm.startPrank(alice);
        cusd.approve(address(flashai), 10 ether);
        flashai.topUp(1 ether);
        flashai.topUp(2 ether);
        flashai.topUp(0.5 ether);
        vm.stopPrank();

        assertEq(flashai.getBalance(alice), 3.5 ether);
    }

    function test_TopUp_BelowMinimum_Reverts() public {
        uint256 amount = 0.05 ether; // below 0.10 min

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashAICredits.TopUpBelowMinimum.selector,
                amount,
                flashai.MIN_TOPUP()
            )
        );
        flashai.topUp(amount);
        vm.stopPrank();
    }

    function test_TopUp_AboveMaximum_Reverts() public {
        uint256 amount = 101 ether; // above 100 max

        cusd.mint(alice, amount);

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);

        vm.expectRevert(
            abi.encodeWithSelector(
                FlashAICredits.TopUpAboveMaximum.selector,
                amount,
                flashai.MAX_TOPUP()
            )
        );
        flashai.topUp(amount);
        vm.stopPrank();
    }

    function test_TopUp_ExactMinimum_Succeeds() public {
        uint256 amount = flashai.MIN_TOPUP(); // exact 0.10 cUSD

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);
        flashai.topUp(amount);
        vm.stopPrank();

        assertEq(flashai.getBalance(alice), amount);
    }

    // ─── UseCredit Tests ──────────────────────────────────────────────────────

    function _aliceTopUp(uint256 amount) internal {
        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);
        flashai.topUp(amount);
        vm.stopPrank();
    }

    function test_UseCredit_Success() public {
        _aliceTopUp(1 ether);

        uint256 cost = flashai.PRICE_TEXT_SHORT(); // 0.02 cUSD

        vm.prank(agent);
        flashai.useCredit(alice, cost, "text_short");

        assertEq(flashai.getBalance(alice), 1 ether - cost);
    }

    function test_UseCredit_EmitsEvent() public {
        _aliceTopUp(1 ether);

        uint256 cost = flashai.PRICE_TRANSLATION();
        uint256 expectedBalance = 1 ether - cost;

        vm.expectEmit(true, false, false, true);
        emit CreditUsed(alice, cost, "translate", expectedBalance);

        vm.prank(agent);
        flashai.useCredit(alice, cost, "translate");
    }

    function test_UseCredit_OnlyAgent_Reverts_ForNobody() public {
        _aliceTopUp(1 ether);

        vm.prank(nobody);
        vm.expectRevert(FlashAICredits.NotAgent.selector);
        flashai.useCredit(alice, flashai.PRICE_TEXT_SHORT(), "text_short");
    }

    function test_UseCredit_OnlyAgent_Reverts_ForOwner() public {
        _aliceTopUp(1 ether);

        vm.prank(owner);
        vm.expectRevert(FlashAICredits.NotAgent.selector);
        flashai.useCredit(alice, flashai.PRICE_TEXT_SHORT(), "text_short");
    }

    function test_UseCredit_InsufficientCredits_Reverts() public {
        _aliceTopUp(flashai.MIN_TOPUP()); // 0.10 cUSD

        uint256 cost = flashai.PRICE_IMAGE(); // 0.10 cUSD = all credits

        // Use all credits
        vm.prank(agent);
        flashai.useCredit(alice, cost, "image");

        // Try to use more — should revert
        vm.prank(agent);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlashAICredits.InsufficientCredits.selector,
                0,
                flashai.PRICE_TEXT_SHORT()
            )
        );
        flashai.useCredit(alice, flashai.PRICE_TEXT_SHORT(), "text_short");
    }

    function test_UseCredit_ZeroAddressUser_Reverts() public {
        vm.prank(agent);
        vm.expectRevert(FlashAICredits.ZeroAddress.selector);
        flashai.useCredit(address(0), flashai.PRICE_TEXT_SHORT(), "text_short");
    }

    function test_UseCredit_MultipleRequests() public {
        _aliceTopUp(1 ether); // 1 cUSD

        uint256 cost = flashai.PRICE_TEXT_SHORT(); // 0.02 cUSD

        // Simulate 10 AI requests
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(agent);
            flashai.useCredit(alice, cost, "text_short");
        }

        // 1 - (10 * 0.02) = 0.80 cUSD remaining
        assertEq(flashai.getBalance(alice), 1 ether - (cost * 10));
    }

    // ─── BatchUseCredit Tests ─────────────────────────────────────────────────

    function test_BatchUseCredit_Success() public {
        _aliceTopUp(1 ether);

        // Bob top-up
        vm.startPrank(bob);
        cusd.approve(address(flashai), 1 ether);
        flashai.topUp(1 ether);
        vm.stopPrank();

        address[] memory users    = new address[](2);
        uint256[] memory costs    = new uint256[](2);
        string[]  memory types    = new string[](2);

        users[0] = alice; costs[0] = flashai.PRICE_TEXT_SHORT();  types[0] = "text_short";
        users[1] = bob;   costs[1] = flashai.PRICE_TRANSLATION(); types[1] = "translate";

        vm.prank(agent);
        flashai.batchUseCredit(users, costs, types);

        assertEq(flashai.getBalance(alice), 1 ether - flashai.PRICE_TEXT_SHORT());
        assertEq(flashai.getBalance(bob),   1 ether - flashai.PRICE_TRANSLATION());
    }

    function test_BatchUseCredit_ArrayMismatch_Reverts() public {
        address[] memory users = new address[](2);
        uint256[] memory costs = new uint256[](1); // mismatch!
        string[]  memory types = new string[](2);

        vm.prank(agent);
        vm.expectRevert("FlashAI: array length mismatch");
        flashai.batchUseCredit(users, costs, types);
    }

    // ─── SetAuthorizedAgent Tests ─────────────────────────────────────────────

    function test_SetAgent_Success() public {
        address newAgent = address(0xCAFE);

        vm.prank(owner);
        flashai.setAuthorizedAgent(newAgent);

        assertEq(flashai.authorizedAgent(), newAgent);
    }

    function test_SetAgent_EmitsEvent() public {
        address newAgent = address(0xCAFE);
        address oldAgent = flashai.authorizedAgent();

        vm.expectEmit(true, true, false, false);
        emit AuthorizedAgentSet(oldAgent, newAgent);

        vm.prank(owner);
        flashai.setAuthorizedAgent(newAgent);
    }

    function test_SetAgent_OnlyOwner_Reverts() public {
        vm.prank(nobody);
        vm.expectRevert(FlashAICredits.NotOwner.selector);
        flashai.setAuthorizedAgent(address(0xCAFE));
    }

    function test_SetAgent_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(FlashAICredits.ZeroAddress.selector);
        flashai.setAuthorizedAgent(address(0));
    }

    // ─── Withdraw Tests ───────────────────────────────────────────────────────

    function test_Withdraw_Success() public {
        _aliceTopUp(1 ether);

        uint256 ownerBalanceBefore = cusd.balanceOf(owner);

        vm.prank(owner);
        flashai.withdraw();

        assertEq(cusd.balanceOf(owner), ownerBalanceBefore + 1 ether);
        assertEq(cusd.balanceOf(address(flashai)), 0);
    }

    function test_Withdraw_OnlyOwner_Reverts() public {
        _aliceTopUp(1 ether);

        vm.prank(nobody);
        vm.expectRevert(FlashAICredits.NotOwner.selector);
        flashai.withdraw();
    }

    function test_Withdraw_EmptyBalance_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(FlashAICredits.NoFundsToWithdraw.selector);
        flashai.withdraw();
    }

    // ─── TransferOwnership Tests ──────────────────────────────────────────────

    function test_TransferOwnership_Success() public {
        vm.prank(owner);
        flashai.transferOwnership(alice);

        assertEq(flashai.owner(), alice);
    }

    function test_TransferOwnership_OnlyOwner_Reverts() public {
        vm.prank(nobody);
        vm.expectRevert(FlashAICredits.NotOwner.selector);
        flashai.transferOwnership(alice);
    }

    function test_TransferOwnership_ZeroAddress_Reverts() public {
        vm.prank(owner);
        vm.expectRevert(FlashAICredits.ZeroAddress.selector);
        flashai.transferOwnership(address(0));
    }

    // ─── View Helper Tests ────────────────────────────────────────────────────

    function test_RemainingRequests() public {
        _aliceTopUp(1 ether); // 1 cUSD

        uint256 remaining = flashai.remainingRequests(alice, flashai.PRICE_TEXT_SHORT());
        // 1 cUSD / 0.02 cUSD = 50 requests
        assertEq(remaining, 50);
    }

    function test_RemainingRequests_ZeroPrice_ReturnsZero() public view {
        assertEq(flashai.remainingRequests(alice, 0), 0);
    }

    function test_TotalDeposited() public {
        _aliceTopUp(2 ether);

        vm.startPrank(bob);
        cusd.approve(address(flashai), 3 ether);
        flashai.topUp(3 ether);
        vm.stopPrank();

        assertEq(flashai.totalDeposited(), 5 ether);
    }

    // ─── Pricing Constants Tests ──────────────────────────────────────────────

    function test_PricingConstants() public view {
        assertEq(flashai.PRICE_TEXT_SHORT(),  0.02 ether);
        assertEq(flashai.PRICE_TEXT_LONG(),   0.05 ether);
        assertEq(flashai.PRICE_TRANSLATION(), 0.02 ether);
        assertEq(flashai.PRICE_SUMMARIZER(),  0.03 ether);
        assertEq(flashai.PRICE_IMAGE(),       0.10 ether);
    }

    // ─── Full E2E Flow Test ────────────────────────────────────────────────────

    function test_FullFlow_TopUpAndMultipleAIRequests() public {
        // 1. Alice top-up 5 cUSD
        vm.startPrank(alice);
        cusd.approve(address(flashai), 5 ether);
        flashai.topUp(5 ether);
        vm.stopPrank();

        assertEq(flashai.getBalance(alice), 5 ether);

        // 2. Simulate various AI requests from backend agent
        vm.startPrank(agent);
        flashai.useCredit(alice, flashai.PRICE_TEXT_SHORT(),  "text_short");  // -0.02
        flashai.useCredit(alice, flashai.PRICE_TRANSLATION(), "translate");   // -0.02
        flashai.useCredit(alice, flashai.PRICE_TEXT_LONG(),   "text_long");   // -0.05
        flashai.useCredit(alice, flashai.PRICE_SUMMARIZER(),  "summarize");   // -0.03
        flashai.useCredit(alice, flashai.PRICE_IMAGE(),       "image");       // -0.10
        vm.stopPrank();

        // Total deducted: 0.02 + 0.02 + 0.05 + 0.03 + 0.10 = 0.22 cUSD
        assertEq(flashai.getBalance(alice), 5 ether - 0.22 ether);

        // 3. Owner withdraws platform revenue
        uint256 contractBalance = cusd.balanceOf(address(flashai));
        assertEq(contractBalance, 5 ether); // All of alice's deposit still in contract

        vm.prank(owner);
        flashai.withdraw();

        assertEq(cusd.balanceOf(address(flashai)), 0);
    }

    // ─── Fuzz Tests ───────────────────────────────────────────────────────────

    function testFuzz_TopUp_ValidAmount(uint256 amount) public {
        amount = bound(amount, flashai.MIN_TOPUP(), flashai.MAX_TOPUP());

        cusd.mint(alice, amount);

        vm.startPrank(alice);
        cusd.approve(address(flashai), amount);
        flashai.topUp(amount);
        vm.stopPrank();

        assertEq(flashai.getBalance(alice), INITIAL_BALANCE + amount); // fuzz adds on top
    }

    function testFuzz_UseCredit_ValidCost(uint256 cost) public {
        uint256 deposit = 10 ether;
        cost = bound(cost, 1, deposit); // cost between 1 wei and full deposit

        _aliceTopUp(deposit);

        vm.prank(agent);
        flashai.useCredit(alice, cost, "fuzz_service");

        assertEq(flashai.getBalance(alice), deposit - cost);
    }
}
