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
    ticket_liquidity,
    bonus_liquidity,
    bonus,
    uni,
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

    bonus.approve(bonus_liquidity, Wei("1000000 ether"), {"from": bonus_liquidity})
    bonus.transferFrom(
        bonus_liquidity, gov, Wei("30000 ether"), {"from": bonus_liquidity}
    )
    bonus.approve(uni, Wei("1000000 ether"), {"from": strategy})
    bonus.approve(uni, Wei("1000000 ether"), {"from": gov})
    bonus.approve(gov, Wei("1000000 ether"), {"from": gov})

    ticket.approve(ticket_liquidity, Wei("1000000 ether"), {"from": ticket_liquidity})
    ticket.transferFrom(
        ticket_liquidity, gov, Wei("3000 ether"), {"from": ticket_liquidity}
    )
    ticket.approve(uni, Wei("1000000 ether"), {"from": strategy})
    ticket.approve(uni, Wei("1000000 ether"), {"from": gov})
    ticket.approve(gov, Wei("1000000 ether"), {"from": gov})

    # users deposit to vault
    vault.deposit(Wei("1000 ether"), {"from": bob})
    vault.deposit(Wei("4000 ether"), {"from": alice})
    vault.deposit(Wei("10 ether"), {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": gov})

    assert ticket.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # small profit
    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    pps_after_second_harvest = vault.pricePerShare()

    assert pps_after_second_harvest > pps_after_first_harvest

    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    # now we deal with winning a drawing. Both bonus and extra tickets.
    # basically just airdrop both, that's how winning works anyways
    ticket.transferFrom(gov, strategy, Wei("1000 ether"), {"from": gov})
    bonus.transferFrom(gov, strategy, Wei("10 ether"), {"from": gov})

    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    pps_after_winning = vault.pricePerShare()

    assert pps_after_winning > pps_after_second_harvest
    dai_in_vault = comp.balanceOf(vault)
    assert dai_in_vault > 0
