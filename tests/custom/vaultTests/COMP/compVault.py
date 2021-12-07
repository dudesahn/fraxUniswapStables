# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config


@pytest.mark.require_network("mainnet-fork")
def test_operation(
    chain,
    compVault,
    stratCompLend,
    stratCompPT,
    comptoken,
    comp_liquidity,
    me,
    compLendPlug,
):

    comptoken.approve(comp_liquidity, Wei("1000000 ether"), {"from": comp_liquidity})
    comptoken.transferFrom(comp_liquidity, me, Wei("3000 ether"), {"from": comp_liquidity})

    comptoken.approve(me, Wei("1000000 ether"), {"from": me})
    comptoken.approve(compVault, Wei("1000000 ether"), {"from": me})

    compVault.deposit(Wei("1000 ether"), {"from": me})

    stratCompLend.addLender(compLendPlug, {"from": me})

    compVault.addStrategy(stratCompLend, 6800, 0, 2 ** 256 - 1, 1000, {"from": me})
    #compVault.addStrategy(stratCompPT, 3000, 0, 2 ** 256 - 1, 1000, {"from": me})

    #compVault.updateStrategyMaxDebtPerHarvest(stratCompLend, 2 ** 256 - 1, {"from": me})
    #compVault.updateStrategyMaxDebtPerHarvest(stratCompPT, 2 ** 256 - 1, {"from": me})

    firstComp = comptoken.balanceOf(compVault)

    chain.sleep(3600)
    chain.mine(1)

    stratCompLend.harvest({"from": me})
    #stratCompPT.harvest({"from": me})


    secondComp = comptoken.balanceOf(compVault)

    assert secondComp < firstComp

    compBefore = comptoken.balanceOf(compVault)

    chain.sleep(3600*24*14)
    chain.mine(1)
    pps_after_first_harvest = compVault.pricePerShare()

    #stratCompPT.harvest({"from": me})
    stratCompLend.harvest({"from": me})

    chain.sleep(3600 * 6)
    chain.mine(1)
    pps_after_second_harvest = compVault.pricePerShare()
    compAfter = comptoken.balanceOf(compVault)
    assert pps_after_second_harvest > pps_after_first_harvest
    assert compAfter > compBefore

    assert 1 == 2


