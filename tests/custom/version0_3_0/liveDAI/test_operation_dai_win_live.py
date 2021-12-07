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
    ticket_liquidity,
    bonus_liquidity,
    bonus,
    uni,
    liveStrategy,
    liveGov,
):

    dai.approve(dai_liquidity, Wei("1000000 ether"), {"from": dai_liquidity})
    dai.transferFrom(dai_liquidity, gov, Wei("10000 ether"), {"from": dai_liquidity})
    dai.approve(gov, Wei("1000000 ether"), {"from": gov})
    dai.transferFrom(gov, bob, Wei("1000 ether"), {"from": gov})
    dai.transferFrom(gov, alice, Wei("4000 ether"), {"from": gov})
    dai.transferFrom(gov, tinytim, Wei("10 ether"), {"from": gov})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": bob})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": alice})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": tinytim})

    bonus.approve(bonus_liquidity, Wei("1000000 ether"), {"from": bonus_liquidity})
    bonus.transferFrom(
        bonus_liquidity, gov, Wei("300000 ether"), {"from": bonus_liquidity}
    )
    bonus.approve(uni, Wei("1000000 ether"), {"from": strategy})
    bonus.approve(uni, Wei("1000000 ether"), {"from": gov})
    bonus.approve(gov, Wei("1000000 ether"), {"from": gov})

    ticket.approve(ticket_liquidity, Wei("1000000 ether"), {"from": ticket_liquidity})
    ticket.transferFrom(
        ticket_liquidity, gov, Wei("300000 ether"), {"from": ticket_liquidity}
    )
    ticket.approve(uni, Wei("1000000 ether"), {"from": strategy})
    ticket.approve(uni, Wei("1000000 ether"), {"from": gov})
    ticket.approve(gov, Wei("1000000 ether"), {"from": gov})

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

    dai_after = dai.balanceOf(liveVault)
    assert dai_after > dai_before

    # users deposit to vault
    liveVault.deposit(Wei("1000 ether"), {"from": bob})
    liveVault.deposit(Wei("4000 ether"), {"from": alice})
    liveVault.deposit(Wei("10 ether"), {"from": tinytim})

    # first harvest
    chain.mine(1)
    strategy.harvest({"from": liveGov})

    assert ticket.balanceOf(strategy) > 0
    dai_vault_before = dai.balanceOf(liveVault)
    chain.sleep(3600 * 24 * 14)
    chain.mine(1)

    # 6 hours for pricepershare to go up, there should be profit
    # using dai balance as profit measurement
    strategy.harvest({"from": liveGov})
    chain.sleep(3600 * 6)
    chain.mine(1)
    dai_vault_after = dai.balanceOf(liveVault)
    assert dai_vault_after > dai_vault_before

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": liveGov})
    chain.sleep(3600 * 6)
    chain.mine(1)

    # now we deal with winning a drawing. Both bonus and extra tickets.
    # basically just airdrop both, that's how winning works anyways
    ticket.transferFrom(gov, strategy, Wei("1000 ether"), {"from": gov})
    bonus.transferFrom(gov, strategy, Wei("10 ether"), {"from": gov})

    strategy.harvest({"from": liveGov})
    chain.mine(1)

    # 6 hours for pricepershare to go up
    chain.sleep(3600 * 6)
    chain.mine(1)

    dai_in_vault = dai.balanceOf(liveVault)
    assert dai_in_vault > 0
