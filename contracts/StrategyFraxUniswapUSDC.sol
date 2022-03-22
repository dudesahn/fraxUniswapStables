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
    uint256 public nftUnlockTime = type(uint256).max; // timestamp that we can withdraw our staked NFT. init at max so we must mint first.

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

    // setters
    bool public reLockProfits; // true if we choose to re-lock profits following each harvest and automatically start another epoch
    bool public checkTrueHoldings; // bool to reset our profit/loss based on the amount we have if we withdrew everything at once
    uint256 public slippageMax; // in bips, how much slippage we allow between our optimistic assets and pessimistic. 50 = 0.5% slippage. Remember curve swap costs 0.04%.
    bool internal forceHarvestTriggerOnce; // only set this to true externally when we want to trigger our keepers to harvest for us

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
        uint256 currentFrax = fraxBalance();
        if (currentFrax > 0) {
            return curve.get_dy_underlying(0, 2, currentFrax);
        } else {
            return 0;
        }
    }

    // returns balance of our UniV3 LP, assuming 1 FRAX = 1 want
    function balanceOfNFToptimistic() public view returns (uint256) {
        (uint256 amount0, uint256 amount1) = principal();
        uint256 fraxRebase = amount0.div(1e12); // div by 1e12 to convert frax to usdc
        return fraxRebase.add(amount1);
    }

    // returns balance of our UniV3 LP, swapping all FRAX to want using Curve
    function balanceOfNFTpessimistic() public view returns (uint256) {
        (uint256 amount0, uint256 amount1) = principal();
        // only bother adding/converting if we have anything, otherwise just return amount1
        if (amount0 > 0) {
            uint256 usdcCurveOut = curve.get_dy_underlying(0, 2, amount0);
            return usdcCurveOut.add(amount1);
        } else {
            return amount1;
        }
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
        // do this so we don't count dust leftover from LPing as profit
        uint256 beforeStableBalance = balanceOfWant().add(valueOfFrax());

        // claim our rewards. this will give us FXS (emissions), FRAX, and USDC (fees)
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

        // convert all of our FRAX profits to USDC for ease of accounting
        uint256 fraxToSwap = fraxBalance();
        if (fraxToSwap > 0) {
            _curveSwapToWant(fraxToSwap);
        }

        // check how much we have after claiming our rewards
        uint256 wantBal = balanceOfWant();

        // slightly pessimistic profits since we convert our FRAX to USDC before counting it
        uint256 afterStableBalance = valueOfFrax().add(wantBal);
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
        } else {
            // check our peg to make sure everything is okay
            checkFraxPeg();
        }

        // we need to free up all of our profit as USDC
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
                _loss = _debtOutstanding.sub(_debtPayment);
            }
        }

        // we're done harvesting, so reset our trigger if we used it
        forceHarvestTriggerOnce = false;
    }

    // Swap FXS -> WETH on UniV2, then WETH -> want on UniV3
    function _swapFXS(uint256 _amountIn) internal {
        address[] memory path = new address[](2);
        path[0] = address(fxs);
        path[1] = address(frax);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
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

    function _curveSwapToWant(uint256 _amountIn) internal {
        // use our slippage tolerance, convert between FRAX (1e18) -> USDC (1e6)
        uint256 _amountOut =
            _amountIn.mul(DENOMINATOR.sub(slippageMax)).div(DENOMINATOR).div(
                1e12
            );

        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        curve.exchange_underlying(0, 2, _amountIn, _amountOut);
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
                // need to swap half want to frax, but use the proper conversion
                // based on the current exchange rate in the LP
                (uint256 fraxBal, uint256 usdcBal) = principal();
                uint256 fraxPercentage = 5e17; // default our percentage to 50%, 100% is 1e18
                if (usdcBal > 0 || fraxBal > 0) {
                    fraxPercentage = fraxBal.mul(1e18).div(
                        (usdcBal.mul(1e12)).add(fraxBal)
                    ); // multiply usdc by 1e12 to convert to frax, 1e18
                }
                uint256 fraxNeeded = wantBal.mul(fraxPercentage).div(1e18); // this will be 1e6, which matches our valueOfFrax

                // we should only have USDC holdings after our harvest
                // doing this will leave us with a little USDC leftover each time
                if (fraxNeeded > 0) {
                    _curveSwapToFrax(fraxNeeded);
                }

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
            uint256 lockTime = fraxTimelockSet;
            IERC721(uniNFT).approve(fraxLock, nftId);
            IFrax(fraxLock).stakeLocked(nftId, lockTime);

            // update our new unlock time
            nftUnlockTime = block.timestamp.add(lockTime);
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
        uint256 toLiquidate = estimatedTotalAssets();
        (_amountFreed, ) = liquidatePosition(toLiquidate);
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
    function _withdrawSome(uint256 _amount) internal {
        // check if we have enough free FRAX to cover the extra needed
        if (valueOfFrax() > _amount) {
            _curveSwapToWant(fraxBalance());
            return;
        }

        // make sure our pool is healthy enough for a normal withdrawal
        checkFraxPeg();

        // NFT has to be unlocked before we can do anything with it
        require(block.timestamp > nftUnlockTime, "Wait for NFT to unlock!");

        // if we don't have enough free funds, unstake our NFT
        _nftUnstake();

        // use our "ideal" amount for this so we under-estimate and assess losses on each debt reduction
        // calculate the share of the NFT that our amount needed should be
        uint256 optimisticBal = balanceOfNFToptimistic();
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

        // swap any FRAX we have to USDC
        uint256 currentFrax = fraxBalance();
        if (currentFrax > 0) {
            _curveSwapToWant(currentFrax);
        }
    }

    // transfers all tokens to new strategy
    function prepareMigration(address _newStrategy) internal override {
        frax.transfer(_newStrategy, fraxBalance());
        fxs.transfer(_newStrategy, fxs.balanceOf(address(this)));

        // NFT has to be unlocked before we can do anything with it
        require(block.timestamp > nftUnlockTime, "Wait for NFT to unlock!");

        // unstake and send our NFT to our new strategy
        _nftUnstake();
        if (nftId != 1) {
            // don't try migrating if we don't have an NFT
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
    function setManagerParams(bool _reLockProfits, bool _checkTrueHoldings)
        external
        onlyVaultManagers
    {
        reLockProfits = _reLockProfits;
        checkTrueHoldings = _checkTrueHoldings;
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

        // swap half to frax, don't care about using real pricing since it's a small amount
        // and is only meant to seed the LP
        uint256 swapAmt = balanceOfWant().div(2);
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
