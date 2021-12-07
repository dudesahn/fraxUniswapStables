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
    uniVault,
    stratUniLend,
    stratUniPT,
    unitoken,
    uni_liquidity,
    me,
):

    unitoken.approve(uni_liquidity, Wei("1000000 ether"), {"from": uni_liquidity})
    unitoken.transferFrom(uni_liquidity, me, Wei("3000 ether"), {"from": uni_liquidity})

    unitoken.approve(me, Wei("1000000 ether"), {"from": me})
    unitoken.approve(uniVault, Wei("1000000 ether"), {"from": me})

    uniVault.deposit(Wei("3000 ether"), {"from": me})

    uniVault.updateStrategyMaxDebtPerHarvest(stratUniLend, 2 ** 256 - 1, {"from": me})
    uniVault.updateStrategyMaxDebtPerHarvest(stratUniPT, 2 ** 256 - 1, {"from": me})

    firstUni = unitoken.balanceOf(uniVault)

    chain.sleep(3600)
    chain.mine(1)

    stratUniPT.harvest({"from": me})
    stratUniLend.harvest({"from": me})

    secondUni = unitoken.balanceOf(uniVault)

    assert secondUni < firstUni

    uniBefore = unitoken.balanceOf(uniVault)

    chain.sleep(3600*24*14)
    chain.mine(1)
    pps_after_first_harvest = uniVault.pricePerShare()

    stratUniPT.harvest({"from": me})
    stratUniLend.harvest({"from": me})

    chain.sleep(3600 * 6)
    chain.mine(1)
    pps_after_second_harvest = uniVault.pricePerShare()
    uniAfter = unitoken.balanceOf(uniVault)
    assert pps_after_second_harvest > pps_after_first_harvest
    assert uniAfter > uniBefore


