// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import {BaseStrategyInitializable} from "@yearn/contracts/BaseStrategy.sol";

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
//import "..\..\YearnV2-Generic-Lev-Comp-Farm\contracts\Interfaces\Maker\Maker.sol";


// TODO: symbol() is more concise
interface IName {
    function name() external view returns (string memory);
}

/*
    Suggestion: Consolidate the two contracts DAI/USDC to one.
    Use BaseStrategy and factory pattern to clone.
    Example https://github.com/tonkers-kuma/strategy-88mph/blob/ftm-yswaps/contracts/StrategyFactory.sol
*/
contract StrategyFraxUniswapDAI is BaseStrategyInitializable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;


    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    uint256 public percentKeep;
    uint256 public fraxTimelockSet;
    // Stick with camel case
    uint256 public tokenId;
    address public frax;
    address public fxs;
    address public unirouter;
    address public uniNFT;
    address public fraxLock;
    address public refer;
    address public treasury;
    address public curve;
    address public uniV3Pool;
    // TODO: uint8 public curveIndexFrax;
    // TODO: uint8 public curveIndexWant;

    constructor(
        address _vault,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve,
        address _uniV3Pool
    ) public BaseStrategyInitializable(_vault) {
        // Constructor should initialize local variables
        _initializeThis(
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve,
            _uniV3Pool
        );
    }

    // initializetime
    function _initializeThis(
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve,
        address _uniV3Pool
    ) internal {
        require(
            address(frax) == address(0),
            "StrategyFraxUniswap already initialized"
        );

        frax = _frax;
        fxs = _fxs;
        unirouter = _unirouter;
        uniNFT = _uniNFT;
        fraxLock = _fraxLock;
        curve = _curve;
        uniV3Pool = _uniV3Pool;
        // TODO: Add some checks here to make sure lock/nft/vault/pool tokens all match up

        percentKeep = 1000;
        // TODO: These seem to be old? https://gnosis-safe.io/app/eth:0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52/balances
        // ^^ was using the Treasury vault. Can change these to whatever the current address is.
        //Will be used in veFRAX voterproxy in the future, so the best may be SMS.
        refer = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        treasury = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        // TODO: Math.min(fraxLock.lock_time_min(), 86400);
        // ^^ The 86400 is a variable that can be set later on via set function. Would the above be able to be passed via function?
        // if so, easy fix.
        fraxTimelockSet = 86400;
        tokenId = 0;

        // TODO: Iterate through curve pool to find indices of want and frax


        // setting maxVar
        uint256 max256 = 2 ** 256 - 1;
        IERC20(want).safeApprove(curve, max256);
        IERC20(frax).safeApprove(curve, max256);
        IERC20(want).safeApprove(uniNFT, max256);
        IERC20(frax).safeApprove(uniNFT, max256);
        IERC20(fxs).safeApprove(unirouter, max256);
        IERC721(uniNFT).setApprovalForAll(governance(), true);
        IERC721(uniNFT).setApprovalForAll(strategist, true);
        IERC721(uniNFT).setApprovalForAll(fraxLock, true);
    }

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
        address _curve,
        address _univ3Pool
    ) internal {
        // Parent initialize contains the double initialize check
        super._initialize(_vault, _strategist, _rewards, _keeper);
        _initializeThis(
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve,
            _univ3Pool
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
        address _curve,
        address _uniV3Pool
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
            _curve,
            _uniV3Pool
        );
    }

    // TODO: Move this to factory
    function cloneFraxUni(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _frax,
        address _fxs,
        address _unirouter,
        address _uniNFT,
        address _fraxLock,
        address _curve,
        address _uniV3Pool
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

        StrategyFraxUniswapDAI(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _frax,
            _fxs,
            _unirouter,
            _uniNFT,
            _fraxLock,
            _curve,
            _uniV3Pool
        );
    }

    function name() external view override returns (string memory) {
        return
        string(
        // use symbol()
            abi.encodePacked("FRAX_Uniswap ", IName(address(want)).name())
        );
    }


    // Image the new_strategy here receiving the NFT transferred from old_strategy.
    // nft_id at this point is still uninitialized. We also don't want to mint a new one bc we're transferring positions, not starting new one
    // TODO: Set tokenId = received NFT
    // Now, the above line could be easily tempered with by any small brain by sending a random nft to reset the tokenId
    // TODO: Make sure to only receive the nft if it's from old_strategy by require(msg.sender == old_strategy)
    // TODO: Add method setOldStrategy onlyVaultManager to act as a password

    // Responding to above: This is not just for migrations, this is needed for all unlock events
    // the tokenId shouldn't change from normal harvests - so I don't want to have the tokenId changed upon receiving an NFT
    // the old_strategy per above wouldn't work, as we'd also be receiving from the fraxLock contract.
    // As such, I think that the safest course of action is to continue with the manual onlyApproved function call to manually declare tokenID
    // that will be for the migration case, and will be the only time it's used.
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
    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant().add(valueOfFrax()).add(balanceOfNFT());
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
            // uint initializes default at 0. Don't need to set 0 to it
            uint256 _amountFreed = 0;
            (_amountFreed, _loss) = liquidatePosition(_debtOutstanding);
            _debtPayment = Math.min(_amountFreed, _debtOutstanding);
        }

        // harvest() will track profit by estimated total assets compared to debt.
        uint256 totalBalBefore = balanceOfWant().add(valueOfFrax());
        uint256 debt = vault.strategies(address(this)).totalDebt;

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

        uint256 totalBalAfter = valueOfFrax().add(balanceOfWant());

        if (totalBalAfter > totalBalBefore) {
            _profit = totalBalAfter.sub(totalBalBefore);
        }

        if (_profit > _loss) {
            _profit = _profit.sub(_loss);
            _loss = 0;
        } else {
            _loss = _loss.sub(_profit);
            _profit = 0;
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

        // Personal preference: Not necessary. Funds would be better utilized invested rather than sitting idle until next harvest
        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        uint256 sumBefore = valueOfFrax().add(_balanceOfWant);

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            // need to swap half want to frax
            // TODO: Same here, 1e6/2e6 = /2
            uint256 halfWant = _wantAvailable.mul(1e6).div(2e6);
            _curveSwapToFrax(halfWant);
            uint256 fraxBal = IERC20(frax).balanceOf(address(this));
            uint256 wantBal = IERC20(want).balanceOf(address(this));

            uint256 stamp = block.timestamp;
            uint256 deadline = stamp.add(60 * 5);

            IUniNFT.increaseStruct memory setIncrease = IUniNFT.increaseStruct(
                tokenId,
                wantBal,
                fraxBal,
                0,
                0,
                deadline);

            // time to add val to NFT
            IUniNFT(uniNFT).increaseLiquidity(setIncrease);

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
        uint256 valueOfFraxBefore = IERC20(frax).balanceOf(address(this));

        nftUnlock();

        // TODO: I recommend writing more defensive code here to make sure fraction = range[0,1].
        // _amount > balanceOfNFT() will result in unwanted results
        uint256 fraction = (_amount).mul(1e18).div(balanceOfNFT());

        (,,,,,,,uint256 initLiquidity,,,,) = IUniNFT(uniNFT).positions(tokenId);

        uint256 liquidityRemove = initLiquidity.mul(fraction).div(1e18);

        uint256 _timestamp = block.timestamp;
        uint256 deadline = _timestamp.add(5 * 60);

        if (emergencyExit) {
            liquidityRemove = initLiquidity;
        }

        uint128 _liquidityRemove = uint128(liquidityRemove);

        IUniNFT.decreaseStruct memory setDecrease = IUniNFT.decreaseStruct(
            tokenId,
            _liquidityRemove,
            0,
            0,
            deadline);

        IUniNFT(uniNFT).decreaseLiquidity(setDecrease);

        // maximum value of uint128
        // TODO: type(uint128).max
        // ^^ that was breaking my tests for some reason - I might not have the right package installed? So I went the alt route
        // not an underflow method, so it should be fine.
        uint128 MAX_INT = 2 ** 128 - 1;

        IUniNFT.collectStruct memory collectParams = IUniNFT.collectStruct(
            tokenId,
            address(this),
            MAX_INT,
            MAX_INT);

        IUniNFT(uniNFT).collect(collectParams);

        _curveSwapToWant(IERC20(frax).balanceOf(address(this));
        return balanceOfWant().sub(balanceOfWantBefore);
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

        // TODO: Read ERC721Received above for more info
        IERC721(uniNFT).transferFrom(
            address(this),
            _newStrategy,
            tokenId
        );
    }

    // returns balance of want token
    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    // TODO: Optional: Add public function balanceOfFrax() for frax.balanceOf(address(this)) replace use of IERC(token).balanceOf(address(this))
    // TODO: Optional: Add public function balanceOfReward() for fxs.balanceOf(address(this)) replace use of IERC(token).balanceOf(address(this))

    // returns balance of frax, denominated in same dec as want
    // TODO: Rename valueOfFrax. Balance of frax means more frax.balanceOf(address(this))
    function valueOfFrax() public view returns (uint256) //noinspection NoReturn {
        uint256 fraxTrue = IERC20(frax).balanceOf(address(this));
        //hard-coding for testing
        // USDC=Tether=6, frax=dai=18,

        // TODO: Convert in terms of want. Assuming 1:1 stable:frax
         uint decFrax = ERC20(frax).decimals()
         uint decWant = ERC20(want).decimals()
            if(decFrax > decWant){
                return fraxTrue.div(10 ** (decFrax.sub(decWant)));
            }else{
                return fraxTrue.mul(10 ** (decWant.sub(decFrax)));
            }
    }

    // Question: What does running value mean?
    // returns balance of NFT - cannot calculate on-chain so this is a running value
    function balanceOfNFT() public view returns (uint256) {

        (uint160 sqrtPriceX96,,,,,,) = IUniV3Pool(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(sqrtPriceX96);

        // dai and frax have same decimals, unnecessary
        //uint256 fraxRebase = amount0;//.div(1e12);

        // TODO: Convert in terms of want. Assuming 1:1 stable:frax
        // uint decFrax = ERC20(frax).decimals()
        // uint decWant = ERC20(want).decimals()
        //        if(decFrax > decWant){
        //            return fraxTrue.div(10 ** (decFrax.sub(decWant)));
        //        }else{
        //            return fraxTrue.mul(10 ** (decWant.sub(decFrax)));
        //        }

        return amount0.add(amount1);

    }

    // Question: Why sell FXS on V2 when V3 interfaces are all set up?
    // swaps rewarded tokens for want
    // uses UniV2. May want to include Sushi / UniV3
    function _swap(uint256 _amountIn, address _token) internal {
        address[] memory path = new address[](3);
        path[0] = _token;
        // token to swap
        path[1] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // weth
        path[2] = address(want);

        IUni(unirouter).swapExactTokensForTokens(
            _amountIn,
            0,
            path,
            address(this),
            now
        );
    }

    // TODO: Consolidate to one function
    // TODO: Move indices to function param _curveSwapToFrax(uint256 _amountIn, uint8 _indexIn, uint8 _indexOut)
    function _curveSwapToFrax(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(1, 0, _amountIn, 0);
    }

    // TODO: Remove
    function _curveSwapToWant(uint256 _amountIn) internal {
        // sets a slippage tolerance of 0.5%
        //uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(0, 1, _amountIn, 0);
    }

    // TODO: Convention is to have internal function prepended with _ and external functions without.
    // TODO: Rename to curveSwap(...)
    // TODO: Descope to onlyVaultManagers
    // TODO: Add this to natspec `USDC is 2, DAI is 1, Tether is 3, frax is 0` to help executor
    // TODO: Reuse internal function
    // to use in case the frax:want ratio slips significantly away from 1:1
    function _externalSwapToFrax(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(1, 0, _amountIn, _amountOut);
    }

    // TODO: Remove this method. Redundant, can be merged with above
    function _externalSwapToWant(uint256 _amountIn) external onlyGovernance {
        // sets a slippage tolerance of 0.5%
        uint256 _amountOut = _amountIn.mul(9950).div(10000);
        // USDC is 2, DAI is 1, Tether is 3, frax is 0
        ICurveFi(curve).exchange_underlying(0, 1, _amountIn, _amountOut);
    }

    // TODO: Convention is to have internal function prepended with _ and external functions without
    // TODO: Add checks for !rewardsCollectionPaused(), earned() > 0
    // claims rewards if unlocked
    function claimReward() internal {
        IFrax(fraxLock).getReward();
    }

    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }

    // TODO: rename _percentKeepInBips or enforce range = [0, 10000]
    // the amount of FXS to keep
    function setKeep(uint256 _percentKeep) external onlyGovernance {
        percentKeep = _percentKeep;
    }

    // where FXS goes
    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }

    // TODO: Non-critical function can be descoped to onlyVaultManagers
    // sets time locked as a multiple of days. Would recommend values between 1-7.
    // initial value is set to 1
    function setFraxTimelock(uint256 _days) external onlyGovernance {
        uint256 _secs = _days.mul(86400);
        // TODO: require(_secs >= fraxLock.lock_time_min)
        fraxTimelockSet = _secs;
    }

    // TODO: tokenId is set automatically when nft is minted. This setter isn't necessary unless it's meant to be used as an override, in which case, should be descoped to onlyVaultManager
    // sets the id of the minted NFT. Unknowable until mintNFT is called
    function setTokenID(uint256 _id) external onlyGovernance {
        tokenId = _id;
    }

    // TODO: Remove. Unused
    function convertTo128(uint256 _var) public returns (uint128) {
        return uint128(_var);
    }

    // TODO: Remove. Unused
    function convertTo256(uint128 _var) public returns (uint256) {
        return uint256(_var);
    }

    // TODO: Remove. fraxTimelockSet is already a public variable which will autogenerate a getter
    function readTimeLock() public view returns (uint256) {
        return fraxTimelockSet;
    }

    // TODO: Instead needing to call this separately and manually, why not integrate this into adjustPosition?
    // TODO: You can do something like if(tokenId = 0 && initBalance>0) mintNFT()
    // This function is needed to initialize the entire strategy.
    // want needs to be airdropped to the strategy in a nominal amount. Say ~1k USD worth.
    // This will run through the process of minting the NFT on UniV3
    // that NFT will be the NFT we use for this strat. We will add/sub balances, but never burn the NFT
    // it will always have dust, accordingly
    function mintNFT() external onlyGovernance {
        // TODO: Add require for tokenId == 0
        uint256 initBalance = IERC20(want).balanceOf(address(this));

        if (initBalance == 0) {
            return;
        }

        //div(2) with extra decimal accuracy
        // This doesn't do actually do anything.
        // Example: 5 * 100000 / 200000 = 5 / 2 = 2
        uint256 swapAmt = initBalance.mul(1e5).div(2e5);
        _curveSwapToFrax(swapAmt);

        // TODO: Genericize this
        uint256 token0Balance = IERC20(uniNFT.token0()).balanceOf(address(this));
        uint256 token1Balance = IERC20(uniNFT.token1()).balanceOf(address(this));
        // uint256 fraxBalance = IERC20(frax).balanceOf(address(this));
        // uint256 wantBalance = IERC20(want).balanceOf(address(this));

        uint256 timestamp = block.timestamp;
        uint256 deadline = timestamp.add(5 * 60);

        // may want to make these settable
        // values for FRAX/Dai
        //uint24 fee = 500;
        //int24 tickLower = (-50);
        //int24 tickUpper = (50);
        // values for FRAX/USDC
        //uint24 fee = 500;
        //int24 tickLower = (-276380);
        //int24 tickUpper = (-276270);

        // TODO: Abstract out the tick values to the function param or even better, pass it in at constructor level
        IUniNFT.nftStruct memory setNFT = IUniNFT.nftStruct(
            uniNFT.token0(),
            uniNFT.token1(),
        //  address(want),
        //  address(frax),
            500,
            (- 50),
            50,
            wantBalance,
            fraxBalance,
            0,
            0,
            address(this),
            deadline);

        //time to mint the NFT
        (uint256 tokenOut,,,) = IUniNFT(uniNFT).mint(setNFT);

        tokenId = tokenOut;

    }

    // TODO: It'll greatly help other devs if you can abstract this out into the library too. This way, we can just reuse the entire folder without further refactoring
    // turning PositionValue.sol into an internal function
    // positionManager is uniNFT, tokenId, sqrt
    function principal(
    // TODO: Uncomment these
    //contract uniNFT,
    //tokenId,
        uint160 sqrtRatioX96
    ) internal view returns (uint256 amount0, uint256 amount1) {
        (, , , , , int24 tickLower, int24 tickUpper, uint128 liquidity, , , ,) = IUniNFT(uniNFT).positions(tokenId);

        return
        LiquidityAmounts.getAmountsForLiquidity(
            sqrtRatioX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    // TODO: Suggestion if possible, add triggers for harvest and tend when it's free to unlock so that we don't accidentally forfeit the locking rewards
    function nftUnlock() internal {
        // TODO: Require(withdrawalsPaused() == false), otherwise migration can happen without the nft transferred, essentially losing our entire position
        address nftOwner = IUniNFT(uniNFT).ownerOf(tokenId);
        if (nftOwner == address(fraxLock)) {
            IFrax(fraxLock).withdrawLocked(tokenId);
        }
    }

    // TODO: I recommend just leaving this blank. Not worth to add unirouter just for an estimation, unless V2 has concentrated liquidity
    // below for 0.4.3 upgrade
    function ethToWant(uint256 _amtInWei)
    public
    view
    override
    returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        // weth
        path[1] = address(want);

        uint256[] memory amounts = IUni(unirouter).getAmountsOut(_amtInWei, path);

        return amounts[amounts.length - 1];
    }

    function liquidateAllPositions()
    internal
    override
    returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        // TODO: You'll actually want to use a much larger number (rec: uint max) because of this line `if (_balanceOfWant < _amountNeeded)`
        // TODO: Having credits larger than 42069 would bypass _withdrawSome and break your logic, leaving funds still lp'ed and report large losses during emergency
        (_amountFreed,) = liquidatePosition(420_69);
    }
}
