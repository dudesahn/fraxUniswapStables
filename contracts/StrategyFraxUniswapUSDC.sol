// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../../interfaces/frax/IFrax.sol";
import "../../interfaces/uniswap/IUniNFT.sol";
import "../../interfaces/uniswap/IUni.sol";
import "../../interfaces/uniswap/IUniV3Pool.sol";
import "../../interfaces/curve/ICurve.sol";

import "../../libraries/UnsafeMath.sol";
import "../../libraries/FixedPoint96.sol";
import "../../libraries/FullMath.sol";
import "../../libraries/LowGasSafeMath.sol";
import "../../libraries/SafeCast.sol";
import "../../libraries/SqrtPriceMath.sol";
import "../../libraries/TickMath.sol";
import "../../libraries/LiquidityAmounts.sol";

interface IName {
    function name() external view returns (string memory);
}

contract StrategyFraxUniswapUSDC is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;

    /* ========== STATE VARIABLES ========== */

    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    uint256 public percentKeep;
    uint256 public fraxTimelockSet;
    address public refer;
    address public treasury;
    address public oldStrategy;

    // these are variables specific to our want-FRAX pair
    uint256 public tokenId;
    address internal constant fraxLock =
        0xF22471AC2156B489CC4a59092c56713F813ff53e;
    address internal constant uniV3Pool =
        0x97e7d56A0408570bA1a7852De36350f7713906ec;

    // set up our constants
    IERC20 internal constant frax =
        IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IERC20 internal constant fxs =
        IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address internal constant unirouter =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant uniNFT =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant curve =
        0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;

    // these are our decimals
    uint256 internal constant decFrax = 18;
    uint256 internal constant conversionFactor = 1e12; // used to convert frax to USDC

    // check for cloning
    bool internal isOriginal = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _vault) public BaseStrategy(_vault) {
        _initializeStrat();
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // initializetime
    function _initializeStrat() internal {
        require(tokenId == 0);

        refer = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        treasury = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        fraxTimelockSet = 86400;
        tokenId = 1;

        want.safeApprove(curve, type(uint256).max);
        frax.safeApprove(curve, type(uint256).max);
        want.safeApprove(uniNFT, type(uint256).max);
        frax.safeApprove(uniNFT, type(uint256).max);
        fxs.safeApprove(unirouter, type(uint256).max);
        IERC721(uniNFT).setApprovalForAll(governance(), true);
        IERC721(uniNFT).setApprovalForAll(strategist, true);
        IERC721(uniNFT).setApprovalForAll(fraxLock, true);
    }

    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) external {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat();
    }

    function cloneFraxUni(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper
    ) external returns (address newStrategy) {
        require(isOriginal);

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

        StrategyFraxUniswapUSDC(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper
        );

        emit Cloned(newStrategy);
    }

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return "StrategyFraxUniswapUSDC";
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // returns balance of frax
    function balanceOfFrax() public view returns (uint256) {
        uint256 fraxTrue = frax.balanceOf(address(this));

        // USDC only has 6 decimals so we must convert frax to its base
        return fraxTrue.div(conversionFactor);
    }

    // returns balance of NFT - cannot calculate on-chain so this is a running value
    function balanceOfNFT() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniV3Pool(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);

        uint256 fraxRebase = amount0.div(conversionFactor);

        return fraxRebase.add(amount1);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}

    // returns sum of all assets, realized and unrealized
    // assume frax == want in value to avoid oracle failures
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
        uint256 totalStableBalance = balanceOfWant().add(balanceOfFrax());
        uint256 debt = vault.strategies(address(this)).totalDebt;

        uint256 currentValue = estimatedTotalAssets();

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

        uint256 balanceOfWantAfter = balanceOfWant();
        uint256 balanceOfFraxAfter = balanceOfFrax();
        uint256 totalBalAfter = balanceOfFraxAfter.add(balanceOfWantAfter);

        if (totalBalAfter > totalStableBalance) {
            _profit = totalBalAfter.sub(totalStableBalance);
        }
    }

    // Deposit value to NFT & stake NFT
    function adjustPosition(uint256 _debtOutstanding) internal override {
        //emergency exit is dealt with in prepareReturn
        if (emergencyExit) {
            return;
        }

        nftUnlock();

        uint256 _balanceOfWant = balanceOfWant();

        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        uint256 sumBefore = balanceOfFrax().add(balanceOfWant());

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            // need to swap half want to frax
            uint256 halfWant = _wantAvailable.mul(1e6).div(2e6);
            _curveSwapToFrax(halfWant);
            uint256 fraxBal = IERC20(frax).balanceOf(address(this));
            uint256 wantBal = IERC20(want).balanceOf(address(this));

            uint256 stamp = block.timestamp;
            uint256 deadline = stamp.add(60 * 5);

            IUniNFT.increaseStruct memory setIncrease =
                IUniNFT.increaseStruct(
                    tokenId,
                    fraxBal,
                    wantBal,
                    0,
                    0,
                    deadline
                );

            // time to add val to NFT
            IUniNFT(uniNFT).increaseLiquidity(setIncrease);

            uint256 sumAfter = balanceOfFrax().add(balanceOfWant());

            uint256 addedValue = sumBefore.sub(sumAfter);

            uint256 NFTAdded = balanceOfNFT().add(addedValue);

            IERC721(uniNFT).approve(fraxLock, tokenId);

            IFrax(fraxLock).stakeLocked(tokenId, fraxTimelockSet);
        }
    }

    //v0.4.3 includes logic for emergencyExit
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
        //uint256 curTimestamp = block.timestamp;
        // will need to check if timelocked
        //if(fraxTimelockRemaining > curTimestamp) {
        //    return(0);
        //}

        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 balanceOfFraxBefore = IERC20(frax).balanceOf(address(this));

        nftUnlock();

        uint256 fraction = (_amount).mul(1e18).div(balanceOfNFT());

        (, , , , , , , uint256 initLiquidity, , , , ) =
            IUniNFT(uniNFT).positions(tokenId);

        uint256 liquidityRemove = initLiquidity.mul(fraction).div(1e18);

        uint256 _timestamp = block.timestamp;
        uint256 deadline = _timestamp.add(5 * 60);

        if (emergencyExit) {
            liquidityRemove = initLiquidity;
        }

        uint128 _liquidityRemove = uint128(liquidityRemove);

        IUniNFT.decreaseStruct memory setDecrease =
            IUniNFT.decreaseStruct(tokenId, _liquidityRemove, 0, 0, deadline);

        IUniNFT(uniNFT).decreaseLiquidity(setDecrease);

        // maximum value of uint128
        uint128 MAX_INT = 2**128 - 1;

        IUniNFT.collectStruct memory collectParams =
            IUniNFT.collectStruct(tokenId, address(this), MAX_INT, MAX_INT);

        IUniNFT(uniNFT).collect(collectParams);

        uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        uint256 wantBalance = IERC20(want).balanceOf(address(this));

        _curveSwapToWant(fraxBalance);

        uint256 difference = balanceOfWant().sub(balanceOfWantBefore);

        return difference;
    }

    // transfers all tokens to new strategy
    // would be better to not use this function - to liquidate and transfer that way instead
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

        nftUnlock();

        IERC721(uniNFT).transferFrom(address(this), _newStrategy, tokenId);
    }

    // swaps rewarded tokens for want
    // uses UniV2. May want to include Sushi / UniV3
    function _swap(uint256 _amountIn, address _token) internal {
        address[] memory path = new address[](3);
        path[0] = _token; // token to swap
        path[1] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        path[2] = address(want);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            now
        );
    }

    function _curveSwapToFrax(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(2, 0, _amountIn, 0);
    }

    function _curveSwapToWant(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(0, 2, _amountIn, 0);
    }

    // to use in case the frax:want ratio slips significantly away from 1:1
    function _externalSwapToFrax(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(2, 0, _amountIn, _amountOut);
    }

    function _externalSwapToWant(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(0, 2, _amountIn, _amountOut);
    }

    // claims rewards if unlocked
    function claimReward() internal {
        IFrax(fraxLock).getReward();
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
        uint256 _secs = _days.mul(86400);
        fraxTimelockSet = _secs;
    }

    // sets the id of the minted NFT. Unknowable until mintNFT is called
    function setTokenID(uint256 _id) external onlyGovernance {
        tokenId = _id;
    }

    function convertTo128(uint256 _var) public returns (uint128) {
        return uint128(_var);
    }

    function convertTo256(uint128 _var) public returns (uint256) {
        return uint256(_var);
    }

    function readTimeLock() public view returns (uint256) {
        return fraxTimelockSet;
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

        //div(2) with extra decimal accuracy
        uint256 swapAmt = initBalance.mul(1e5).div(2e5);
        _curveSwapToFrax(swapAmt);
        uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        uint256 wantBalance = IERC20(want).balanceOf(address(this));

        uint256 timestamp = block.timestamp;
        uint256 deadline = timestamp.add(5 * 60);

        // may want to make these settable
        // values for FRAX/USDC
        //uint24 fee = 500;
        //int24 tickLower = (-276380);
        //int24 tickUpper = (-276270);

        IUniNFT.nftStruct memory setNFT =
            IUniNFT.nftStruct(
                address(frax),
                address(want),
                500,
                (-276380),
                (-276270),
                fraxBalance,
                wantBalance,
                0,
                0,
                address(this),
                deadline
            );

        //time to mint the NFT
        (uint256 tokenOut, , , ) = IUniNFT(uniNFT).mint(setNFT);

        tokenId = tokenOut;
    }

    /// turning PositionValue.sol into an internal function
    // positionManager is uniNFT, tokenId, sqrt
    function principal(
        //contraqct uniNFT,
        //tokenId,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (
            ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = IUniNFT(uniNFT).positions(tokenId);

        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    function nftUnlock() internal {
        address nftOwner = IUniNFT(uniNFT).ownerOf(tokenId);
        if (nftOwner == address(fraxLock)) {
            IFrax(fraxLock).withdrawLocked(tokenId);
        }
    }

    // below for 0.4.3 upgrade
    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // weth
        path[1] = address(want);

        uint256[] memory amounts =
            IUni(unirouter).getAmountsOut(_amtInWei, path);

        return amounts[amounts.length - 1];
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        (_amountFreed, ) = liquidatePosition(420_69);
    }
}
