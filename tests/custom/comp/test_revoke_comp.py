import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyPoolTogether


def test_revoke_strategy_from_vault(
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
    # Deposit to the vault and harvest
    # Funding and vault approvals
    # Can be also done from the conftest and remove dai_liquidity from here
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

    deposit_amount = comp.balanceOf(vault)

    # First harvest
    strategy.harvest({"from": gov})

    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})
    assert comp.balanceOf(vault) > deposit_amount
