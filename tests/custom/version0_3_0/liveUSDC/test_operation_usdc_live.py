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

    # Funding and vault approvals
    # Can be also done from the conftest and remove dai_liquidity from here
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

    # First harvest
    strategy.harvest({"from": liveGov})
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    assert ticket.balanceOf(strategy) > 0
    usdc_vault_before = usdc.balanceOf(liveVault)
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    # 6 hours for pricepershare to go up, there should be profit
    # using USDC in vault as tracker of profit
    strategy.harvest({"from": liveGov})
    chain.sleep(3600 * 12)
    chain.mine(1)
    usdc_vault_after = usdc.balanceOf(liveVault)
    assert usdc_vault_after > usdc_vault_before

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": liveGov})
    chain.sleep(3600 * 12)
    chain.mine(1)

    alice_vault_balance = liveVault.balanceOf(alice)
    liveVault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert usdc.balanceOf(alice) > 0
    assert usdc.balanceOf(bob) == 0
    assert ticket.balanceOf(strategy) > 0

    bob_vault_balance = liveVault.balanceOf(bob)
    liveVault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert usdc.balanceOf(bob) > 0
    assert usdc.balanceOf(strategy) == 0

    tt_vault_balance = liveVault.balanceOf(tinytim)
    liveVault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert usdc.balanceOf(tinytim) > 0
    assert usdc.balanceOf(strategy) == 0

    # We should have made profit
    assert liveVault.pricePerShare() > 1e6
