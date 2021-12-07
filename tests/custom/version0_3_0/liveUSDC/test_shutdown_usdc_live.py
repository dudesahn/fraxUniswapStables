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
    usdc,
    usdc_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
    liveStrategy,
    liveGov,
):
    usdc.approve(usdc_liquidity, 1_000_000_000000, {"from": usdc_liquidity})
    usdc.transferFrom(usdc_liquidity, gov, 300_000_000000, {"from": usdc_liquidity})
    usdc.approve(gov, 1_000_000_000000, {"from": gov})
    usdc.transferFrom(gov, bob, 10000_000000, {"from": gov})
    usdc.transferFrom(gov, alice, 40000_000000, {"from": gov})
    usdc.transferFrom(gov, tinytim, 10_000000, {"from": gov})
    usdc.approve(liveVault, 1_000_000_000000, {"from": bob})
    usdc.approve(liveVault, 1_000_000_000000, {"from": alice})
    usdc.approve(liveVault, 1_000_000_000000, {"from": tinytim})

    liveVault.updateStrategyDebtRatio(liveStrategy, 0, {"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveVault.addStrategy(strategy, 3_000, 0, 0, {"from": liveGov})
    chain.sleep(60)
    chain.mine(1)

    usdc_before = usdc.balanceOf(liveVault)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)
    liveStrategy.harvest({"from": liveGov})
    chain.sleep(60)
    chain.mine(1)

    usdc_after = usdc.balanceOf(liveVault)
    assert usdc_after > usdc_before

    # users deposit to vault
    liveVault.deposit(10000_000_000, {"from": bob})
    liveVault.deposit(40000_000_000, {"from": alice})
    liveVault.deposit(10_000_000, {"from": tinytim})

    chain.mine(1)
    strategy.harvest({"from": liveGov})

    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    # first harvest
    strategy.harvest({"from": liveGov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    strategy.setEmergencyExit({"from": liveGov})
    strategy.harvest({"from": liveGov})
    chain.mine(1)

    assert usdc.balanceOf(liveVault) > 0

    c = liveVault.balanceOf(alice)

    liveVault.withdraw(c, alice, 75, {"from": alice})

    assert usdc.balanceOf(alice) > 0

    d = liveVault.balanceOf(bob)
    liveVault.withdraw(d, bob, 75, {"from": bob})

    assert usdc.balanceOf(bob) > 0

    e = liveVault.balanceOf(tinytim)
    liveVault.withdraw(e, tinytim, 75, {"from": tinytim})

    assert usdc.balanceOf(tinytim) > 0
