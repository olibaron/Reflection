// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ReflectionToken is ERC20, Ownable, ReentrancyGuard {
    uint256 public constant taxRate = 5; // Example 5% tax
    uint256 public constant liquidityRate = 2; // 2% liquidity
    uint256 public constant minimumTaxThreshold = 1 ether; // Example threshold for triggering tax wallet
    uint256 public lastDistributionTime;
    uint256 public distributionInterval = 888 * 15; // Example time for distribution (3 hours with block time ~15s)

    address public rewardsWallet;
    address public liquidityWallet;
    address public taxWallet;

    address[] private holders;
    mapping(address => bool) public holderExists;
    mapping(address => bool) public excludedFromRewards;
    mapping(address => bool) private includedInRewards;

    event RewardsDistributed(uint256 amount, uint256 time);

    constructor(
        string memory name,
        string memory symbol,
        address _rewardsWallet,
        address _liquidityWallet,
        address _taxWallet
    ) ERC20(name, symbol) {
        rewardsWallet = _rewardsWallet;
        liquidityWallet = _liquidityWallet;
        taxWallet = _taxWallet;
        lastDistributionTime = block.timestamp;
    }

    // Allow the contract to receive ETH
    receive() external payable {}

    // Mint function to create new tokens
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    // Override the transfer function to include tax and liquidity handling
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 taxAmount = (amount * taxRate) / 100;
        uint256 liquidityAmount = (amount * liquidityRate) / 100;
        uint256 transferAmount = amount - taxAmount - liquidityAmount;

        super._transfer(sender, address(this), taxAmount); // Collect tax
        super._transfer(sender, liquidityWallet, liquidityAmount); // Add liquidity
        super._transfer(sender, recipient, transferAmount); // Transfer remaining amount

        if (!holderExists[recipient]) {
            holders.push(recipient);
            holderExists[recipient] = true;
        }

        if (balanceOf(address(this)) >= minimumTaxThreshold) {
            _sendToTaxWallet();
        }
    }

    // Function to distribute rewards
    function distributeRewards() external nonReentrant {
        require(
            block.timestamp >= lastDistributionTime + distributionInterval,
            "Distribution interval has not passed"
        );

        uint256 rewardsBalance = address(this).balance;
        require(rewardsBalance > 0, "No rewards to distribute");

        uint256 amountToDistribute = (rewardsBalance * 70) / 100; // 70% to holders

        // State updates before external interactions
        lastDistributionTime = block.timestamp;

        _distributeToHolders(amountToDistribute);

        emit RewardsDistributed(amountToDistribute, block.timestamp);
    }

    // Internal function to handle tax wallet transfer to rewards wallet
    function _sendToTaxWallet() internal nonReentrant {
        uint256 taxBalance = balanceOf(address(this));
        super._transfer(address(this), taxWallet, taxBalance);

        (bool success, ) = payable(rewardsWallet).call{
            value: address(this).balance
        }("");
        require(success, "Transfer to rewards wallet failed.");
    }

    // Internal function to distribute ETH to holders
    function _distributeToHolders(uint256 amount) internal {
        uint256 totalSupply_ = totalSupply();
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if (!excludedFromRewards[holder]) {
                uint256 holderBalance = balanceOf(holder);
                uint256 holderShare = (amount * holderBalance) / totalSupply_;
                (bool success, ) = payable(holder).call{value: holderShare}("");
                require(success, "Transfer to holder failed.");
            }
        }
    }

    // Add or remove addresses from exclusion
    function setExcludedFromRewards(
        address account,
        bool excluded
    ) external onlyOwner {
        excludedFromRewards[account] = excluded;
    }

    // Add addresses to include in rewards
    function setIncludedInRewards(
        address account,
        bool included
    ) external onlyOwner {
        includedInRewards[account] = included;
    }

    // Function to set distribution interval (4-12 hours)
    function setDistributionInterval(
        uint256 intervalInSeconds
    ) external onlyOwner {
        require(
            intervalInSeconds >= 14400 && intervalInSeconds <= 43200,
            "Interval must be between 4 and 12 hours"
        );
        distributionInterval = intervalInSeconds;
    }
}
