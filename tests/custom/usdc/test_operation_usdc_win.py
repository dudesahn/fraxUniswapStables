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
    ticket_liquidity,
    bonus_liquidity,
    bonus,
    uni,
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

    bonus.approve(bonus_liquidity, Wei("1000000 ether"), {"from": bonus_liquidity})
    bonus.transferFrom(
        bonus_liquidity, gov, Wei("10000 ether"), {"from": bonus_liquidity}
    )
    bonus.approve(uni, Wei("1000000 ether"), {"from": strategy})
    bonus.approve(uni, Wei("1000000 ether"), {"from": gov})
    bonus.approve(gov, Wei("1000000 ether"), {"from": gov})

    ticket.approve(ticket_liquidity, 1_000_000_000000, {"from": ticket_liquidity})
    ticket.transferFrom(
        ticket_liquidity, gov, 30_000_000000, {"from": ticket_liquidity}
    )
    ticket.approve(uni, 1_000_000_000000, {"from": strategy})
    ticket.approve(uni, 1_000_000_000000, {"from": gov})
    ticket.approve(gov, 1_000_000_000000, {"from": gov})

    # users deposit to vault
    vault.deposit(1000_000_000, {"from": bob})
    vault.deposit(4000_000_000, {"from": alice})
    vault.deposit(10_000_000, {"from": tinytim})

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
    ticket.transferFrom(gov, strategy, 1_000_000000, {"from": gov})
    bonus.transferFrom(gov, strategy, Wei("10 ether"), {"from": gov})

    strategy.harvest({"from": gov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    pps_after_winning = vault.pricePerShare()

    assert pps_after_winning > pps_after_second_harvest
    usdc_in_vault = usdc.balanceOf(vault)
    assert usdc_in_vault > 0
