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
    ticket_liquidity,
    bonus_liquidity,
    bonus,
    uni,
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
    liveVault.deposit(10000_000_000, {"from": bob})
    liveVault.deposit(40000_000_000, {"from": alice})
    liveVault.deposit(10_000_000, {"from": tinytim})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": liveGov})

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
    usdc_before_winning = usdc.balanceOf(liveVault)

    # now we deal with winning a drawing. Both bonus and extra tickets.
    # basically just airdrop both, that's how winning works anyways
    ticket.transferFrom(gov, strategy, 1_000_000000, {"from": gov})
    bonus.transferFrom(gov, strategy, Wei("10 ether"), {"from": gov})

    strategy.harvest({"from": liveGov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)
    usdc_after_winning = usdc.balanceOf(liveVault)

    assert usdc_after_winning > usdc_before_winning
    usdc_in_vault = usdc.balanceOf(liveVault)
    assert usdc_in_vault > 0
