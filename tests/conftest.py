import pytest
from brownie import config, Contract

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass

@pytest.fixture
def gov(accounts):
    yield accounts[0]


@pytest.fixture
def rewards(accounts):
    yield accounts[1]


@pytest.fixture
def guardian(accounts):
    yield accounts[2]


@pytest.fixture
def management(accounts):
    yield accounts[3]


@pytest.fixture
def strategist(accounts):
    yield accounts[4]


@pytest.fixture
def keeper(accounts):
    yield accounts[5]


@pytest.fixture
def alice(accounts):
    yield accounts[6]


@pytest.fixture
def bob(accounts):
    yield accounts[7]


@pytest.fixture
def tinytim(accounts):
    yield accounts[8]


@pytest.fixture
def usdc_liquidity(accounts):
    yield accounts.at("0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7", force=True)


@pytest.fixture
def usdc():
    token_address = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48"
    yield Contract(token_address)


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, usdc):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(usdc, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault

@pytest.fixture
def uniV3Pool():
    yield Contract.from_explorer("0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52")

@pytest.fixture
def strategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyFraxUniswapUSDC,
    gov,
    frax,
    fxs,
    uni,
    uniNFT,
    fraxLock,
    curve,
    uniV3Pool,
):
    strategy = guardian.deploy(
        StrategyFraxUniswapUSDC,
        vault,
    )
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture
def uni():
    yield Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")


@pytest.fixture
def frax():
    yield Contract("0x853d955acef822db058eb8505911ed77f175b99e")


@pytest.fixture
def fxs():
    yield Contract("0x3432b6a60d23ca0dfca7761b7ab56459d9c964d0")


@pytest.fixture
def uniNFT():
    yield Contract("0xC36442b4a4522E871399CD717aBDD847Ab11FE88")


@pytest.fixture
def fraxLock():
    yield Contract("0x3EF26504dbc8Dd7B7aa3E97Bc9f3813a9FC0B4B0")


@pytest.fixture
def curve():
    yield Contract("0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B")


@pytest.fixture
def newstrategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyFraxUniswapUSDC,
    gov,
    frax,
    fxs,
    uni,
    uniNFT,
    fraxLock,
    curve,
    uniV3Pool,
):
    newstrategy = guardian.deploy(
        StrategyFraxUniswapUSDC,
        vault,
    )
    newstrategy.setKeeper(keeper)
    yield newstrategy


@pytest.fixture
def frax_liquidity(accounts):
    yield accounts.at("0xd632f22692fac7611d2aa1c0d552930d43caed3b", force=True)


@pytest.fixture
def fxs_liquidity(accounts):
    yield accounts.at("0xf977814e90da44bfa03b6295a0616a897441acec", force=True)

@pytest.fixture
def token_owner(accounts):
    yield accounts.at("0x8412ebf45bac1b340bbe8f318b928c466c4e39ca", force=True)



