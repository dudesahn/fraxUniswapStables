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
    liveVault,
    strategy,
    ticket,
    dai,
    dai_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
    newstrategy,
    liveStrategy,
    liveGov,
):

    dai.approve(dai_liquidity, Wei("1000000 ether"), {"from": dai_liquidity})
    dai.transferFrom(dai_liquidity, gov, Wei("300000 ether"), {"from": dai_liquidity})
    dai.approve(gov, Wei("1000000 ether"), {"from": gov})
    dai.transferFrom(gov, bob, Wei("10000 ether"), {"from": gov})
    dai.transferFrom(gov, alice, Wei("40000 ether"), {"from": gov})
    dai.transferFrom(gov, tinytim, Wei("10 ether"), {"from": gov})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": bob})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": alice})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": tinytim})

    liveVault.updateStrategyDebtRatio(liveStrategy, 0, {"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveVault.addStrategy(strategy, 1_500, 0, 0, {"from": liveGov})
    chain.sleep(60)
    chain.mine(1)

    dai_before = dai.balanceOf(liveVault)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)

    # users deposit to vault
    liveVault.deposit(Wei("1000 ether"), {"from": bob})
    liveVault.deposit(Wei("4000 ether"), {"from": alice})
    liveVault.deposit(Wei("10 ether"), {"from": tinytim})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": liveGov})

    # one week passes & profit is generated
    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)
    strategy.harvest({"from": liveGov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    newstrategy.setStrategist(strategist)
    liveVault.migrateStrategy(strategy, newstrategy, {"from": liveGov})

    assert ticket.balanceOf(strategy) == 0
    assert ticket.balanceOf(newstrategy) > 0
