# TODO: Add tests here that show the normal operation of this strategy
#       Suggestions to include:
#           - strategy loading and unloading (via Vault addStrategy/revokeStrategy)
#           - change in loading (from low to high and high to low)
#           - strategy operation at different loading levels (anticipated and "extreme")

import pytest

from brownie import Wei, accounts, Contract, config
from brownie import StrategyFraxUniswapUSDC


@pytest.mark.require_network("mainnet-fork")
def test_operation(
    chain,
    vault,
    strategy,
    frax,
    usdc,
    usdc_liquidity,
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
    usdc.approve(usdc_liquidity, 1_000_000_000000, {"from": usdc_liquidity})
    usdc.transferFrom(usdc_liquidity, gov, 300_000_000000, {"from": usdc_liquidity})
    usdc.approve(gov, 1_000_000_000000, {"from": gov})
    usdc.transferFrom(gov, bob, 1000_000000, {"from": gov})
    usdc.transferFrom(gov, alice, 4000_000000, {"from": gov})
    usdc.transferFrom(gov, tinytim, 10_000000, {"from": gov})
    usdc.approve(vault, 1_000_000_000000, {"from": bob})
    usdc.approve(vault, 1_000_000_000000, {"from": alice})
    usdc.approve(vault, 1_000_000_000000, {"from": tinytim})

    fxs.approve(fxs_liquidity, 1e30, {"from": fxs_liquidity})
    fxs.approve(fxs_liquidity, 1e30, {"from": token_owner})
    fxs.transferFrom(fxs_liquidity, gov, 1e24, {"from": fxs_liquidity})
    fxs.approve(gov, 1e30, {"from": gov})
    fxs.transferFrom(gov, fraxLock, 1e24, {"from": gov})

    # users deposit to vault
    vault.deposit(1000_000_000, {"from": bob})
    vault.deposit(4000_000_000, {"from": alice})
    vault.deposit(10_000_000, {"from": tinytim})

    vault.setManagementFee(0, {"from": gov})
    vault.setPerformanceFee(0, {"from": gov})

    usdc.transferFrom(usdc_liquidity, strategy, 100_000000, {"from": usdc_liquidity})

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
    assert usdc.balanceOf(alice) > 0
    assert usdc.balanceOf(bob) == 0
    #assert frax.balanceOf(strategy) > 0

    bob_vault_balance = vault.balanceOf(bob)
    vault.withdraw(bob_vault_balance, bob, 75, {"from": bob})
    assert usdc.balanceOf(bob) > 0
    #assert usdc.balanceOf(strategy) == 0

    tt_vault_balance = vault.balanceOf(tinytim)
    vault.withdraw(tt_vault_balance, tinytim, 75, {"from": tinytim})
    assert usdc.balanceOf(tinytim) > 0
    #assert usdc.balanceOf(strategy) == 0

    # We should have made profit
    assert vault.pricePerShare() > 1e6
