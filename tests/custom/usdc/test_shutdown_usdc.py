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
    usdc,
    usdc_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
):
    usdc.approve(usdc_liquidity, 1_000_000_000000, {"from": usdc_liquidity})
    usdc.transferFrom(usdc_liquidity, gov, 300_000_000000, {"from": usdc_liquidity})
    usdc.approve(gov, 1_000_000_000000, {"from": gov})
    usdc.transferFrom(gov, bob, 1000_000000, {"from": gov})
    usdc.transferFrom(gov, alice, 4000_000000, {"from": gov})
    usdc.transferFrom(gov, tinytim, 10_000000, {"from": gov})
    usdc.approve(vault, 1_000_000_000000, {"from": bob})
    usdc.approve(vault, 1_000_000_000000, {"from": alice})
    usdc.approve(vault, 1_000_000_000000, {"from": tinytim})

    # users deposit to vault
    vault.deposit(1000_000_000, {"from": bob})
    vault.deposit(4000_000_000, {"from": alice})
    vault.deposit(10_000_000, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    chain.mine(1)
    strategy.harvest({"from": gov})

    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    # first harvest
    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    strategy.setEmergencyExit({"from": gov})
    strategy.harvest({"from": gov})
    chain.mine(1)

    assert usdc.balanceOf(vault) > 0

    c = vault.balanceOf(alice)

    vault.withdraw(c, alice, 75, {"from": alice})

    assert usdc.balanceOf(alice) > 0

    d = vault.balanceOf(bob)
    vault.withdraw(d, bob, 75, {"from": bob})

    assert usdc.balanceOf(bob) > 0

    e = vault.balanceOf(tinytim)
    vault.withdraw(e, tinytim, 75, {"from": tinytim})

    assert usdc.balanceOf(tinytim) > 0
