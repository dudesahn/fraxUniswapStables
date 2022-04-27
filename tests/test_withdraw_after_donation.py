import brownie
from brownie import chain, Contract
import math

# lower debtRatio to 50%, donate, withdraw less than the donation, then harvest
def test_withdraw_after_donation_1(
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

    prev_params = vault.strategies(strategy).dict()

    currentDebt = vault.strategies(strategy)["debtRatio"]
    vault.updateStrategyDebtRatio(strategy, currentDebt / 2, {"from": gov})
    assert vault.strategies(strategy)["debtRatio"] == 5000

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraw half of his donation, this ensures that we test withdrawing without pulling from the staked balance
    vault.withdraw(donation / 2, {"from": whale})

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep so our funds unlock
    chain.sleep(86400)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )

    # withdraw and check on our losses (due to slippage on big swaps in/out, also our donation)
    # even though we still have funds in strategy
    tx = vault.withdraw({"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print(
        "Losses from withdrawal slippage and donation:", loss / (10 ** token.decimals())
    )
    print(
        "Vault total assets, this should be similar to the loss we experienced:",
        vault.totalAssets() / (10 ** token.decimals()),
    )

    # since we harvested on this loss (wasn't just a withdrawal), but also got a big donation, we should have a profit
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


# lower debtRatio to 0, donate, withdraw less than the donation, then harvest
def test_withdraw_after_donation_2(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()

    currentDebt = vault.strategies(strategy)["debtRatio"]
    vault.updateStrategyDebtRatio(strategy, 0, {"from": gov})
    assert vault.strategies(strategy)["debtRatio"] == 0

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraw half of his donation, this ensures that we test withdrawing without pulling from the staked balance
    vault.withdraw(donation / 2, {"from": whale})

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )


# lower debtRatio to 0, donate, withdraw more than the donation, then harvest
def test_withdraw_after_donation_3(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()

    currentDebt = vault.strategies(strategy)["debtRatio"]
    vault.updateStrategyDebtRatio(strategy, 0, {"from": gov})
    assert vault.strategies(strategy)["debtRatio"] == 0

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraws more than his donation, ensuring we pull from strategy
    # set loss parameter based on our strategy's slippage, we will lose some on slippage that is assessed on withdrawal
    vault.withdraw(
        donation + donation / 2, whale, strategy.slippageMax(), {"from": whale}
    )

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )


# lower debtRatio to 50%, donate, withdraw more than the donation, then harvest
def test_withdraw_after_donation_4(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()

    currentDebt = vault.strategies(strategy)["debtRatio"]
    vault.updateStrategyDebtRatio(strategy, currentDebt / 2, {"from": gov})
    assert vault.strategies(strategy)["debtRatio"] == 5000

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraws more than his donation, ensuring we pull from strategy
    # set loss parameter based on our strategy's slippage, we will lose some on slippage that is assessed on withdrawal
    vault.withdraw(
        donation + donation / 2, whale, strategy.slippageMax(), {"from": whale}
    )

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # check to make sure that our debtRatio is about half of our previous debt
    assert math.isclose(new_params["debtRatio"], currentDebt / 2, abs_tol=5)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )


# donate, withdraw more than the donation, then harvest
def test_withdraw_after_donation_5(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # have our whale withdraws more than his donation, ensuring we pull from strategy
    # set loss parameter based on our strategy's slippage, we will lose some on slippage that is assessed on withdrawal
    vault.withdraw(
        donation + donation / 2, whale, strategy.slippageMax(), {"from": whale}
    )

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )


# donate, withdraw less than the donation, then harvest
def test_withdraw_after_donation_6(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # have our whale withdraws more than his donation, ensuring we pull from strategy
    vault.withdraw(donation / 2, {"from": whale})

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # sleep 10 hours to increase our credit available for last assert at the bottom.
    chain.sleep(60 * 60 * 10)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)

    # assert that our vault total assets, multiplied by our debtRatio, is about equal to our estimated total assets plus credit available (within our slippage)
    # we multiply this by the debtRatio of our strategy out of 10_000 total
    # we sleep 10 hours above specifically for this check
    assert math.isclose(
        vault.totalAssets() * new_params["debtRatio"] / 10_000,
        strategy.estimatedTotalAssets() + vault.creditAvailable(strategy),
        abs_tol=(vault.totalAssets() * (10000 - strategy.slippageMax())),
    )


# lower debtRatio to 0, donate, withdraw more than the donation, then harvest
def test_withdraw_after_donation_7(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()
    prev_assets = vault.totalAssets()

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraws more than his donation, ensuring we pull from strategy
    # set 1% loss parameter, we will lose some on slippage that is assessed on withdrawal
    withdrawal = donation + donation / 2
    vault.withdraw(withdrawal, whale, 100, {"from": whale})

    # try to check our true holdings to see this profit
    # if we're going to do this method, then we need to set emergencyExit to make sure we get everything out
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})
    strategy.setEmergencyExit({"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # check everywhere to make sure we emptied out the strategy, sometimes need a second harvest
    if strategy.estimatedTotalAssets() > 0:
        strategy.setDoHealthCheck(False, {"from": gov})
        chain.sleep(1)
        harvest = strategy.harvest({"from": gov})
        new_params = vault.strategies(strategy).dict()
        assert strategy.estimatedTotalAssets() == 0
    assert token.balanceOf(strategy) == 0
    current_assets = vault.totalAssets()

    # assert that our total assets have gone up or stayed the same when accounting for the donation and withdrawal, and our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert current_assets >= (donation * slippage) - withdrawal + prev_assets

    new_params = vault.strategies(strategy).dict()

    # assert that our strategy has no debt
    assert new_params["totalDebt"] == 0
    assert vault.totalDebt() == 0

    # sleep to allow share price to normalize
    chain.sleep(86400)
    chain.mine(1)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)


# lower debtRatio to 0, donate, withdraw less than the donation, then harvest
def test_withdraw_after_donation_8(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    prev_params = vault.strategies(strategy).dict()
    prev_assets = vault.totalAssets()

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # our whale donates dust to the vault, what a nice person!
    donation = amount / 2
    token.transfer(strategy, donation, {"from": whale})

    # have our whale withdraws less than his donation
    withdrawal = donation / 2
    vault.withdraw(withdrawal, {"from": whale})

    # try to check our true holdings to see this profit
    # if we're going to do this method, then we need to set emergencyExit to make sure we get everything out
    tx = strategy.setManagerParams(True, True, 50, {"from": gov})
    strategy.setEmergencyExit({"from": gov})

    # turn off health check since we just took big profit
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    new_params = vault.strategies(strategy).dict()

    # check everywhere to make sure we emptied out the strategy, sometimes need a second harvest
#     if strategy.estimatedTotalAssets() > 0:
#         strategy.setDoHealthCheck(False, {"from": gov})
#         chain.sleep(1)
#         harvest = strategy.harvest({"from": gov})
#         new_params = vault.strategies(strategy).dict()
    assert strategy.estimatedTotalAssets() == 0
    assert token.balanceOf(strategy) == 0
    current_assets = vault.totalAssets()

    # assert that our total assets have gone up or stayed the same when accounting for the donation and withdrawal, and our preset slippage
    slippage = strategy.slippageMax() / 10000
    assert current_assets >= (donation * slippage) - withdrawal + prev_assets

    new_params = vault.strategies(strategy).dict()

    # assert that our strategy has no debt
    assert new_params["totalDebt"] == 0
    assert vault.totalDebt() == 0

    # sleep to allow share price to normalize
    chain.sleep(86400)
    chain.mine(1)

    profit = new_params["totalGain"] - prev_params["totalGain"]

    # check that our gain is greater than our donation, with our preset slippage
    assert profit >= donation * slippage
    assert profit >= 0

    # check that we didn't add more than our slippage
    assert new_params["totalLoss"] <= vault.totalAssets() * (1 - slippage)
