// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import './FullMath.sol';
import './FixedPoint96.sol';
import './LiquidityAmounts.sol';
import './TickMath.sol';
import "../../interfaces/uniswap/IUniNFT.sol";

/// @title Position amount functions
/// @notice Provides functions for computing position value
library PositionValue {

    function principal(contract uniNFT, tokenId, uint160 sqrtRatioX96)
     internal view returns (uint256 amount0, uint256 amount1) {

        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , ,) = IUniNFT(uniNFT).positions(tokenId);

        return
        LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

}