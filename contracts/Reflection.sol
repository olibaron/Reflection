// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ReflectionToken is ERC20, Ownable, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;

    uint256 public taxRate = 5; // Example 5% tax
    uint256 public liquidityRate = 2; // 2% liquidity
    uint256 public minimumTaxThreshold = 1 ether; // Example threshold for triggering tax wallet
    uint256 public lastDistributionTime;
    uint256 public distributionInterval = 888 * 15; // Example time for distribution (3 hours with block time ~15s)

    address public rewardsWallet;
    address public liquidityWallet;
    address public taxWallet;

    mapping(address => bool) private excludedFromRewards;
    EnumerableSet.AddressSet private holders;

    event RewardsDistributed(uint256 amount, uint256 time);
    event TaxRateUpdated(uint256 newTaxRate);
    event LiquidityRateUpdated(uint256 newLiquidityRate);
    event MinimumTaxThresholdUpdated(uint256 newThreshold);
    event DistributionIntervalUpdated(uint256 newInterval);

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

        _updateHolders(sender, recipient);

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

        _distributeToHolders(amountToDistribute);
        lastDistributionTime = block.timestamp;

        emit RewardsDistributed(amountToDistribute, block.timestamp);
    }

    // Internal function to handle tax wallet transfer to rewards wallet
    function _sendToTaxWallet() internal {
        uint256 taxBalance = balanceOf(address(this));
        super._transfer(address(this), taxWallet, taxBalance);
        payable(rewardsWallet).transfer(address(this).balance); // Send ETH to rewards wallet
    }

    // Internal function to distribute ETH to holders
    function _distributeToHolders(uint256 amount) internal {
        uint256 totalSupply_ = totalSupply();
        uint256 numHolders = holders.length();

        for (uint256 i = 0; i < numHolders; i++) {
            address holder = holders.at(i);
            if (!excludedFromRewards[holder] && balanceOf(holder) > 0) {
                uint256 holderBalance = balanceOf(holder);
                uint256 holderShare = (amount * holderBalance) / totalSupply_;
                payable(holder).transfer(holderShare);
            }
        }
    }

    // Function to set tax rate
    function setTaxRate(uint256 newTaxRate) external onlyOwner {
        require(newTaxRate <= 10, "Tax rate too high"); // Example upper limit
        taxRate = newTaxRate;
        emit TaxRateUpdated(newTaxRate);
    }

    // Function to set liquidity rate
    function setLiquidityRate(uint256 newLiquidityRate) external onlyOwner {
        require(newLiquidityRate <= 5, "Liquidity rate too high"); // Example upper limit
        liquidityRate = newLiquidityRate;
        emit LiquidityRateUpdated(newLiquidityRate);
    }

    // Function to set minimum tax threshold
    function setMinimumTaxThreshold(uint256 newThreshold) external onlyOwner {
        minimumTaxThreshold = newThreshold;
        emit MinimumTaxThresholdUpdated(newThreshold);
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
        emit DistributionIntervalUpdated(intervalInSeconds);
    }

    // Add or remove addresses from exclusion
    function setExcludedFromRewards(
        address account,
        bool excluded
    ) external onlyOwner {
        excludedFromRewards[account] = excluded;
    }

    // Update the holders set on transfer
    function _updateHolders(address sender, address recipient) internal {
        if (balanceOf(sender) == 0) {
            holders.remove(sender);
        }
        if (balanceOf(recipient) > 0 && !holders.contains(recipient)) {
            holders.add(recipient);
        }
    }
}
