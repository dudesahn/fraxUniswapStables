import brownie
from brownie import Contract
from brownie import config
import math


def test_change_debt(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    amount,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # evaluate our current total assets
    old_assets = vault.totalAssets()
    startingStrategy = strategy.estimatedTotalAssets()
    print("\nStarting strategy assets", startingStrategy / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print(
        "Here's what our strategy owes the vault (debt):",
        vault.strategies(strategy)["totalDebt"] / (10 ** token.decimals()),
    )
    print("This is our slippage:", "{:.4%}".format(slippage))

    # debtRatio is in BPS (aka, max is 10,000, which represents 100%), and is a fraction of the funds that can be in the strategy
    currentDebt = 10000

    # reduce our debtRatio to 50%
    vault.updateStrategyDebtRatio(strategy, currentDebt / 2, {"from": gov})

    # sleep for a day to make sure our NFT is unlocked
    chain.sleep(86400)

    # turn off health check since we will take a loss here
    strategy.setDoHealthCheck(False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])
    chain.sleep(1)

    assert strategy.estimatedTotalAssets() <= startingStrategy
    print(
        "\nReduced strategy assets",
        strategy.estimatedTotalAssets() / (10 ** token.decimals()),
    )

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print(
        "Here's what our strategy owes the vault (debt):",
        vault.strategies(strategy)["totalDebt"] / (10 ** token.decimals()),
    )
    print("This is our slippage:", "{:.4%}".format(slippage))

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # set DebtRatio back to 100%
    vault.updateStrategyDebtRatio(strategy, currentDebt, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    print(
        "\nRe-increased strategy assets",
        strategy.estimatedTotalAssets() / (10 ** token.decimals()),
    )

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print(
        "Here's what our strategy owes the vault (debt):",
        vault.strategies(strategy)["totalDebt"] / (10 ** token.decimals()),
    )
    print("This is our slippage:", "{:.4%}".format(slippage))

    # evaluate our current total assets
    new_assets = vault.totalAssets()

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))

    # check that we haven't lost anything significant from slippage
    share_price = vault.pricePerShare() / (10 ** token.decimals())
    print("Vault share price", share_price)
    assert share_price > 0.995
