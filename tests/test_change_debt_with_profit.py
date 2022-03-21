import brownie
from brownie import chain
import math


def test_change_debt_with_profit(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    amount,
    no_profit,
    is_slippery,
):

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    # sleep for a day to make sure our NFT is unlocked
    chain.sleep(86400)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    prev_params = vault.strategies(strategy)

    currentDebt = vault.strategies(strategy)["debtRatio"]
    vault.updateStrategyDebtRatio(strategy, currentDebt / 2, {"from": gov})
    assert vault.strategies(strategy)["debtRatio"] == 5000

    # turn off health check since we're about to take a big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    print("\nThe is our harvest info:", harvest.events["Harvested"])

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    new_params = vault.strategies(strategy)

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that we've recorded a gain
    assert profit > 0

    # check to make sure that our debtRatio is about half of our previous debt
    assert new_params["debtRatio"] == currentDebt / 2

    # check that we didn't add any more loss, or at least no more than 10 wei if we get slippage on deposit/withdrawal
    if is_slippery:
        assert math.isclose(
            new_params["totalLoss"], prev_params["totalLoss"], abs_tol=10
        )
    else:
        assert new_params["totalLoss"] == prev_params["totalLoss"]

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within 1 token)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=1e18,
    )
