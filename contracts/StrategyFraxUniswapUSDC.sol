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
    uint256 public fraxTimelockSet;
    uint256 public fraxTimelockRemaining;
    uint256 public token_id;
    uint256 public balanceOfNFT;
    address public frax;
    address public fxs;
    address public unirouter;
    address public uniNFT;
    address public fraxLock;
    address public refer;
    address public treasury;
    address public curve;

    constructor(
        address _vault,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve
    ) public BaseStrategyInitializable(_vault) {
        // Constructor should initialize local variables
        _initializeThis(
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve
        );
    }

    // initializetime
    function _initializeThis(
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve
    ) internal {
        require(
            address(wantPool) == address(0),
            "StrategyPoolTogether already initialized"
        );

        frax = _frax;
        fxs = _fxs;
        unirouter = _unirouter;
        uniNFT = _uniNFT;
        fraxLock = _fraxLock;
        curve = _curve;

        percentKeep = 1000;
        refer = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        treasury = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        fraxTimelockSet = 86400;
        fraxTimelockRemaining = 1;
        token_id = 1;
        balanceOfNFT = 1;

        IERC20(want).safeApprove(curve, uint256(-1));
        IERC20(frax).safeApprove(curve, uint256(-1));
        IERC20(want).safeApprove(uniNFT, uint256(-1));
        IERC20(frax).safeApprove(uniNFT, uint256(-1));
        IERC20(fxs).safeApprove(unirouter, uint256(-1));
        IERC720(uniNFT).safeApprove(fraxLock, uint256(-1));
    }

    //TODO: This
    function _initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve
    ) internal {
        // Parent initialize contains the double initialize check
        super._initialize(_vault, _strategist, _rewards, _keeper);
        _initializeThis(
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve
        );
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve
    ) external {
        _initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve
        );
    }

    function clonePoolTogether(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve
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
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve
        );
    }

    function name() external view override returns (string memory) {
        return
            string(
                abi.encodePacked("FRAX_Uniswap ", IName(address(want)).name())
            );
    }

    //TODO: This
    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {
        address[] memory protected = new address[](3);
        // (aka want) is already protected by default
        protected[0] = frax;
        protected[1] = fxs;
        protected[2] = uniNFT;

        return protected;
    }


    // returns sum of all assets, realized and unrealized
    // assume frax == want in value to avoid oracle failures
    // balanceOfNFT is a running system variable to keep track of things
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(balanceOfFrax()).add(balanceOfNFT());
    }

    // claim profit and swap for want
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
        //if (currentValue > debt) {
        //    uint256 _amount = currentValue.sub(debt);
        //   liquidatePosition(_amount);
        //}

        claimReward();

        uint256 _tokensAvailable = IERC20(fxs).balanceOf(address(this));
        if (_tokensAvailable > 0) {
            uint256 _tokensToGov =
                _tokensAvailable.mul(percentKeep).div(_denominator);
            if (_tokensToGov > 0) {
                IERC20(fxs).safeTransfer(treasury, _tokensToGov);
            }
            uint256 _tokensRemain = IERC20(fxs).balanceOf(address(this));
            _swap(_tokensRemain, address(fxs));
        }

        //uint256 _bonusAvailable = IERC20(bonus).balanceOf(address(this));
        //if (_bonusAvailable > 0) {
        //    _swap(_bonusAvailable, address(bonus));
        //}

        uint256 balanceOfWantAfter = balanceOfWant();

        if (balanceOfWantAfter > balanceOfWantBefore) {
            _profit = balanceOfWantAfter.sub(balanceOfWantBefore);
        }
    }

    // Deposit value to NFT & stake NFT
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

        uint256 sumBefore = balanceOfFrax.add(balanceOfWant);

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            // need to swap half want to frax
            uint256 halfWant = _wantAvailable.mul(1e6).div(2e6);
            _curveSwap(halfWant, want, frax);
            uint256 fraxBal = IERC20(frax).balanceOf(address(this));
            uint256 wantBal = IERC20(want).balanceOf(address(this));

            // time to add val to NFT
            IUniNFT(uniNFT).increaseLiquidity(
                token_id,
                fraxBal,
                wantBal)
                returns (uint256 liquidity, uint256 depositedFrax, uint256 depositedWant);

            uint256 sumAfter = balanceOfFrax.add(balanceOfWant);

            uint256 addedValue = sumBefore.sub(sumAfter);

            uint256 NFTAdded = balanceOfNFT().add(addedValue);
            updateNFTValue(NFTAdded);

            IFrax(fraxLock).stakeLocked(token_id, fraxTimelockSet);

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
        //will need to check if timelocked
        if(fraxTimelockRemaining > 0) {
            return(0);
        }

        uint256 balanceOfWantBefore = balanceOfWant();

        IFrax(fraxLock).withdrawLocked(
            token_id
        );

        uint256 currentValue = estimateTotalAssets();
        uint256 fraction = currentValue.div(_amount);

        uint128[] _positions = IUniNFT(uniNFT).positions(token_id);
        uint128 initLiquidity = _positions.liquidity;

        uint128 liquidityRemove = initLiquidity.div(fraction);

        uint256 timestamp = block.timestamp();
        uint256 deadline = timestamp.add(5*60);

        // should be set at some value for slippage.  Currently at 1 for testing
        //TODO: see above
        // maybe _amount.mul(1e5).div(2e5).mul(9e4).div(1e5)
        uint256 amount0Min = 1;
        uint256 amount1Min = 1;

        IUniNFT(uniNFT).decreaseLiquidity(
            token_id,
            liquidityRemove,
            amount0Min,
            amount1Min,
            deadline
        );

        uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        uint256 wantBalance = IERC20(want).balanceOf(address(this));

        _curveSwap(fraxBalance, frax, want);
        uint256 wantBalanceNew = IERC20(want).balanceOf(address(this));

        uint256 difference = balanceOfWant().sub(balanceOfWantBefore);

        uint256 NFTDifference = (balanceOfNFT).sub(difference);

        updateNFTValue(NFTDifference);

        return balanceOfWant().sub(balanceOfWantBefore);
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        // want is transferred by the base contract's migrate function
        IERC20(frax).transfer(
            _newStrategy,
            IERC20(frax).balanceOf(address(this))
        );
        IERC20(fxs).transfer(
            _newStrategy,
            IERC20(fxs).balanceOf(address(this))
        );
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // returns balance of frax
    function balanceOfFrax() public view returns (uint256) {
        uint256 fraxTrue = IERC20(frax).balanceOf(address(this));
        uint256 wantDecimals = IERC20(want).decimals();
        uint256 fraxDecimals = IERC20(frax).decimals();
        // decimals may be different
        uint256 ratio = (fraxDecimals).div(wantDecimals);
        // because 10 ** 1 == mul(10), so needs to be 10 ** 0 for mul(1)
        uint256 ratiosub = ratio.sub(1);
        return fraxTrue.div(10 ** ratiosub);
    }

    // returns balance of NFT - cannot calculate on-chain so this is a running value
    function balanceOfNFT() public view returns (uint256) {
        return balanceOfNFT;
    }

    // swaps rewarded tokens for want
    // uses UniV2. May want to include Sushi / UniV3
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

    function _curveSwap(uint256 _amountIn, address _tokenIn, address _tokenOut) internal {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        ICurve(curve).exchange(_tokenIn, _tokenOut, _amountIn, _amountOut);
    }

    // to use in case the frax:want ratio slips significantly away from 1:1
    function _externalSwap(uint256 _amountIn, address _tokenIn, address _tokenOut) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        ICurve(curve).exchange(_tokenIn, _tokenOut, _amountIn, _amountOut);
    }

    // claims rewards if unlocked
    function claimReward() internal {
        IFrax(fraxLock).claim(address(this));
    }

    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }

    // the amount of FXS to keep
    function setKeep(uint256 _percentKeep) external onlyGovernance {
        percentKeep = _percentKeep;
    }

    // where FXS goes
    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }

    // sets time locked as a multiple of days. Would recommend values between 1-7.
    // initial value is set to 1
    function setFraxTimelock(uint256 _days) external onlyGovernance {
        uint256 secs = _days.mul(86400);
        fraxTimelockSet = _secs;
    }

    // sets the id of the minted NFT. Unknowable until mintNFT is called
    function setTokenID(uint256 _id) external onlyGovernance {
        token_id = _id;
    }

    function updateNFTValue(uint256 _value) internal {
        balanceOfNFT = _value;
}

    // This function is needed to initialize the entire strategy.
    // want needs to be airdropped to the strategy in a nominal amount. Say ~1k USD worth.
    // This will run through the process of minting the NFT on UniV3
    // that NFT will be the NFT we use for this strat. We will add/sub balances, but never burn the NFT
    // it will always have dust, accordingly
    function mintNFT() external onlyGovernance {
        uint256 initBalance = IERC20(want).balanceOf(address(this));

        if (initBalance == 0) {
            return;
        }

        updateNFTValue(initBalance);

        //div(2) with extra decimal accuracy
        uint256 swapAmt = initBalance.mul(1e5)div(2e5);
        _curveSwap(swapAmt, want);
        uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        uint256 wantBalance = IERC20(want).balanceOf(address(this));
        //min amt of 2%
        uint256 fraxMin = fraxBalance.mul(9800).div(10000);
        uint256 wantMin = wantBalance.mul(9800).div(10000);
        uint256 timestamp = block.timestamp();
        uint256 deadline = timestamp.add(5*60);

        // may want to make these settable
        // values for FRAX/USDC
        uint24 fee = 500;
        int24 tickLower = (-276380);
        int24 tickUpper = (-276270);

        //time to mint the NFT
        IUniNFT(uniNFT).mint(
            frax,
            want,
            fee,
            tickLower,
            tickUpper,
            fraxBalance,
            wantBalance,
            0,
            0,
            address(this),
            deadline);
    }
}
