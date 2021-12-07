// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IPoolTogether {
    function depositTo(
        address,
        uint256,
        address,
        address
    ) external;

    function withdrawInstantlyFrom(
        address,
        uint256,
        address,
        uint256
    ) external;

    function calculateEarlyExitFee(
        address,
        address,
        uint256
    ) external returns(uint256);
}
