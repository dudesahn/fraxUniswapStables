// SPDX-License-Identifier: MIT

pragma experimental ABIEncoderV2;
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/openZeppelin/IERC20Metadata.sol";


import {BaseStrategy} from "@yearn/contracts/BaseStrategy.sol";

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
import "../../libraries/PositionValue.sol";
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
contract StrategyFraxUniswap is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint128;


    // variables for determining how much governance token to hold for voting rights
    uint256 public constant _denominator = 10000;
    uint256 public percentKeep;
    uint256 public fraxTimelockSet;
    address public refer;
    address public treasury;
    address public oldStrategy;
    
    // these are variables specific to our want-FRAX pair
    uint256 public tokenId;
    address internal constant fraxLock = 0xF22471AC2156B489CC4a59092c56713F813ff53e;
    address internal constant uniV3Pool = 0x97e7d56A0408570bA1a7852De36350f7713906ec;
    
    // set up our constants
    IERC20 internal constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    // IERC20 internal constant usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    
    address internal constant unirouter = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IERC20 internal constant frax = IERC20(0x853d955aCEf822Db058eb8505911ED77F175b99e);
    address internal constant fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address internal constant uniNFT = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address internal constant curve = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;

    string internal stratName; // set our strategy name here
    
    // these are our decimals
    uint256 internal decFrax = 18;
    uint256 internal decWant = 18;
    
    // check for cloning
    bool internal isOriginal = true;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _vault,
        address _fraxLock,
        address _uniV3Pool,
        string memory _name
    ) public BaseStrategy(_vault) {
        // Constructor should initialize local variables
        _initializeStrat(
            _fraxLock,
            _uniV3Pool,
            _name
        );
    }

    /* ========== CLONING ========== */

    event Cloned(address indexed clone);

    // we use this to clone our original strategy to other vaults
    function cloneSingleSideFrax(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        address _fraxLock,
        address _uniV3Pool,
        string memory _name
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

        StrategyFraxUniswap(newStrategy).initialize(
            _vault,
            _strategist,
            _rewards,
            _keeper,
            _fraxLock,
            _uniV3Pool,
            _name
        );

        emit Cloned(newStrategy);
    }

    // this will only be called by the clone function above
    function initialize(
        address _vault,
        address _strategist,
        address _rewards,
        address _keeper,
        string memory _name
    ) public {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrat(_name);
    }

    // this is called by our original strategy, as well as any clones
    function _initializeStrat(
        string memory _name
    ) internal {
        // make sure that we haven't initialized this before
        require(tokenId == 0); // dev: already initialized.
        // TODO: Add some checks here to make sure lock/nft/vault/pool tokens all match up

        percentKeep = 1000;
        // TODO: These seem to be old? https://gnosis-safe.io/app/eth:0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52/balances
        // ^^ was using the Treasury vault. Can change these to whatever the current address is.
        // Will be used in veFRAX voterproxy in the future, so the best may be SMS.
        refer = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        treasury = address(0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde);
        // TODO: Math.min(fraxLock.lock_time_min(), 86400);
        // ^^ The 86400 is a variable that can be set later on via set function. Would the above be able to be passed via function?
        // if so, easy fix.
        // changing default to 7 days
        fraxTimelockSet = 604800;
        tokenId = 1;
        // set to yearn treasury to init as failsafe
        oldStrategy = address(0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52);


        // TODO: Iterate through curve pool to find indices of want and frax
        // ^^ passing them in as constructor
        
        // mint tthe NFT in here too, duh
        
        // setting maxVar
        uint256 max256 = 2 ** 256 - 1;
        IERC20(want).safeApprove(curve, type(uint256).max);
        IERC20(frax).safeApprove(curve, type(uint256).max);
        IERC20(want).safeApprove(uniNFT, type(uint256).max);
        IERC20(frax).safeApprove(uniNFT, type(uint256).max);
        IERC20(fxs).safeApprove(unirouter, type(uint256).max);
        IERC721(uniNFT).setApprovalForAll(governance(), true);
        IERC721(uniNFT).setApprovalForAll(strategist, true);
        IERC721(uniNFT).setApprovalForAll(fraxLock, true);

        // set our strategy's name
        stratName = _name;
    }

    function name() external view override returns (string memory) {
        return stratName;
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
    // also: having to call setOldStrategy to act as password in order for the new upgraded strat to receive the NFT isn't much different than just setting the tokenId after migrating
    function onERC721Received(
        address,
        address,
        uint256 tokenIncoming,
        bytes calldata
    ) public pure virtual returns (bytes4) {
        //require(msg.sender == address(oldStrategy) || msg.sender == fraxLock, "nonallowed NFT sender address");
        //tokenId = tokenIncoming;

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
        //uint256 debt = vault.strategies(address(this)).totalDebt;

        _claimReward();

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

        if(tokenId == 0) {
            _mintNFT();
        }

        nftUnlock();

        uint256 _balanceOfWant = balanceOfWant();

        // Personal preference: Not necessary. Funds would be better utilized invested rather than sitting idle until next harvest
        // do not invest if we have more debt than want
        if (_debtOutstanding > _balanceOfWant) {
            return;
        }

        //uint256 sumBefore = valueOfFrax().add(_balanceOfWant);

        // Invest the rest of the want
        uint256 _wantAvailable = _balanceOfWant.sub(_debtOutstanding);
        if (_wantAvailable > 0) {
            // need to swap half want to frax
            uint256 halfWant = _wantAvailable.div(2);
            _curveSwap(halfWant, address(want), address(frax));

            uint256 token0Balance = dai.balanceOf(address(this));
            uint256 token1Balance = frax.balanceOf(address(this));

            IUniNFT.increaseStruct memory setIncrease = IUniNFT.increaseStruct(
                tokenId,
                token0Balance,
                token1Balance,
                0,
                0,
                block.timestamp);

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

        uint256 balanceOfWantBefore = balanceOfWant();
        //uint256 valueOfFraxBefore = IERC20(frax).balanceOf(address(this));

        nftUnlock();

        uint256 fraction;
        // _amount > balanceOfNFT() will result in unwanted results
        if (_amount > balanceOfNFT()) {
            fraction == 0;
        } else {
            fraction = (_amount).mul(1e18).div(balanceOfNFT());
        }

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
        uint128 MAX_INT = 2 ** 128 - 1;

        IUniNFT.collectStruct memory collectParams = IUniNFT.collectStruct(
            tokenId,
            address(this),
            MAX_INT,
            MAX_INT);

        IUniNFT(uniNFT).collect(collectParams);

        _curveSwap(IERC20(frax).balanceOf(address(this)), address(frax), address(want));
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

    // returns balance of frax, denominated in same decimals as want
    function valueOfFrax() public view returns (uint256) {
        return IERC20(frax).balanceOf(address(this));
    }

    // returns balance of NFT
    function balanceOfNFT() public view returns (uint256) {

        (uint160 sqrtPriceX96,,,,,,) = IUniV3Pool(uniV3Pool).slot0();

        (uint256 amount0, uint256 amount1) = principal(uniNFT, tokenId, sqrtPriceX96);

        return amount1.mul(2);
    }

    // swaps rewarded tokens for want
    // uses UniV2, which has deepest liq at time of publish
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

    function _curveSwap(uint256 _amountIn, address _tokenIn, address _tokenOut) internal {
        // USDC is 2, DAI is 1, Tether is 3, frax is 0

            uint8 _indexIn;
            uint8 _indexOut;
        if(_tokenIn == address(dai)) {
            _indexIn = 1;
        } else {
            _indexIn = 0;
        }
        if(_tokenOut == address(dai)) {
            _indexOut = 1;
        } else {
            _indexOut = 0;
        }

        ICurveFi(curve).exchange_underlying(_indexIn, _indexOut, _amountIn, 0);
    }

    // to use in case the frax:want ratio slips significantly away from 1:1
    /// @notice DAI is 1, USDC is 2, Tether is 3, frax is 0
//     function curveSwap(uint256 _amountIn, uint8 _indexIn, uint8 _indexOut) external onlyVaultManagers {
//         /// @notice DAI is 1, USDC is 2, Tether is 3, frax is 0
//         ICurveFi(curve).exchange_underlying(_indexIn, _indexOut, _amountIn, 0);
//     }

    // claims rewards if unlocked
    function _claimReward() internal {
        if(IFrax(fraxLock).rewardsCollectionPaused() == true){
            return;
        }
        if(IFrax(fraxLock).earned(address(this)) > 0) {
            IFrax(fraxLock).getReward();
         }
    }

    function setReferrer(address _refer) external onlyGovernance {
        refer = _refer;
    }

    // the amount of FXS to keep
    function setKeep(uint256 _percentKeepInBips) external onlyGovernance {
        percentKeep = _percentKeepInBips;
    }

    // where FXS goes
    function setTreasury(address _treasury) external onlyGovernance {
        treasury = _treasury;
    }

    // sets time locked as a multiple of days.
    // initial value is set to 7 day
    function setFraxTimelock(uint256 _days) external onlyVaultManagers {
        uint256 _secs = _days.mul(86400);
        require(_secs >= IFrax(fraxLock).lock_time_min(), "time below minimum required");
        require(_secs <= IFrax(fraxLock).lock_time_for_max_multiplier(), "time exceeds maximum");
        fraxTimelockSet = _secs;
    }

    // Override just in case
    function setTokenID(uint256 _id) external onlyVaultManagers {
        tokenId = _id;
    }

    // to be set before calling migrate -
    function setOldStrategy(address _oldStrategy) external onlyVaultManagers {
        oldStrategy = _oldStrategy;
    }

    // This function is needed to initialize the entire strategy.
    // This will run through the process of minting the NFT on UniV3
    // that NFT will be the NFT we use for this strat. We will add/sub balances, but never burn the NFT
    // it will always have dust, accordingly
    function _mintNFT() internal {
        require(tokenId == 1, "NFT already minted");
        uint256 initBalance = IERC20(want).balanceOf(address(this));
        require(initBalance >0, "no value to mint");

        uint256 swapAmt = initBalance.div(2);
        // swap want to Frax
        _curveSwap(swapAmt, address(want), address(frax));

        uint256 token0Balance = IERC20(IFrax(fraxLock).uni_token0()).balanceOf(address(this));
        uint256 token1Balance = IERC20(IFrax(fraxLock).uni_token1()).balanceOf(address(this));
        uint256 timestamp = block.timestamp;
        uint256 deadline = timestamp.add(5 * 60);

        // values for FRAX/Dai
        //uint24 fee = 500;
        //int24 tickLower = (-50);
        //int24 tickUpper = (50);
        // values for FRAX/USDC
        //uint24 fee = 500;
        //int24 tickLower = (-276380);
        //int24 tickUpper = (-276270);

        IUniNFT.nftStruct memory setNFT = IUniNFT.nftStruct(
            IFrax(fraxLock).uni_token0(),
            IFrax(fraxLock).uni_token1(),
            //500,
            //(- 50),
            //50,
            IFrax(fraxLock).uni_required_fee(),
            IFrax(fraxLock).uni_tick_lower(),
            IFrax(fraxLock).uni_tick_upper(),
            token0Balance,
            token1Balance,
            0,
            0,
            address(this),
            deadline);

        //time to mint the NFT
        (uint256 tokenOut,,,) = IUniNFT(uniNFT).mint(setNFT);

        tokenId = tokenOut;

    }

    // Calculates principal via PositionValue lib
    function principal(address _uniNFT, uint256 _tokenId, uint160 _sqrtRatioX96)
     internal view returns (uint256 amount0, uint256 amount1) {

        return PositionValue.principal(_uniNFT, _tokenId, _sqrtRatioX96);

    }

    // the unlock function here will fail if locked.
    // require(block.timestamp >= thisStake.ending_timestamp || stakesUnlocked == true, "Stake is still locked!")
    function nftUnlock() internal {
        // Require(withdrawalsPaused() == false), otherwise migration can happen without the nft transferred, essentially losing our entire position
        require (IFrax(fraxLock).withdrawalsPaused() == false, "withdrawals paused");
        address nftOwner = IUniNFT(uniNFT).ownerOf(tokenId);
        if (nftOwner == address(fraxLock)) {
            IFrax(fraxLock).withdrawLocked(tokenId);
        }
    }

    // V2 has the most concentrated liq - so I added this specifically for the 0.4.3 upgrade
    // below for 0.4.3 upgrade
    function ethToWant(uint256 _amtInWei)
    public
    view
    override
    returns (uint256)
    {}

    function liquidateAllPositions()
    internal
    override
    returns (uint256 _amountFreed)
    {
        //shouldn't matter, logic is already in liquidatePosition
        uint256 max256 = type(uint256).max;
        (_amountFreed,) = liquidatePosition(max256);
    }
}
