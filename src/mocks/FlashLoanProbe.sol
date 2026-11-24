// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "../interfaces/IERC20Like.sol";
import "../interfaces/IUniswapV2PairLike.sol";
import "../libraries/FlashFee.sol";

/// @title 最小闪电兑换探针：只借、只还，用来单独验证回调签名与手续费公式
contract FlashLoanProbe {
    address public immutable token;
    address public immutable pair;
    uint256 public borrowed;
    uint256 public repaid;

    constructor(address _pair, address _token) {
        pair = _pair;
        token = _token;
    }

    /// @param amount 想借的数量
    /// @param shortfall 故意少还的 wei 数（用于验证 k 校验会拒绝），0 表示足额还
    function run(uint256 amount, uint256 shortfall) external {
        borrowed = amount;
        bool isToken1 = IUniswapV2PairLike(pair).token1() == token;
        IUniswapV2PairLike(pair).swap(isToken1 ? 0 : amount, isToken1 ? amount : 0, address(this), abi.encode(shortfall));
    }

    function uniswapV2Call(address, uint256, uint256, bytes calldata data) external {
        require(msg.sender == pair, "bad pair");
        uint256 shortfall = abi.decode(data, (uint256));
        uint256 pay = FlashFee.owed(borrowed) - shortfall;
        repaid = pay;
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(IERC20Like.transfer.selector, pair, pay));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "repay failed");
    }
}
