# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyFraxUniswapDAI


@pytest.mark.require_network("mainnet-fork")
def test_operation(
    chain,
    vault,
    strategy,
    frax,
    dai,
    dai_liquidity,
    gov,
    rewards,
    guardian,
    strategist,
    alice,
    bob,
    tinytim,
    uniNFT,
    fraxLock,
    fxs,
    fxs_liquidity,
    token_owner,
    uniV3Pool
):

    # Funding and vault approvals
    # Can be also done from the conftest and remove dai_liquidity from here
    dai.approve(dai_liquidity, 1_000_000e18, {"from": dai_liquidity})
    dai.transferFrom(dai_liquidity, gov, 300_000e18, {"from": dai_liquidity})
    dai.approve(gov, 1_000_000e18, {"from": gov})
    dai.transferFrom(gov, bob, 1000e18, {"from": gov})
    dai.transferFrom(gov, alice, 4000e18, {"from": gov})
    dai.transferFrom(gov, tinytim, 10e18, {"from": gov})
    dai.approve(vault, 1_000_000e18, {"from": bob})
    dai.approve(vault, 1_000_000e18, {"from": alice})
    dai.approve(vault, 1_000_000e18, {"from": tinytim})

    fxs.approve(fxs_liquidity, 1e30, {"from": fxs_liquidity})
    fxs.approve(fxs_liquidity, 1e30, {"from": token_owner})
    fxs.transferFrom(fxs_liquidity, gov, 1e24, {"from": fxs_liquidity})
    fxs.approve(gov, 1e30, {"from": gov})
    fxs.transferFrom(gov, fraxLock, 1e24, {"from": gov})

    # users deposit to vault
    vault.deposit(1000e18, {"from": bob})
    vault.deposit(4000e18, {"from": alice})
    vault.deposit(10e18, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    dai.transferFrom(dai_liquidity, strategy, 100e18, {"from": dai_liquidity})

    assert frax.balanceOf(strategy) == 0


    strategy.mintNFT({"from": gov})

    assert frax.balanceOf(strategy) > 0

    # First harvest
    strategy.harvest({"from": gov})

    assert frax.balanceOf(strategy) > 0
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_first_harvest = vault.pricePerShare()

    # 6 hours for pricepershare to go up, there should be profit
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)
    pps_after_second_harvest = vault.pricePerShare()
    assert pps_after_second_harvest > pps_after_first_harvest

    # 6 hours for pricepershare to go up
    strategy.harvest({"from": gov})
    chain.sleep(3600 * 24 * 1)
    chain.mine(1)
    chain.sleep(3600 * 1)
    chain.mine(1)

    alice_vault_balance = vault.balanceOf(alice)
    vault.withdraw(alice_vault_balance, alice, 75, {"from": alice})
    assert dai.balanceOf(alice) > 0
    assert dai.balanceOf(bob) == 0
    #assert frax.balanceOf(strategy) > 0

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert dai.balanceOf(bob) > 0
    #assert usdc.balanceOf(strategy) == 0

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert dai.balanceOf(tinytim) > 0
    #assert usdc.balanceOf(strategy) == 0

    # We should have made profit
    assert vault.pricePerShare() > 1e6
