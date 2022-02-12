import brownie
from brownie import Contract
from brownie import config
import math


def test_simple_harvest(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    amount,
    accounts,
    no_profit,
    frax,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2 ** 256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    assert strategy.nftIsLocked() == False

    # harvest, store asset amount
    chain.sleep(1)
    chain.mine(1)
    print(
        "Here's how much is in our NFT:",
        strategy.balanceOfNFT() / (10 ** token.decimals()),
    )
    strategy.harvest({"from": gov})
    chain.sleep(1)  # we currently lock for a day
    chain.mine(1)
    assert strategy.nftIsLocked() == True
    print(
        "Here's how much is in our NFT:",
        strategy.balanceOfNFT() / (10 ** token.decimals()),
    )
    old_assets = vault.totalAssets()
    print("Vault assets", old_assets / (10 ** token.decimals()))
    print("USDC strat", token.balanceOf(strategy) / (10 ** token.decimals()))
    print("FRAX strat", frax.balanceOf(strategy) / 1e18)
    print(
        "Strategy estimated assets",
        strategy.estimatedTotalAssets() / (10 ** token.decimals()),
    )

    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting vault total assets: ", old_assets / (10 ** token.decimals()))

    # simulate one day, since that's how long we lock for
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    tx = strategy.harvest({"from": gov})
    print("The is our harvest info:", tx.events["Harvested"])
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    if no_profit:
        assert math.isclose(new_assets, old_assets, abs_tol=10)
    else:
        assert new_assets >= old_assets
    print(
        "\nVault total assets after 1 harvest: ", new_assets / (10 ** token.decimals())
    )

    # Display estimated APR
    print(
        "\nEstimated APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate 1 day of earnings
    chain.mine(1)
    chain.sleep(86400)

    # withdraw and confirm our whale made money, or that we didn't lose more than dust


#     vault.withdraw({"from": whale})
#     assert token.balanceOf(whale) >= startingWhale
