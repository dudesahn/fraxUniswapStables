// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface Uni {

    function earned(address account)
        external
        view
        returns (uint256 profit);

    function combinedWeightOf(address account)
        external
        view
        returns (uint256 amount);

    function userStakedFrax(address account)
        external
        view
        returns (uint256 stakedFrax);

    function veFXSMultiplier(address account)
        external
        view
        returns (uint256 multiplier);

    function withdrawalsPaused() external view returns (bool);

    function stakeLocked(uint256 token_id, uint256 _seconds)
        external;

    function withdrawLocked(uint256 token_id) external;

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForTokens(
        uint256,
        uint256,
        address[] calldata,
        address,
        uint256
    ) external;

    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        returns (uint256[] memory amounts);
}
