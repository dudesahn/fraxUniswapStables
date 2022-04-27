import brownie
from brownie import Wei, accounts, Contract, config
import math


def test_cloning(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    keeper,
    rewards,
    chain,
    StrategyFraxUniswapFRAXUSDC,
    guardian,
    amount,
    tests_using_tenderly,
):
    # tenderly doesn't work for "with brownie.reverts"
    if tests_using_tenderly:
        ## clone our strategy
        tx = strategy.cloneFraxUni(
            vault,
            strategist,
            rewards,
            keeper,
            {"from": gov},
        )
        newStrategy = StrategyFraxUniswapFRAXUSDC.at(tx.return_value)
    else:
        # Shouldn't be able to call initialize again
        with brownie.reverts():
            strategy.initialize(
                vault,
                strategist,
                rewards,
                keeper,
                {"from": gov},
            )

        ## clone our strategy
        tx = strategy.cloneFraxUni(
            vault,
            strategist,
            rewards,
            keeper,
            {"from": gov},
        )
        newStrategy = StrategyFraxUniswapFRAXUSDC.at(tx.return_value)

        # Shouldn't be able to call initialize again
        with brownie.reverts():
            newStrategy.initialize(
                vault,
                strategist,
                rewards,
                keeper,
                {"from": gov},
            )

        ## shouldn't be able to clone a clone
        with brownie.reverts():
            newStrategy.cloneFraxUni(
                vault,
                strategist,
                rewards,
                keeper,
                {"from": gov},
            )

    # revoke and send all funds back to vault
    vault.revokeStrategy(strategy, {"from": gov})
    strategy.harvest({"from": gov})

    # attach our new strategy and approve it on the proxy
    vault.addStrategy(newStrategy, 10_000, 0, 2**256 - 1, 1_000, {"from": gov})

    # setup our NFT on our new strategy, IMPORTANT***
    token.transfer(newStrategy, 100 * (10 ** token.decimals()), {"from": whale})
    newStrategy.mintNFT({"from": gov})

    assert vault.withdrawalQueue(1) == newStrategy
    assert vault.strategies(newStrategy)["debtRatio"] == 10_000
    assert vault.withdrawalQueue(0) == strategy
    assert vault.strategies(strategy)["debtRatio"] == 0

    ## deposit to the vault after approving; this is basically just our simple_harvest test
    before_pps = vault.pricePerShare()
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})

    # harvest, store asset amount
    tx = newStrategy.harvest({"from": gov})
    old_assets_dai = vault.totalAssets()
    assert old_assets_dai > 0
    assert newStrategy.estimatedTotalAssets() > 0
    print("\nStarting Assets: ", old_assets_dai / (10 ** token.decimals()))

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest after a day, store new asset amount
    newStrategy.harvest({"from": gov})
    new_assets_dai = vault.totalAssets()
    # we can't use strategyEstimated Assets because the profits are sent to the vault
    # if we're not making profit, check that we didn't lose too much on conversions
    assert new_assets_dai >= old_assets_dai

    print("\nAssets after 2 days: ", new_assets_dai / (10 ** token.decimals()))

    # Display estimated APR
    print(
        "\nEstimated APR: ",
        "{:.2%}".format(
            ((new_assets_dai - old_assets_dai) * (365))
            / (newStrategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))
