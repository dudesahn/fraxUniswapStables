// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {
    BaseStrategyInitializable
} from "../../contracts/BaseStrategyEdited.sol";

import "../../interfaces/poolTogether/IPoolTogether.sol";
import "../../interfaces/poolTogether/IPoolFaucet.sol";
import "../../interfaces/uniswap/Uni.sol";

interface IName {
    function name() external view returns (string memory);
}

contract StrategyPoolTogether is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    uint256 public percentKeep;
    address public wantPool;
    address public poolToken;
    address public unirouter;
    address public bonus;
    address public faucet;
    address public ticket;
    address public refer;
    address public treasury;

    constructor(
        address _vault,
        address _wantPool,
        address _poolToken,
        address _unirouter,
        address _bonus,
        address _faucet,
        address _ticket
    ) public BaseStrategyInitializable(_vault) {
        // Constructor should initialize local variables
        _initializeThis(
            _wantPool,
            _poolToken,
            _unirouter,
            _bonus,
            _faucet,
            _ticket
        );
    }

    function _initializeThis(
        address _wantPool,
        address _poolToken,
        address _unirouter,
        address _bonus,
        address _faucet,
        address _ticket
    ) internal {
        require(
            address(wantPool) == address(0),
            "StrategyPoolTogether already initialized"
        );

        wantPool = _wantPool;
        poolToken = _poolToken;
        unirouter = _unirouter;
        bonus = _bonus;
        faucet = _faucet;
        ticket = _ticket;

        percentKeep = 1000;
        refer = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        treasury = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);

        IERC20(want).safeApprove(wantPool, uint256(-1));
        IERC20(poolToken).safeApprove(unirouter, uint256(-1));
        IERC20(bonus).safeApprove(unirouter, uint256(-1));
    }

    function _initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _wantPool,
        address _poolToken,
        address _unirouter,
        address _bonus,
        address _faucet,
        address _ticket
    ) internal {
        // Parent initialize contains the double initialize check
        super._initialize(_vault, _strategist, _rewards, _keeper);
        _initializeThis(
            _wantPool,
            _poolToken,
            _unirouter,
            _bonus,
            _faucet,
            _ticket
        );
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _wantPool,
        address _poolToken,
        address _unirouter,
        address _bonus,
        address _faucet,
        address _ticket
    ) external {
        _initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _wantPool,
            _poolToken,
            _unirouter,
            _bonus,
            _faucet,
            _ticket
        );
    }

    function clonePoolTogether(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _wantPool,
        address _poolToken,
        address _unirouter,
        address _bonus,
        address _faucet,
        address _ticket
    ) external returns (address newStrategy) {
        // Copied from https://github.com/optionality/clone-factory/blob/master/contracts/CloneFactory.sol
        bytes20 addressBytes = bytes20(address(this));

        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            newStrategy := create(0, clone_code, 0x37)
        }

        StrategyPoolTogether(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _wantPool,
            _poolToken,
            _unirouter,
            _bonus,
            _faucet,
            _ticket
        );
    }

    function name() external view override returns (string memory) {
        return
            string(
                abi.encodePacked("PoolTogether ", IName(address(want)).name())
            );
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        // (aka want) is already protected by default
        protected[0] = ticket;
        protected[1] = poolToken;
        protected[2] = bonus;

        return protected;
    }

    // returns sum of all assets, realized and unrealized
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfPool());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (
            uint256 _profit,
            uint256 _loss,
            uint256 _debtPayment
        )
    {
        // We might need to return want to the vault
        if (_debtOutstanding > 0) {
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        // harvest() will track profit by estimated total assets compared to debt.
        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 debt = vault.strategies(address(this)).totalDebt;

        uint256 currentValue = estimatedTotalAssets();

        // If we win we will have more value than debt!
        // Let's convert tickets to want to calculate profit.
        if (currentValue > debt) {
            uint256 _amount = currentValue.sub(debt);
            liquidatePosition(_amount);
        }

        claimReward();

        uint256 _tokensAvailable = IERC20(poolToken).balanceOf(address(this));
        if (_tokensAvailable > 0) {
            uint256 _tokensToGov =
                _tokensAvailable.mul(percentKeep).div(_denominator);
            if (_tokensToGov > 0) {
                IERC20(poolToken).safeTransfer(treasury, _tokensToGov);
            }
            uint256 _tokensRemain = IERC20(poolToken).balanceOf(address(this));
            _swap(_tokensRemain, address(poolToken));
        }

        uint256 _bonusAvailable = IERC20(bonus).balanceOf(address(this));
        if (_bonusAvailable > 0) {
            _swap(_bonusAvailable, address(bonus));
        }

        uint256 balanceOfWantAfter = balanceOfWant();

        if (balanceOfWantAfter > balanceOfWantBefore) {
            _profit = balanceOfWantAfter.sub(balanceOfWantBefore);
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        uint256 _balanceOfWant = balanceOfWant();

        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            IPoolTogether(wantPool).depositTo(
                address(this),
                _wantAvailable,
                ticket,
                refer
            );
        }
    }

    //v0.3.0 - liquidatePosition is emergency exit. Supplants exitPosition
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {

        uint256 _balanceOfWant = balanceOfWant();
        if (_balanceOfWant < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(_balanceOfWant));
            // reload balance of want after side effect
            _balanceOfWant = balanceOfWant();
        }

        if (_balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            _liquidatedAmount = _balanceOfWant;
            _loss = _amountNeeded.sub(_balanceOfWant);
        }
    }

    // withdraw some want from the vaults
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        uint256 balanceOfWantBefore = balanceOfWant();

        uint256 _fee = IPoolTogether(wantPool).calculateEarlyExitFee(
            address(this),
            ticket,
            _amount
        );

        IPoolTogether(wantPool).withdrawInstantlyFrom(
            address(this),
            _amount,
            ticket,
            _fee.add(1)
        );

        return balanceOfWant().sub(balanceOfWantBefore);
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        IERC20(poolToken).transfer(
            _newStrategy,
            IERC20(poolToken).balanceOf(address(this))
        );
        IERC20(bonus).transfer(
            _newStrategy,
            IERC20(bonus).balanceOf(address(this))
        );
        IERC20(ticket).transfer(
            _newStrategy,
            IERC20(ticket).balanceOf(address(this))
        );
    }

    // returns value of total pool tickets
    function balanceOfPool() public view returns (uint256) {
        return IERC20(ticket).balanceOf(address(this));
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // swaps rewarded tokens for want
    function _swap(uint256 _amountIn, address _token) internal {
        address[] memory path = new address[](3);
        path[0] = _token; // token to swap
        path[1] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        path[2] = address(want);

        Uni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            now
        );
    }

    // claims POOL from faucet
    function claimReward() internal {
        IPoolFaucet(faucet).claim(address(this));
    }

    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }

    function setKeep(uint256 _percentKeep) external onlyGovernance {
        percentKeep = _percentKeep;
    }

    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }
}
