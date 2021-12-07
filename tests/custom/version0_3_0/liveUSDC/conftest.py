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
    yield Contract("0xde9ec95d7708B8319CCca4b8BC92c0a3B70bf416")


@pytest.fixture
def pool_token():
    yield Contract("0x0cec1a9154ff802e7934fc916ed7ca50bde6844e")


@pytest.fixture
def bonus():
    yield Contract("0xc00e94cb662c3520282e6f5717214004a7f26888")


@pytest.fixture
def faucet():
    yield Contract("0xBD537257fAd96e977b9E545bE583bbF7028F30b9")


@pytest.fixture
def ticket():
    yield Contract("0xd81b1a8b1ad00baa2d6609e0bae28a38713872f7")


@pytest.fixture
def ticket_liquidity(accounts):
    yield accounts.at("0x80845058350B8c3Df5c3015d8a717D64B3bF9267", force=True)


@pytest.fixture
def bonus_liquidity(accounts):
    yield accounts.at("0x7587cAefc8096f5F40ACB83A09Df031a018C66ec", force=True)

@pytest.fixture
def liveVault():
    yield Contract("0x5f18C75AbDAe578b483E5F43f12a39cF75b973a9")

@pytest.fixture
def liveStrategy():
    yield Contract("0x4D7d4485fD600c61d840ccbeC328BfD76A050F87")

@pytest.fixture
def liveGov():
    yield Contract("0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52")

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