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

    assert comp.balanceOf(vault) > 0

    c = vault.balanceOf(alice)

    vault.withdraw(c, alice, 75, {"from": alice})

    assert comp.balanceOf(alice) > 0

    d = vault.balanceOf(bob)
    vault.withdraw(d, bob, 75, {"from": bob})

    assert comp.balanceOf(bob) > 0

    e = vault.balanceOf(tinytim)
    vault.withdraw(e, tinytim, 75, {"from": tinytim})

    assert comp.balanceOf(tinytim) > 0
