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

interface IBaseFee {
    function isCurrentBaseFeeAcceptable() external view returns (bool);
}

contract StrategyFraxUniswapFRAXUSDC is BaseStrategy {
    using Address for address;
    using SafeMath for uint128;

    /* ========== STATE VARIABLES ========== */

    // variables for determining how much governance token to hold for voting rights
    uint256 internal constant DENOMINATOR = 10000;
    uint256 public keepFXS;
    uint256 public fraxTimelockSet;
    address public refer;
    address public voter;
    uint256 public nftUnlockTime = type(uint256).max; // timestamp that we can withdraw our staked NFT. init at max so we must mint first.

    // these are variables specific to our want-FRAX pair
    uint256 public nftId;
    address internal constant fraxLock =
        0x3EF26504dbc8Dd7B7aa3E97Bc9f3813a9FC0B4B0;
    address internal constant uniV3Pool =
        0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52;

    // tokens
    IERC20 internal constant usdc =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant fxs =
        IERC20(0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0);

    // uniswap v3 NFT address
    address internal constant uniNFT =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    // routers/pools for swaps
    address internal constant unirouter =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    ICurveFi internal constant curve =
        ICurveFi(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B);

    // setters
    bool public reLockProfits; // true if we choose to re-lock profits following each harvest and automatically start another epoch
    bool public checkTrueHoldings; // bool to reset our profit/loss based on the amount we have if we withdrew everything at once
    uint256 public slippageMax; // in bips, how much slippage we allow between our optimistic assets and pessimistic. 50 = 0.5% slippage. Remember curve swap costs 0.04%.
    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

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

        refer = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
        voter = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;
        fraxTimelockSet = 86400;
        nftId = 1;
        reLockProfits = true;
        slippageMax = 50;

        want.approve(address(curve), type(uint256).max);
        usdc.approve(address(curve), type(uint256).max);
        want.approve(uniNFT, type(uint256).max);
        usdc.approve(uniNFT, type(uint256).max);
        fxs.approve(unirouter, type(uint256).max);
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

        StrategyFraxUniswapFRAXUSDC(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper
        );

        emit Cloned(newStrategy);
    }

    /* ========== VIEWS ========== */

    function name() external view override returns (string memory) {
        return "StrategyFraxUniswapFRAXUSDC";
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // returns balance of usdc
    function balanceOfUsdc() public view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    /// @notice Returns additional FRAX we get if we swap our USDC on Curve
    function valueOfUsdc() public view returns (uint256) {
        // see how much FRAX we would get for our USDC on curve
        uint256 currentUsdc = balanceOfUsdc();
        if (currentUsdc > 0) {
            return curve.get_dy_underlying(2, 0, currentUsdc);
        } else {
            return 0;
        }
    }

    // returns balance of our UniV3 LP, assuming 1 USDC = 1 want, factoring curve swap fee
    function balanceOfNFToptimistic() public view returns (uint256) {
        (uint256 fraxBalance, uint256 usdcBalance) = principal();
        uint256 usdcRebase = usdcBalance.mul(1e12).mul(9996).div(DENOMINATOR); // mul by 1e12 to convert usdc to frax, assume 1:1 swap on curve with fees
        return usdcRebase.add(fraxBalance);
    }

    /// @notice Returns balance of our UniV3 LP, swapping all USDC to want (FRAX) using Curve.
    function balanceOfNFTpessimistic() public view returns (uint256) {
        (uint256 fraxBalance, uint256 usdcBalance) = principal();
        // only bother adding/converting if we have anything, otherwise just return fraxBalance
        if (usdcBalance > 0) {
            uint256 fraxCurveOut = curve.get_dy_underlying(2, 0, usdcBalance);
            return fraxCurveOut.add(fraxBalance);
        } else {
            return fraxBalance;
        }
    }

    // assume pessimistic value; used directly in emergencyExit
    function estimatedTotalAssets() public view override returns (uint256) {
        return
            balanceOfWant().add(valueOfUsdc()).add(balanceOfNFTpessimistic());
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
        // do this so we don't count dust leftover from LPing as profit
        uint256 beforeStableBalance = balanceOfWant().add(valueOfUsdc());

        // claim our rewards. this will give us FXS (emissions), FRAX and USDC (fees)
        // however, only claim if we have an NFT staked
        if (IFrax(fraxLock).lockedLiquidityOf(address(this)) > 0) {
            IFrax(fraxLock).getReward();
        }

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

        // convert all of our USDC profits to FRAX for ease of accounting
        uint256 usdcToSwap = balanceOfUsdc();
        if (usdcToSwap > 0) {
            _curveSwapToFrax(usdcToSwap);
        }

        // check how much we have after claiming our rewards
        uint256 wantBal = balanceOfWant();

        // slightly pessimistic profits since we convert our USDC to FRAX before counting it
        uint256 afterStableBalance = valueOfUsdc().add(wantBal);
        _profit = afterStableBalance.sub(beforeStableBalance);
        _debtPayment = _debtOutstanding;

        // use this to check our profit/loss if we suspect the pool is imbalanced in one way or the other, or if we get donations
        if (checkTrueHoldings) {
            uint256 assets = estimatedTotalAssets();
            uint256 debt = vault.strategies(address(this)).totalDebt;
            // if assets are greater than debt, things are working great!
            if (assets > debt) {
                _profit = assets.sub(debt);
            }
            // Losses should never happen unless FRAX depegs, but if it does, let's record it accurately.
            else {
                _loss = debt.sub(assets);
                _profit = 0;
            }
            // reset since we've adjusted for our true holdings
            checkTrueHoldings = false;
        } else {
            // check our peg to make sure everything is okay
            checkFraxPeg();
        }

        // we need to free up all of our profit as FRAX
        uint256 toFree = _debtPayment.add(_profit);

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
                _loss = _debtOutstanding.sub(_debtPayment);
            }
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    // Swap FXS -> FRAX on UniV2
    function _swapFXS(uint256 _amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = address(fxs);
        path[1] = address(want);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function _curveSwapToUsdc(uint256 _amountIn) internal {
        // use our slippage tolerance, convert between FRAX (1e18) -> USDC (1e6)
        uint256 _amountOut =
            _amountIn.mul(DENOMINATOR.sub(slippageMax)).div(DENOMINATOR).div(
                1e12
            );

        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(0, 2, _amountIn, _amountOut);
    }

    function _curveSwapToFrax(uint256 _amountIn) internal {
        // use our slippage tolerance, convert between USDC (1e6) -> FRAX (1e18)
        uint256 _amountOut =
            _amountIn.mul(DENOMINATOR.sub(slippageMax)).div(DENOMINATOR).mul(
                1e12
            );

        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(2, 0, _amountIn, _amountOut);
    }

    // Deposit value to NFT & stake NFT
    function adjustPosition(uint256 _debtOutstanding) internal override {
        if (emergencyExit || nftId == 1) {
            return;
        }

        // NFT has to be unlocked before we can do anything with it
        require(block.timestamp > nftUnlockTime, "Wait for NFT to unlock!");

        // unstake our NFT so we can withdraw or deposit more as needed
        _nftUnstake();

        // only re-lock our profits if our bool is true
        if (reLockProfits) {
            // Invest the rest of the want
            uint256 wantBal = balanceOfWant();
            if (wantBal > 0) {
                // need to swap half want to usdc, but use the proper conversion
                // based on the current exchange rate in the LP
                (uint256 fraxBal, uint256 usdcBal) = principal();
                uint256 usdcPercentage = 5e17; // default our percentage to 50%, 100% is 1e18
                if (usdcBal > 0 || fraxBal > 0) {
                    usdcPercentage = (usdcBal.mul(1e12).mul(1e18)).div(
                        fraxBal.add(usdcBal.mul(1e12))
                    ); // multiply usdc by 1e12 to convert to frax, 1e18
                }
                uint256 usdcNeeded = wantBal.mul(usdcPercentage).div(1e18); // this will be 1e18, which matches our valueOfUsdc

                // we should only have FRAX holdings after our harvest
                // doing this will leave us with a little FRAX leftover each time
                if (usdcNeeded > 0) {
                    _curveSwapToUsdc(usdcNeeded);
                }

                // add more liquidity to our NFT
                IUniNFT.increaseStruct memory setIncrease =
                    IUniNFT.increaseStruct(
                        nftId,
                        balanceOfWant(),
                        balanceOfUsdc(),
                        0,
                        0,
                        block.timestamp
                    );
                IUniNFT(uniNFT).increaseLiquidity(setIncrease);
            }

            // re-lock our NFT
            _nftStake();
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
            // make sure our pool is healthy enough for a normal withdrawal
            checkFraxPeg();

            // We need to withdraw to get back more want
            uint256 toFree = _amountNeeded.sub(wantBal);
            _withdrawSome(toFree);

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
        // amount here doesn't really matter, since in withdrawSome we always withdraw everything
        // if emergencyExit is true, so just use more than we would have loose in the strategy
        (_amountFreed, ) = liquidatePosition(estimatedTotalAssets());
    }

    // before we go crazy withdrawing or harvesting, make sure our FRAX peg is healthy
    function checkFraxPeg() internal {
        uint256 virtualBalance = balanceOfNFToptimistic();
        uint256 realBalance = balanceOfNFTpessimistic();

        // don't bother checking if either of our vars are 0 since we will revert
        if (realBalance == 0 || virtualBalance == 0) {
            return;
        }

        if (virtualBalance > realBalance) {
            require(
                (slippageMax >
                    (virtualBalance.sub(realBalance)).mul(DENOMINATOR).div(
                        realBalance
                    )),
                "too much USDC"
            );
        } else {
            require(
                (slippageMax >
                    (realBalance.sub(virtualBalance)).mul(DENOMINATOR).div(
                        virtualBalance
                    )),
                "too much FRAX"
            );
        }
    }

    // withdraw some want from the vaults, probably don't want to allow users to initiate this
    function _withdrawSome(uint256 _amount) internal {
        if (nftId == 1) {
            return;
        }

        // NFT has to be unlocked before we can do anything with it
        require(block.timestamp > nftUnlockTime, "Wait for NFT to unlock!");

        // if we don't have enough free funds, unstake our NFT
        _nftUnstake();

        // use our "ideal" amount for this so we under-estimate and assess losses on each debt reduction
        // calculate the share of the NFT that our amount needed should be
        uint256 debt = vault.strategies(address(this)).totalDebt;
        uint256 optimisticBal = Math.max(balanceOfNFToptimistic(), debt);
        uint256 fraction;
        if (optimisticBal > 0) {
            // don't want to divide by 0
            fraction = (_amount).mul(1e18).div(optimisticBal); // multiply by 1e18 for precision reasons
        } else {
            return;
        }

        (, , , , , , , uint128 liquidity, , , , ) =
            IUniNFT(uniNFT).positions(nftId);

        // convert between uint128 and uint256, fun!
        uint256 _liquidity = uint256(liquidity);

        uint256 liquidityToRemove = _liquidity.mul(fraction).div(1e18); // divide by 1e18 since that's how big our fraction is

        // remove it all if we're in emergency exit
        if (fraction >= 1e18 || emergencyExit) {
            liquidityToRemove = _liquidity;
        }

        // convert between uint128 and uint256, fun!
        uint128 _liquidityToRemove = uint128(liquidityToRemove);

        // remove our specified liquidity amount
        IUniNFT.decreaseStruct memory setDecrease =
            IUniNFT.decreaseStruct(
                nftId,
                _liquidityToRemove,
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

        // swap any USDC we have to FRAX
        uint256 currentUsdc = balanceOfUsdc();
        if (currentUsdc > 0) {
            _curveSwapToFrax(currentUsdc);
        }
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        usdc.transfer(_newStrategy, balanceOfUsdc());
        fxs.transfer(_newStrategy, fxs.balanceOf(address(this)));

        // NFT has to be unlocked before we can do anything with it
        require(block.timestamp > nftUnlockTime, "Wait for NFT to unlock!");

        // unstake and send our NFT to our new strategy, don't try migrating if we don't have an NFT
        if (nftId != 1) {
            _nftUnstake();
            IERC721(uniNFT).transferFrom(address(this), _newStrategy, nftId);
            // approvals automatically revoke when we migrate. and set our NFTid back to 1
            _setGovParams(address(0), address(0), 0, 1, 0, 0);
        }
    }

    /* ========== SETTERS ========== */

    // sets the id of the minted NFT. Unknowable until mintNFT is called
    function _setGovParams(
        address _refer,
        address _voter,
        uint256 _keepFXS,
        uint256 _nftId,
        uint256 _timelockInSeconds,
        uint256 _currentUnlockTime
    ) internal {
        refer = _refer;
        voter = _voter;
        keepFXS = _keepFXS;
        nftId = _nftId;
        fraxTimelockSet = _timelockInSeconds;
        nftUnlockTime = _currentUnlockTime;
    }

    function setGovParams(
        address _refer,
        address _voter,
        uint256 _keepFXS,
        uint256 _nftId,
        uint256 _timelockInSeconds,
        uint256 _currentUnlockTime
    ) external onlyGovernance {
        _setGovParams(
            _refer,
            _voter,
            _keepFXS,
            _nftId,
            _timelockInSeconds,
            _currentUnlockTime
        );
    }

    ///@notice This allows us to decide to automatically re-lock our NFT with profits after a harvest
    function setManagerParams(
        bool _reLockProfits,
        bool _checkTrueHoldings,
        uint256 _slippageMax
    ) external onlyVaultManagers {
        require(_slippageMax < 10001, "10000 = 100% slippage");
        reLockProfits = _reLockProfits;
        checkTrueHoldings = _checkTrueHoldings;
        slippageMax = _slippageMax;
    }

    ///@notice This allows us to manually harvest with our keeper as needed
    function setForceHarvestTriggerOnce(bool _forceHarvestTriggerOnce)
        external
        onlyAuthorized
    {
        forceHarvestTriggerOnce = _forceHarvestTriggerOnce;
    }

    /* ========== NFT HELPERS ========== */

    // This function is needed to initialize the entire strategy.
    // want needs to be airdropped to the strategy in a nominal amount. Say ~1k USD worth.
    // This will run through the process of minting the NFT on UniV3
    // that NFT will be the NFT we use for this strat. We will add/sub balances, but never burn the NFT
    // it will always have dust, accordingly
    function mintNFT() external onlyVaultManagers {
        require(
            (balanceOfWant() > 0 &&
                IUniNFT(uniNFT).balanceOf(address(this)) == 0),
            "can't mint"
        );

        // swap some to usdc, don't care about using real pricing since it's a small amount
        // and is only meant to seed the LP. prefer extra want left over for accounting reasons.
        uint256 swapAmt = balanceOfWant().mul(40).div(100);
        _curveSwapToUsdc(swapAmt);

        IUniNFT.nftStruct memory setNFT =
            IUniNFT.nftStruct(
                address(want),
                address(usdc),
                500,
                (-276380),
                (-276270),
                balanceOfWant(),
                balanceOfUsdc(),
                0,
                0,
                address(this),
                block.timestamp
            );

        //time to mint the NFT
        (uint256 tokenOut, , , ) = IUniNFT(uniNFT).mint(setNFT);

        nftId = tokenOut;

        // reset our unlock time, we have our NFT but it's not locked
        nftUnlockTime = 0;
    }

    /// turning PositionValue.sol into an internal function
    // positionManager is uniNFT, nftId, sqrt
    function principal()
        public
        view
        returns (
            //contraqct uniNFT,
            //nftId,
            // uint160 sqrtRatioX96
            uint256 fraxHoldings,
            uint256 usdcHoldings
        )
    {
        if (nftId == 1) {
            // this is our "placeholder" ID, means we need to mint our NFT still
            return (0, 0);
        } else {
            // check where our NFT is, hopefully staked or in our strategy 😬
            address nftOwner = IUniNFT(uniNFT).ownerOf(nftId);
            if (nftOwner == address(this) || nftOwner == fraxLock) {
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
                (uint160 sqrtRatioX96, , , , , , ) = IUniV3(uniV3Pool).slot0();

                return
                    LiquidityAmounts.getAmountsForLiquidity(
                        sqrtRatioX96,
                        TickMath.getSqrtRatioAtTick(tickLower),
                        TickMath.getSqrtRatioAtTick(tickUpper),
                        liquidity
                    );
            } else {
                // we don't have our NFT, that's not good
                return (0, 0);
            }
        }
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

    function _nftUnstake() internal {
        address nftOwner = IUniNFT(uniNFT).ownerOf(nftId);
        if (nftOwner == fraxLock) {
            IFrax(fraxLock).withdrawLocked(nftId);
        }
    }

    function nftUnstake() external onlyVaultManagers {
        _nftUnstake();
    }

    function _nftStake() internal {
        IERC721(uniNFT).approve(fraxLock, nftId);
        IFrax(fraxLock).stakeLocked(nftId, fraxTimelockSet);

        // update our new unlock time
        nftUnlockTime = block.timestamp.add(fraxTimelockSet);
    }

    function nftStake() external onlyVaultManagers {
        _nftStake();
    }

    /// @notice Include this so gov can sweep our NFT if needed.
    function sweepNFT(address _destination) external onlyGovernance {
        IERC721(uniNFT).safeTransferFrom(address(this), _destination, nftId);
    }

    /* ========== KEEP3RS ========== */

    // use this to determine when to harvest
    function harvestTrigger(uint256 callCostinEth)
        public
        view
        override
        returns (bool)
    {
        // Should not trigger if strategy is not active (no assets and no debtRatio). This means we don't need to adjust keeper job.
        if (!isActive()) {
            return false;
        }

        if (!isBaseFeeAcceptable()) {
            return false;
        }

        // harvest if our NFT can be unlocked
        if (block.timestamp > nftUnlockTime) {
            return true;
        }

        // trigger if we want to manually harvest
        if (forceHarvestTriggerOnce) {
            return true;
        }

        // otherwise, we don't harvest
        return false;
    }

    // check if the current baseFee is below our external target
    function isBaseFeeAcceptable() internal view returns (bool) {
        return
            IBaseFee(0xb5e1CAcB567d98faaDB60a1fD4820720141f064F)
                .isCurrentBaseFeeAcceptable();
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
