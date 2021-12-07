# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyPoolTogether


@pytest.mark.require_network("mainnet-fork")
def test_revoke(
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
    liveStrategy,
    liveGov,
):
    dai.approve(dai_liquidity, Wei("1000000 ether"), {"from": dai_liquidity})
    dai.transferFrom(dai_liquidity, gov, Wei("300000 ether"), {"from": dai_liquidity})
    dai.approve(gov, Wei("1000000 ether"), {"from": gov})
    dai.transferFrom(gov, bob, Wei("1000 ether"), {"from": gov})
    dai.transferFrom(gov, alice, Wei("4000 ether"), {"from": gov})
    dai.transferFrom(gov, tinytim, Wei("10 ether"), {"from": gov})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": bob})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": alice})
    dai.approve(liveVault, Wei("1000000 ether"), {"from": tinytim})

    gen_lender = Contract(liveVault.withdrawalQueue(0))
    gen_lender_ratio = liveVault.strategies(gen_lender).dict()['debtRatio'] - 500
    liveVault.updateStrategyDebtRatio(gen_lender, gen_lender_ratio, {'from': liveGov})

    liveVault.addStrategy(strategy, 500, 0, 1_000, {"from": liveGov})
    strategy.harvest({"from": liveGov})
    dai_before = dai.balanceOf(liveVault)
    chain.sleep(60*60*5)
    chain.mine()
    strategy.harvest({"from": liveGov})
    liveVault.revokeStrategy(strategy, {"from": liveGov})
    strategy.harvest({"from": liveGov})

    dai_after = dai.balanceOf(liveVault)
    assert dai_after > dai_before
