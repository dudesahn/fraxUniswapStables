import brownie
from brownie import Contract
from brownie import config
import math

# test that we can migrate from an old strategy to a new one and that it works normally
def test_migration(
    StrategyFraxUniswapUSDC,
    gov,
    token,
    vault,
    guardian,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    healthCheck,
    amount,
    is_slippery,
    no_profit,
):

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # deploy our new strategy
    new_strategy = strategist.deploy(
        StrategyFraxUniswapUSDC,
        vault,
    )
    total_old = strategy.estimatedTotalAssets()

    # simulate 1 day of earnings, let our NFT unlock
    chain.sleep(86400)
    chain.mine(1)

    # store our NFT id
    nft_id = strategy.nftId()

    # migrate our old strategy
    vault.migrateStrategy(strategy, new_strategy, {"from": gov})
    new_strategy.setHealthCheck(healthCheck, {"from": gov})
    new_strategy.setDoHealthCheck(True, {"from": gov})

    # check that we updated our old nftId to 1
    assert strategy.nftId() == 1

    # assert that our old strategy is empty
    updated_total_old = strategy.estimatedTotalAssets()
    assert updated_total_old == 0

    # update our new strategy so it knows what our NFT id is, and our NFT is unlocked
    new_strategy.setGovParams(
        "0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde",
        "0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde",
        0,
        nft_id,
        86400,
        0,
        {"from": gov},
    )
    chain.mine(1)
    chain.sleep(1)

    assert new_strategy.nftId() == nft_id

    # we should already be able to see our money just fine since it's almost all in the LP
    new_strat_balance = new_strategy.estimatedTotalAssets()

    # confirm we made money, or at least that we have about the same
    if is_slippery and no_profit:
        assert math.isclose(new_strat_balance, total_old, abs_tol=10)
    else:
        assert new_strat_balance >= total_old

    startingVault = vault.totalAssets()
    print("\nVault starting assets with new strategy: ", startingVault)

    # harvest to get our NFT staked again
    new_strategy.harvest({"from": gov})
    chain.mine(1)
    chain.sleep(1)

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # Test out our migrated strategy, confirm we're making a profit
    tx = new_strategy.harvest({"from": gov})
    profit = tx.events["Harvested"]["profit"]
    print("This is our harvest info:", tx.events["Harvested"])
    assert profit > 0
    vaultAssets_2 = vault.totalAssets()

    # confirm we made money, or at least that we have about the same
    if is_slippery and no_profit:
        assert math.isclose(vaultAssets_2, startingVault, abs_tol=10)
    else:
        assert vaultAssets_2 > startingVault

    print("\nAssets after 1 day harvest: ", vaultAssets_2)
