// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IPoolFaucet {
    function userStates(address)
        external
        view
        returns (uint128 lastExchangeRateMantissa, uint128 balance);

    function deposit(uint256) external;

    function claim(address) external;
}
