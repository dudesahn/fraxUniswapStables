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
def dai_liquidity(accounts):
    yield accounts.at("0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7", force=True)


@pytest.fixture
def dai():
    token_address = "0x6b175474e89094c44da98b954eedeac495271d0f"
    yield Contract(token_address)


@pytest.fixture
def vault(pm, gov, rewards, guardian, management, dai):
    Vault = pm(config["dependencies"][0]).Vault
    vault = guardian.deploy(Vault)
    vault.initialize(dai, gov, rewards, "", "", guardian)
    vault.setDepositLimit(2 ** 256 - 1, {"from": gov})
    vault.setManagement(management, {"from": gov})
    yield vault


@pytest.fixture
def strategy(
    strategist,
    guardian,
    keeper,
    liveVault,
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
        liveVault,
        want_pool,
        pool_token,
        uni,
        bonus,
        faucet,
        ticket,
    )
    strategy.setKeeper(keeper)
    yield strategy


@pytest.fixture
def uni():
    yield Contract("0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D")


@pytest.fixture
def want_pool():
    yield Contract("0xEBfb47A7ad0FD6e57323C8A42B2E5A6a4F68fc1a")


@pytest.fixture
def pool_token():
    yield Contract("0x0cec1a9154ff802e7934fc916ed7ca50bde6844e")


@pytest.fixture
def bonus():
    yield Contract("0xc00e94cb662c3520282e6f5717214004a7f26888")


@pytest.fixture
def faucet():
    yield Contract("0xF362ce295F2A4eaE4348fFC8cDBCe8d729ccb8Eb")


@pytest.fixture
def ticket():
    yield Contract("0x334cbb5858417aee161b53ee0d5349ccf54514cf")


@pytest.fixture
def newstrategy(
    strategist,
    guardian,
    keeper,
    liveVault,
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
        liveVault,
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
    yield accounts.at("0x926e78b8DF67e129011750Dd7b975f8E50D3d7Ad", force=True)


@pytest.fixture
def bonus_liquidity(accounts):
    yield accounts.at("0x7587cAefc8096f5F40ACB83A09Df031a018C66ec", force=True)

@pytest.fixture
def liveVault():
    yield Contract("0x19D3364A399d251E894aC732651be8B0E4e85001")

@pytest.fixture
def liveStrategy():
    yield Contract("0x32b8C26d0439e1959CEa6262CBabC12320b384c4")

@pytest.fixture
def liveGov():
    yield Contract("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52")


@pytest.fixture
def treasury(accounts):
    yield accounts.at("0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde", force=True)
