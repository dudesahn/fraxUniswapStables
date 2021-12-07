import pytest
from brownie import config, Contract

# Snapshots the chain before each test and reverts after test completion.
@pytest.fixture(scope="function", autouse=True)
def shared_setup(fn_isolation):
    pass

@pytest.fixture
def uni_liquidity(accounts):
    yield accounts.at("0xbe0eb53f46cd790cd13851d5eff43d12404d33e8", force=True)

@pytest.fixture
def unitoken():
    token_address = "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984"
    yield Contract(token_address)

@pytest.fixture
def uniVault():
    yield Contract.from_explorer("0xFBEB78a723b8087fD2ea7Ef1afEc93d35E8Bed42")

@pytest.fixture
def stratUniLend():
    yield Contract.from_explorer("0x5e882c9f00209315e049B885B9b3dfbEe60D80A4")

@pytest.fixture
def stratUniPT():
    yield Contract.from_explorer("0x6EB00860260CF51623737e17579Db797d71cd337")

@pytest.fixture
def me(accounts):
    yield accounts.at("0x1a123d835B006d27d4978C8EB40B14f08e0b8607", force=True)
