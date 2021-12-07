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
def uni_liquidity(accounts):
    yield accounts.at("0xbe0eb53f46cd790cd13851d5eff43d12404d33e8", force=True)


@pytest.fixture
def unitoken():
    token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    yield Contract(token_address)


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, unitoken):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(unitoken, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyPoolTogether,
    gov,
    want_pool,
    pool_token,
    uni,
    bonus,
    faucet,
    ticket,
):
    strategy = guardian.deploy(
        StrategyPoolTogether,
        vault,
        want_pool,
        pool_token,
        uni,
        bonus,
        faucet,
        ticket,
    )
    strategy.setKeeper(keeper)
    vault.addStrategy(strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})
    yield strategy


@pytest.fixture
def uni():  # unirouter contract
    yield Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")


@pytest.fixture
def want_pool():
    yield Contract("0x0650d780292142835F6ac58dd8E2a336e87b4393")


@pytest.fixture
def pool_token():
    yield Contract("0x0cec1a9154ff802e7934fc916ed7ca50bde6844e")


@pytest.fixture
def bonus():
    yield Contract("0xc00e94cb662c3520282e6f5717214004a7f26888")


@pytest.fixture
def faucet():
    yield Contract("0xa5dddefD30e234Be2Ac6FC1a0364cFD337aa0f61")


@pytest.fixture
def ticket():
    yield Contract("0xa92a861fc11b99b24296af880011b47f9cafb5ab")


@pytest.fixture
def newstrategy(
    strategist,
    guardian,
    keeper,
    vault,
    StrategyPoolTogether,
    gov,
    want_pool,
    pool_token,
    uni,
    bonus,
    faucet,
    ticket,
):
    newstrategy = guardian.deploy(
        StrategyPoolTogether,
        vault,
        want_pool,
        pool_token,
        uni,
        bonus,
        faucet,
        ticket,
    )
    newstrategy.setKeeper(keeper)
    yield newstrategy


@pytest.fixture
def ticket_liquidity(accounts):
    yield accounts.at("0x330e75e1f48b1ee968197cc870511665a4a5a832", force=True)


@pytest.fixture
def bonus_liquidity(accounts):
    yield accounts.at("0x7587cAefc8096f5F40ACB83A09Df031a018C66ec", force=True)
