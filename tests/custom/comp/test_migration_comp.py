# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyPoolTogether


@pytest.mark.require_network("mainnet-fork")
def test_operation(
    chain,
    vault,
    strategy,
    ticket,
    comp,
    comp_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
    newstrategy,
):

    comp.approve(comp_liquidity, Wei("1000000 ether"), {"from": comp_liquidity})
    comp.transferFrom(comp_liquidity, gov, Wei("10000 ether"), {"from": comp_liquidity})
    comp.approve(gov, Wei("1000000 ether"), {"from": gov})
    comp.transferFrom(gov, bob, Wei("1000 ether"), {"from": gov})
    comp.transferFrom(gov, alice, Wei("4000 ether"), {"from": gov})
    comp.transferFrom(gov, tinytim, Wei("10 ether"), {"from": gov})
    comp.approve(vault, Wei("1000000 ether"), {"from": bob})
    comp.approve(vault, Wei("1000000 ether"), {"from": alice})
    comp.approve(vault, Wei("1000000 ether"), {"from": tinytim})

    # users deposit to vault
    vault.deposit(Wei("1000 ether"), {"from": bob})
    vault.deposit(Wei("4000 ether"), {"from": alice})
    vault.deposit(Wei("10 ether"), {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": gov})

    # one week passes & profit is generated
    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)
    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    newstrategy.setStrategist(strategist)
    vault.migrateStrategy(strategy, newstrategy, {"from": gov})

    assert ticket.balanceOf(strategy) == 0
    assert ticket.balanceOf(newstrategy) > 0
