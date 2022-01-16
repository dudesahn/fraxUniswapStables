// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IFrax {


    function stakeLocked(uint256 token_id, uint256 _seconds) external;

    function withdrawLocked(uint256 token_id) external;

    function getReward() external;

    // read-only functions below

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

    function rewardsCollectionPaused() external view returns (bool);

    function lock_time_min() external view returns(uint256);

    function lock_time_for_max_multiplier() external view returns(uint256);

    // functions for uniNFT vals
    function uni_required_fee() external view returns (uint24);

    function uni_tick_lower() external view returns (int24);

    function uni_tick_upper() external view returns (int24);

    function uni_token0() external view returns (address);

    function uni_token1() external view returns (address);

}
