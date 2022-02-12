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
import "../../interfaces/uniswap/IUniV3.sol";
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
    uint256 public constant DENOMINATOR = 10000;
    uint256 public keepFXS;
    uint256 public fraxTimelockSet;
    address public refer;
    address public voter;
    address public oldStrategy;

    // these are variables specific to our want-FRAX pair
    uint256 public tokenId;
    address internal constant fraxLock =
        0x3EF26504dbc8Dd7B7aa3E97Bc9f3813a9FC0B4B0;
    address internal constant uniV3Pool =
        0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;

    // set up our constants
    IERC20 internal constant frax =
        IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IERC20 internal constant fxs =
        IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    address internal constant unirouter =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant uniNFT =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    ICurveFi internal constant curve =
        ICurveFi(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);

    // these are our decimals
    uint256 internal constant decFrax = 18;
    uint256 internal constant conversionFactor = 1e12; // used to convert frax to USDC

    bool public reLockProfits; // true if we choose to re-lock profits following each harvest and automatically start another epoch
    bool public checkTrueHoldings; // bool to calculate amount left in
    uint256 public liquidateAllSlippage; // in bips, how much slippage we allow between our optimistic assets and pessimistic. 50 = 0.5% slippage.
    uint256 public normalWithdrawalSlippage; // in bips, how much slippage we allow for normal withdrawals. how much are we willing to lose converting FRAX -> USDC?
    uint24 public uniStableFee; // this is equal to 0.05%, can change this later if a different path becomes more optimal

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
        voter = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        fraxTimelockSet = 86400;
        tokenId = 1;
        reLockProfits = true;
        liquidateAllSlippage = 50;

        want.approve(address(curve), type(uint256).max);
        frax.approve(address(curve), type(uint256).max);
        want.approve(uniNFT, type(uint256).max);
        frax.approve(uniNFT, type(uint256).max);
        fxs.approve(unirouter, type(uint256).max);
        IERC721(uniNFT).setApprovalForAll(governance(), true);
        IERC721(uniNFT).setApprovalForAll(strategist, true);
        IERC721(uniNFT).setApprovalForAll(fraxLock, true);

        // set our uniswap pool fees
        uniStableFee = 500;
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

    // returns additional USDC we get if we swap our FRAX on Curve
    function valueOfFrax() public view returns (uint256) {
        uint256 fraxTrue = frax.balanceOf(address(this));

        // see how much USDC we would get for our FRAX on curve
        uint256 usdcCurveOut = curve.get_dy_underlying(0, 2, fraxTrue);

        return usdcCurveOut;
    }

    function nftIsLocked() public view returns (bool) {
        uint256 lockedAmount = IFrax(fraxLock).lockedLiquidityOf(address(this));
        if (lockedAmount > 0) {
            return true;
        } else {
            return false;
        }
    }

    // returns balance of our UniV3 LP, assuming 1 FRAX = 1 want
    function balanceOfNFToptimistic() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniV3(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);

        uint256 fraxRebase = amount0.div(conversionFactor);

        return fraxRebase.add(amount1);
    }

    // returns balance of our UniV3 LP, swapping all FRAX to want using Curve
    function balanceOfNFTpessimistic() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniV3(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);

        uint256 usdcCurveOut = curve.get_dy_underlying(0, 2, amount0);

        return usdcCurveOut.add(amount1);
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

    // assume pessimistic value; the only place this is directly used is when liquidating the whole strategy in vault.report()
    function estimatedTotalAssets() public view override returns (uint256) {
        return
            balanceOfWant().add(valueOfFrax()).add(balanceOfNFTpessimistic());
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
        // in normal situations we can simply use our loose tokens as profit
        uint256 beforeStableBalance = balanceOfWant().add(valueOfFrax());

        // claim our rewards. this will give us FXS (emissions), FRAX, and USDC (fees)
        claimReward();

        // send some FXS to our voter for boosted emissions
        uint256 fxsBalance = fxs.balanceOf(address(this));
        if (fxsBalance > 0) {
            uint256 tokensToSend = fxsBalance.mul(keepFXS).div(DENOMINATOR);
            if (tokensToSend > 0) {
                fxs.transfer(voter, tokensToSend);
            }
            uint256 tokensRemain = fxs.balanceOf(address(this));
            _swapFXS(tokensRemain);
        }

        // check how much we have after claiming our rewards
        uint256 wantBal = balanceOfWant();

        // slightly pessimistic profits since we convert our FRAX to USDC before counting it
        uint256 afterStableBalance = valueOfFrax().add(wantBal);
        _profit = afterStableBalance.sub(beforeStableBalance);
        _debtPayment = _debtOutstanding;

        // we need to free up all of our profit as USDC, so will need more since some is in FRAX currently
        uint256 toFree = _debtPayment.add(_profit);

        if (toFree > wantBal) {
            toFree = toFree.sub(wantBal);

            _withdrawSome(toFree);

            wantBal = want.balanceOf(address(this));
            _debtPayment = Math.min(_debtOutstanding, wantBal);
            _profit = wantBal.sub(_debtPayment);

            if (wantBal < _debtPayment) {
                _loss = _debtOutstanding.sub(wantBal);
            }
        }

        // use this to check our profit/loss if we suspect the pool is imbalanced in one way or the other
        if (checkTrueHoldings) {
            uint256 assets = estimatedTotalAssets();
            uint256 debt = vault.strategies(address(this)).totalDebt;
            // if assets are greater than debt, things are working great!
            if (assets > debt) {
                _profit = assets.sub(debt);
                // we need to prove to the vault that we have enough want to cover our profit and debt payment
                if (wantBal < _profit.add(_debtPayment)) {
                    uint256 amountToFree =
                        _profit.add(_debtPayment).sub(wantBal);
                    _withdrawSome(amountToFree);
                }
            }
            // Losses should never happen unless FRAX depegs, but if it does, let's record it accurately.
            else {
                _loss = debt.sub(assets);
                _profit = 0;
            }
        } else {
            // we shouldn't be harvesting normally if our pool is rekt
            require(
                balanceOfNFTpessimistic() >
                    balanceOfNFToptimistic()
                        .mul(DENOMINATOR.sub(liquidateAllSlippage))
                        .div(DENOMINATOR),
                "check if pool rekt"
            );
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

        uint256 sumBefore = valueOfFrax().add(balanceOfWant());

        // only re-lock our profits if our bool is true
        if (reLockProfits) {
            // Invest the rest of the want
            uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
            if (_wantAvailable > 0) {
                // need to swap half want to frax, but use the proper conversion
                (uint160 sqrtPriceX96, , , , , , ) = IUniV3(uniV3Pool).slot0();
                (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);
                uint256 ratio =
                    amount0.div(conversionFactor).mul(1e6).div(amount1);
                uint256 fraxNeeded =
                    _wantAvailable.mul(ratio).div(ratio.add(1e6));

                _curveSwapToFrax(fraxNeeded);
                uint256 fraxBal = frax.balanceOf(address(this));
                uint256 wantBal = want.balanceOf(address(this));

                IUniNFT.increaseStruct memory setIncrease =
                    IUniNFT.increaseStruct(
                        tokenId,
                        fraxBal,
                        wantBal,
                        0,
                        0,
                        block.timestamp
                    );

                // add more liquidity to our NFT
                IUniNFT(uniNFT).increaseLiquidity(setIncrease);
            }

            // re-lock our NFT for more rewards
            IFrax(fraxLock).stakeLocked(tokenId, fraxTimelockSet);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // check if we have enough free funds to cover the withdrawal
        uint256 balanceOfWant = balanceOfWant();
        if (balanceOfWant < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(balanceOfWant));
            // reload balance of want after withdrawing funds
            balanceOfWant = balanceOfWant();
        }
        // check again if we have enough balance available to cover the liquidation
        if (balanceOfWant >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            // we took a loss :(
            _liquidatedAmount = balanceOfWant;
            _loss = _amountNeeded.sub(balanceOfWant);
        }
    }

    // withdraw some want from the vaults, probably don't want to allow users to initiate this
    function _withdrawSome(uint256 _amount) internal returns (uint256) {
        //uint256 curTimestamp = block.timestamp;
        // will need to check if timelocked
        //if(fraxTimelockRemaining > curTimestamp) {
        //    return(0);
        //}

        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 balanceOfFraxBefore = IERC20(frax).balanceOf(address(this));

        // check how much we would get out by just selling our FRAX profit, add this here first

        require(harvestNow); // this way we only pull from the NFT during a harvest or manually
        nftUnlock();

        // use our "real" amount for this so we over-estimate
        uint256 fraction = (_amount).mul(1e18).div(balanceOfNFTpessimistic());

        (, , , , , , , uint256 initLiquidity, , , , ) =
            IUniNFT(uniNFT).positions(tokenId);

        uint256 liquidityRemove = initLiquidity.mul(fraction).div(1e18);

        if (emergencyExit) {
            liquidityRemove = initLiquidity;
        }

        uint128 _liquidityRemove = uint128(liquidityRemove);

        IUniNFT.decreaseStruct memory setDecrease =
            IUniNFT.decreaseStruct(
                tokenId,
                _liquidityRemove,
                0,
                0,
                block.timestamp
            );

        IUniNFT(uniNFT).decreaseLiquidity(setDecrease);

        IUniNFT.collectStruct memory collectParams =
            IUniNFT.collectStruct(
                tokenId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );

        IUniNFT(uniNFT).collect(collectParams);

        uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        uint256 wantBalance = IERC20(want).balanceOf(address(this));

        _curveSwapToWant(fraxBalance);

        uint256 difference = balanceOfWant().sub(balanceOfWantBefore);

        return difference;
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        frax.transfer(_newStrategy, frax.balanceOf(address(this)));
        fxs.transfer(_newStrategy, fxs.balanceOf(address(this)));

        // unlock and send our NFT to our new strategy
        nftUnlock();
        IERC721(uniNFT).approve(_newStrategy, tokenId);
        IERC721(uniNFT).transferFrom(address(this), _newStrategy, tokenId);
    }

    // Swap FXS -> WETH on UniV2, then WETH -> want on UniV3
    function _swapFXS(uint256 _amountIn) internal {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address[] memory path = new address[](2);
        path[0] = address(fxs);
        path[1] = weth;

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 _wethBalance = IERC20(weth).balanceOf(address(this));
        IUniV3(uniswapv3).exactInput(
            IUniV3.ExactInputParams(
                abi.encodePacked(
                    address(weth),
                    uint24(uniStableFee),
                    address(want)
                ),
                address(this),
                block.timestamp,
                _wethBalance,
                uint256(1)
            )
        );
    }

    function _curveSwapToFrax(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(2, 0, _amountIn, 0);
    }

    function _curveSwapToWant(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(0, 2, _amountIn, 0);
    }

    // to use in case the frax:want ratio slips significantly away from 1:1
    function _externalSwapToFrax(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(2, 0, _amountIn, _amountOut);
    }

    function _externalSwapToWant(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(0, 2, _amountIn, _amountOut);
    }

    // claims rewards if unlocked
    function claimReward() internal {
        IFrax(fraxLock).getReward();
    }

    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }

    // the amount of FXS to keep
    function setKeepFXS(uint256 _keepFXS) external onlyGovernance {
        keepFXS = _keepFXS;
    }

    // where FXS goes
    function setVoter(address _voter) external onlyGovernance {
        voter = _voter;
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
    function mintNFT() external {
        uint256 initBalance = IERC20(want).balanceOf(address(this));

        if (initBalance == 0) {
            return;
        }

        //div(2) with extra decimal accuracy
        uint256 swapAmt = initBalance.mul(1e5).div(2e5);
        _curveSwapToFrax(swapAmt);
        uint256 fraxBalance = frax.balanceOf(address(this));
        uint256 wantBalance = want.balanceOf(address(this));

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
                block.timestamp
            );

        //time to mint the NFT
        (uint256 tokenOut, , , ) = IUniNFT(uniNFT).mint(setNFT);

        tokenId = tokenOut;

        // approve our NFT on our frax lock contract
        IERC721(uniNFT).approve(fraxLock, tokenId);
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

    function nftUnlock() public onlyEmergencyAuthorized {
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
        return _amtInWei;
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        (_amountFreed, ) = liquidatePosition(420_69);
    }

    ///@notice This allows us to decide to automatically re-lock our NFT with profits after a harvest
    function setReLockProfits(bool _reLockProfits)
        external
        onlyEmergencyAuthorized
    {
        reLockProfits = _reLockProfits;
    }
}
