// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import {SafeERC20, SafeMath, IERC20, Address} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

interface IVoting{
    function vote_for_gauge_weights(address, uint256) external;
}

interface IVoteEscrow {
    function create_lock(uint256, uint256) external;
    function increase_unlock_time(uint256) external;
    function increase_amount(uint256) external;
    function withdraw() external;
}

contract FraxVoterProxy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    
    address public constant fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address public constant gaugeController = 0x44ade9AA409B0C29463fF7fcf07c9d3c939166ce;
    address public constant escrow = 0xc8418aF6358FFddA74e09Ca9CC3Fe03Ca6aDC5b0;
        
    address public governance;
    address public strategyProxy;

    constructor() public {
        governance = msg.sender;
    }
    
    function name() external pure returns (string memory) {
        return "FraxVoterProxy";
    }
    
    function createLock(uint256 _value, uint256 _unlockTime) external {
        require(msg.sender == strategyProxy || msg.sender == governance, "!authorized");
        IERC20(fxs).safeApprove(escrow, 0);
        IERC20(fxs).safeApprove(escrow, _value);
        IVoteEscrow(escrow).create_lock(_value, _unlockTime);
    }
    
    function increaseAmount(uint256 _value) external {
        require(msg.sender == strategyProxy || msg.sender == governance, "!authorized");
        IERC20(fxs).safeApprove(escrow, 0);
        IERC20(fxs).safeApprove(escrow, _value);
        IVoteEscrow(escrow).increase_amount(_value);
    }
    
    function increaseUnlockTime(uint256 _value) external {
        require(msg.sender == strategyProxy || msg.sender == governance, "!authorized");
        IVoteEscrow(escrow).increase_unlock_time(_value);
    }
    
    function release() external {
        require(msg.sender == strategyProxy || msg.sender == governance, "!authorized");
        IVoteEscrow(escrow).withdraw();
    }

    function vote(address _gauge, uint256 _amount) external {
        require(msg.sender == governance, "!authorized");
        IVoting(gaugeController).vote_for_gauge_weights(_gauge, _amount);
    }
    
    function setGovernance(address _governance) external {
        require(msg.sender == governance, "!governance");
        governance = _governance;
    }
    
    function setStrategyProxy(address _strategyProxy) external {
        require(msg.sender == governance, "!governance");
        strategyProxy = _strategyProxy;
    }
    
    function execute(address to, uint value, bytes calldata data) external returns (bool, bytes memory) {
        require(msg.sender == strategyProxy || msg.sender == governance, "!governance");
        (bool success, bytes memory result) = to.call.value(value)(data);
        
        return (success, result);
    }
}
