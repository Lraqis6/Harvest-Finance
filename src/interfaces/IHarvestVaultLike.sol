// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

/// @title Harvest 金库接口
/// @dev 重要事实：Harvest 的 VaultProxy 本身就是 ERC20 份额代币（fUSDC/fUSDT），
///      deposit / withdraw / balanceOf / totalSupply / underlying / strategy 全在同一个地址上。
interface IHarvestVaultLike {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function underlying() external view returns (address);
    function strategy() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function getPricePerFullShare() external view returns (uint256);
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function governance() external view returns (address);
}

/// @title Harvest 策略接口（只用到套利闸门）
interface IHarvestStrategyLike {
    /// @notice 存款前的 3% 套利阈值闸门；金库 _deposit() 内部 require(strategy.depositArbCheck())
    function depositArbCheck() external view returns (bool);
}
