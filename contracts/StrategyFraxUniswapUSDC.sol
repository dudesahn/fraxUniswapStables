// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import {
    BaseStrategy,
    StrategyParams
} from "@yearnvaults/contracts/BaseStrategy.sol";

import "../interfaces/frax/IFrax.sol";
import "../interfaces/uniswap/IUniNFT.sol";
import "../interfaces/uniswap/IUni.sol";
import "../interfaces/uniswap/IUniV3.sol";
import "../interfaces/curve/ICurve.sol";

import "../libraries/UnsafeMath.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/FullMath.sol";
import "../libraries/LowGasSafeMath.sol";
import "../libraries/SafeCast.sol";
import "../libraries/SqrtPriceMath.sol";
import "../libraries/TickMath.sol";
import "../libraries/LiquidityAmounts.sol";

interface IName {
    function name() external view returns (string memory);
}

contract StrategyFraxUniswapUSDC is BaseStrategy {
    using Address for address;
    using SafeMath for uint128;

    /* ========== STATE VARIABLES ========== */

    // variables for determining how much governance token to hold for voting rights
    uint256 internal constant DENOMINATOR = 10000;
    uint256 public keepFXS;
    uint256 public fraxTimelockSet;
    address public refer;
    address public voter;

    // these are variables specific to our want-FRAX pair
    uint256 public nftId;
    address internal constant fraxLock =
        0x3EF26504dbc8Dd7B7aa3E97Bc9f3813a9FC0B4B0;
    address internal constant uniV3Pool =
        0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;

    // tokens
    IERC20 internal constant frax =
        IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    IERC20 internal constant fxs =
        IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);
    IERC20 internal constant weth =
        IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // uniswap v3 NFT address
    address internal constant uniNFT =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // routers/pools for swaps
    address internal constant unirouter =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ICurveFi internal constant curve =
        ICurveFi(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);
    address internal constant uniswapv3 =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;

    // setters
    bool public reLockProfits; // true if we choose to re-lock profits following each harvest and automatically start another epoch
    bool public checkTrueHoldings; // bool to reset our profit/loss based on the amount we have if we withdrew everything at once
    uint256 public slippageMax; // in bips, how much slippage we allow between our optimistic assets and pessimistic. 50 = 0.5% slippage. Remember curve swap costs 0.04%.
    uint24 public uniStableFee; // this is equal to 0.05%, can change this later if a different path becomes more optimal

    // do we need to add a maxInvest parameter here?

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
        require(nftId == 0);

        refer = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        voter = 0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde;
        fraxTimelockSet = 86400;
        nftId = 1;
        reLockProfits = true;
        slippageMax = 50;

        want.approve(address(curve), type(uint256).max);
        frax.approve(address(curve), type(uint256).max);
        want.approve(uniNFT, type(uint256).max);
        frax.approve(uniNFT, type(uint256).max);
        fxs.approve(unirouter, type(uint256).max);
        weth.approve(uniswapv3, type(uint256).max);
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

    // returns balance of frax token
    function fraxBalance() public view returns (uint256) {
        return frax.balanceOf(address(this));
    }

    /// @notice Returns additional USDC we get if we swap our FRAX on Curve
    function valueOfFrax() public view returns (uint256) {
        // see how much USDC we would get for our FRAX on curve
        uint256 usdcCurveOut = curve.get_dy_underlying(0, 2, fraxBalance());

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

        uint256 fraxRebase = amount0.div(1e12); // div by 1e12 to convert frax to usdc

        return fraxRebase.add(amount1);
    }

    // returns balance of our UniV3 LP, swapping all FRAX to want using Curve
    function balanceOfNFTpessimistic() public view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniV3(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);

        uint256 usdcCurveOut = curve.get_dy_underlying(0, 2, amount0);

        return usdcCurveOut.add(amount1);
    }

    // assume pessimistic value; the only place this is directly used is when liquidating the whole strategy in vault.report()
    function estimatedTotalAssets() public view override returns (uint256) {
        return
            balanceOfWant().add(valueOfFrax()).add(balanceOfNFTpessimistic());
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

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
        IFrax(fraxLock).getReward();

        // send some FXS to our voter for boosted emissions
        uint256 fxsBalance = fxs.balanceOf(address(this));
        if (fxsBalance > 0) {
            uint256 tokensToSend = fxsBalance.mul(keepFXS).div(DENOMINATOR);
            if (tokensToSend > 0) {
                fxs.transfer(voter, tokensToSend);
            }
            uint256 tokensRemain = fxs.balanceOf(address(this));
            if (tokensRemain > 0) {
                _swapFXS(tokensRemain);
            }
        }

        // check how much we have after claiming our rewards
        uint256 wantBal = balanceOfWant();

        // slightly pessimistic profits since we convert our FRAX to USDC before counting it
        uint256 afterStableBalance = valueOfFrax().add(wantBal);
        _profit = afterStableBalance.sub(beforeStableBalance);
        _debtPayment = _debtOutstanding;

        // we need to free up all of our profit as USDC, so will need more since some is in FRAX currently
        uint256 toFree = _debtPayment.add(_profit);

        // this will pretty much always be true unless we stop getting FRAX profits
        if (toFree > wantBal) {
            toFree = toFree.sub(wantBal);

            _withdrawSome(toFree);

            // check what we got back out
            wantBal = balanceOfWant();
            _debtPayment = Math.min(_debtOutstanding, wantBal);

            // make sure we pay our debt first, then count profit. if not enough to pay debt, then only loss.
            if (wantBal > _debtPayment) {
                _profit = wantBal.sub(_debtPayment);
            } else {
                _profit = 0;
                _loss = _debtPayment.sub(wantBal);
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
            // check our peg to make sure everything is okay
            checkFraxPeg();
        }
    }

    // Swap FXS -> WETH on UniV2, then WETH -> want on UniV3
    function _swapFXS(uint256 _amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = address(fxs);
        path[1] = address(weth);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 _wethBalance = weth.balanceOf(address(this));
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
        // use our slippage tolerance
        uint256 _amountOut =
            _amountIn.mul(DENOMINATOR.sub(slippageMax)).div(DENOMINATOR);

        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(2, 0, _amountIn, _amountOut);
    }

    function _curveSwapToWant(uint256 _amountIn) internal {
        // use our slippage tolerance
        uint256 _amountOut =
            _amountIn.mul(DENOMINATOR.sub(slippageMax)).div(DENOMINATOR);

        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(0, 2, _amountIn, _amountOut);
    }

    // Deposit value to NFT & stake NFT
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit) {
            return;
        }

        // unlock our NFT so we can withdraw or deposit more as needed
        nftUnlock();

        // only re-lock our profits if our bool is true
        if (reLockProfits) {
            // Invest the rest of the want
            uint256 wantbal = balanceOfWant();
            if (wantbal > 0) {
                // need to swap half want to frax, but use the proper conversion
                // based on the current exchange rate in the LP
                (uint160 sqrtPriceX96, , , , , , ) = IUniV3(uniV3Pool).slot0();
                (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);
                uint256 ratio = amount0.div(1e12).mul(1e6).div(amount1); // div by 1e12 to convert frax to usdc
                uint256 fraxNeeded = wantbal.mul(ratio).div(ratio.add(1e6));

                // swap our USDC to FRAX on Curve
                _curveSwapToFrax(fraxNeeded);

                // add more liquidity to our NFT
                IUniNFT.increaseStruct memory setIncrease =
                    IUniNFT.increaseStruct(
                        nftId,
                        fraxBalance(),
                        balanceOfWant(),
                        0,
                        0,
                        block.timestamp
                    );
                IUniNFT(uniNFT).increaseLiquidity(setIncrease);
            }

            // re-lock our NFT for more rewards
            IFrax(fraxLock).stakeLocked(nftId, fraxTimelockSet);
        }
    }

    // this is only called externally by user withdrawals
    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        // check if we have enough free funds to cover the withdrawal
        uint256 wantBal = balanceOfWant();
        if (wantBal < _amountNeeded) {
            // We need to withdraw to get back more want
            _withdrawSome(_amountNeeded.sub(wantBal));
            // reload balance of want after withdrawing funds
            wantBal = balanceOfWant();
        }
        // check again if we have enough balance available to cover the liquidation
        if (wantBal >= _amountNeeded) {
            _liquidatedAmount = _amountNeeded;
        } else {
            // we took a loss :(
            _liquidatedAmount = wantBal;
            _loss = _amountNeeded.sub(wantBal);
        }
    }

    function liquidateAllPositions()
        internal
        override
        returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        (_amountFreed, ) = liquidatePosition(420_69);
    }

    // before we go crazy withdrawing or harvesting, make sure our FRAX peg is healthy
    function checkFraxPeg() internal {
        uint256 virtualBalance = balanceOfNFToptimistic();
        uint256 realBalance = balanceOfNFTpessimistic();
        if (virtualBalance > realBalance) {
            require(
                (slippageMax >
                    (virtualBalance.sub(realBalance)).mul(DENOMINATOR).div(
                        realBalance
                    )),
                "too much FRAX"
            );
        } else {
            require(
                (slippageMax >
                    (realBalance.sub(virtualBalance)).mul(DENOMINATOR).div(
                        virtualBalance
                    )),
                "too much USDC"
            );
        }
    }

    // withdraw some want from the vaults, probably don't want to allow users to initiate this
    // MAKE SURE WE ASSESS LOSSES AND HAVE SLIPPAGE PROTECTION IF NEEDED ******
    function _withdrawSome(uint256 _amount) internal {
        // check if we have enough free USDC and FRAX to cover the withdrawal
        uint256 balanceOfWantBefore = balanceOfWant();
        uint256 valueOfFraxBefore = valueOfFrax();
        uint256 _fraxBalance = fraxBalance();

        if (_fraxBalance > 0) {
            _curveSwapToWant(_fraxBalance);
        }
        uint256 newBalanceOfWant = balanceOfWant();

        if (newBalanceOfWant >= _amount) {
            return;
        }

        // make sure our pool is healthy enough for a normal withdrawal
        checkFraxPeg();

        // if we don't have enough free funds, unlock our NFT
        nftUnlock();

        // update our amount with the amount we have loose
        _amount = _amount.sub(newBalanceOfWant);

        // use our "ideal" amount for this so we under-estimate and assess losses on each debt reduction
        // calculate the share of the NFT that our amount needed should be
        uint256 fraction = (_amount).mul(1e18).div(balanceOfNFToptimistic());

        (, , , , , , , uint256 initLiquidity, , , , ) =
            IUniNFT(uniNFT).positions(nftId);

        uint256 liquidityRemove = initLiquidity.mul(fraction).div(1e18);

        // remove it all if we're in emergency exit
        if (emergencyExit) {
            liquidityRemove = initLiquidity;
        }

        // convert between uint128 and uin256, fun!
        uint128 _liquidityRemove = uint128(liquidityRemove);

        // remove our specified liquidity amount
        IUniNFT.decreaseStruct memory setDecrease =
            IUniNFT.decreaseStruct(
                nftId,
                _liquidityRemove,
                0,
                0,
                block.timestamp
            );

        IUniNFT(uniNFT).decreaseLiquidity(setDecrease);

        IUniNFT.collectStruct memory collectParams =
            IUniNFT.collectStruct(
                nftId,
                address(this),
                type(uint128).max,
                type(uint128).max
            );

        IUniNFT(uniNFT).collect(collectParams);

        // swap our FRAX balance to USDC
        _curveSwapToWant(fraxBalance());
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        frax.transfer(_newStrategy, fraxBalance());
        fxs.transfer(_newStrategy, fxs.balanceOf(address(this)));

        // unlock and send our NFT to our new strategy
        nftUnlock();
        IERC721(uniNFT).approve(_newStrategy, nftId);
        IERC721(uniNFT).transferFrom(address(this), _newStrategy, nftId);
    }

    /* ========== SETTERS ========== */

    // sets time locked as a multiple of days. Would recommend values between 1-7.
    // initial value is set to 1
    // sets the id of the minted NFT. Unknowable until mintNFT is called
    function setGovParams(
        address _refer,
        address _voter,
        uint256 _keepFXS,
        uint256 _nftId,
        uint256 _timelockInSeconds
    ) external onlyGovernance {
        refer = _refer;
        voter = _voter;
        keepFXS = _keepFXS;
        nftId = _nftId;
        fraxTimelockSet = _timelockInSeconds;
    }

    ///@notice This allows us to decide to automatically re-lock our NFT with profits after a harvest
    function setReLockProfits(bool _reLockProfits)
        external
        onlyEmergencyAuthorized
    {
        reLockProfits = _reLockProfits;
    }

    // This function is needed to initialize the entire strategy.
    // want needs to be airdropped to the strategy in a nominal amount. Say ~1k USD worth.
    // This will run through the process of minting the NFT on UniV3
    // that NFT will be the NFT we use for this strat. We will add/sub balances, but never burn the NFT
    // it will always have dust, accordingly
    function mintNFT() external onlyEmergencyAuthorized {
        require(
            (balanceOfWant() > 0 &&
                IUniNFT(uniNFT).balanceOf(address(this)) == 0),
            "can't mint"
        );

        // swap half to frax, don't care about using real pricing since it's a small amount
        // and is only meant to seed the LP
        uint256 swapAmt = balanceOfWant().mul(1e18).div(2e18);
        _curveSwapToFrax(swapAmt);

        IUniNFT.nftStruct memory setNFT =
            IUniNFT.nftStruct(
                address(frax),
                address(want),
                500,
                (-276380),
                (-276270),
                fraxBalance(),
                balanceOfWant(),
                0,
                0,
                address(this),
                block.timestamp
            );

        //time to mint the NFT
        (uint256 tokenOut, , , ) = IUniNFT(uniNFT).mint(setNFT);

        nftId = tokenOut;

        // approve our NFT on our frax lock contract
        IERC721(uniNFT).approve(fraxLock, nftId);
    }

    /// turning PositionValue.sol into an internal function
    // positionManager is uniNFT, nftId, sqrt
    function principal(
        //contraqct uniNFT,
        //nftId,
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

        ) = IUniNFT(uniNFT).positions(nftId);

        return
            LiquidityAmounts.getAmountsForLiquidity(
                sqrtRatioX96,
                TickMath.getSqrtRatioAtTick(tickLower),
                TickMath.getSqrtRatioAtTick(tickUpper),
                liquidity
            );
    }

    /// @notice This is here so our contract can receive ERC721 tokens.
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure virtual returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function nftUnlock() public onlyEmergencyAuthorized {
        address nftOwner = IUniNFT(uniNFT).ownerOf(nftId);
        if (nftOwner == address(fraxLock)) {
            IFrax(fraxLock).withdrawLocked(nftId);
        }
    }

    /* ========== FUNCTION GRAVEYARD ========== */

    function ethToWant(uint256 _amtInWei)
        public
        view
        override
        returns (uint256)
    {}

    function protectedTokens()
        internal
        view
        override
        returns (address[] memory)
    {}
}
