import pytest
from brownie import config, Contract

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass

@pytest.fixture
def comp_liquidity(accounts):
    yield accounts.at("0x7587cAefc8096f5F40ACB83A09Df031a018C66ec", force=True)

@pytest.fixture
def comptoken():
    token_address = "0xc00e94cb662c3520282e6f5717214004a7f26888"
    yield Contract(token_address)

@pytest.fixture
def compVault():
    yield Contract.from_explorer("0x5B707472eeF1553646740a7e5BEcFD41B9B4Ef4C")

@pytest.fixture
def stratCompLend():
    yield Contract.from_explorer("0xB926D027d8dEbC45D81Fee3BC853a6191551D43a")

@pytest.fixture
def stratCompPT():
    yield Contract.from_explorer("0x534d891514E8d092982317C3621a77b68615A29c")

@pytest.fixture
def me(accounts):
    yield accounts.at("0x1a123d835B006d27d4978C8EB40B14f08e0b8607", force=True)

@pytest.fixture
def compLendPlug():
    yield Contract.from_explorer("0x3DfA2E3675e984d9d59DE6871411B0897908fBaB")
