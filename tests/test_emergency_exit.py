import math
import brownie
from brownie import Contract
from brownie import config


def test_emergency_exit(
    gov,
    token,
    vault,
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # set emergency and exit, then confirm that the strategy has no funds
    chain.sleep(86400)
    strategy.setEmergencyExit({"from": gov})

    # turn off healthcheck, we will have a loss on this harvest due to slippage
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    tx = strategy.harvest({"from": gov})
    print("This is our harvest detail:", tx.events["Harvested"])
    harvest_loss = tx.events["Harvested"]["loss"]
    print("This was our harvest loss:", harvest_loss / (10 ** token.decimals()))
    chain.sleep(1)
    assert strategy.estimatedTotalAssets() == 0

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    # this loss should have already been realized on harvest, though, and we removed all funds from strategy so no more slippage.
    tx = vault.withdraw({"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))

    # since we harvested on this loss (wasn't just a withdrawal) then we will see a decrease in share price
    assert vault.pricePerShare() < 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


def test_emergency_exit_with_profit(
    gov,
    token,
    vault,
    whale,
    strategy,
    chain,
    amount,
):
    ## deposit to the vault after approving. turn off health check since we're doing weird shit
    strategy.setDoHealthCheck(False, {"from": gov})
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # set emergency and exit, then confirm that the strategy has no funds
    donation = amount / 2
    chain.sleep(86400)
    token.transfer(strategy, donation, {"from": whale})
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.setEmergencyExit({"from": gov})
    chain.sleep(1)
    tx = strategy.harvest({"from": gov})
    print("This is our harvest detail:", tx.events["Harvested"])
    harvest_profit = tx.events["Harvested"]["profit"]
    print("This was our harvest profit:", harvest_profit / (10 ** token.decimals()))
    assert harvest_profit < donation
    chain.sleep(1)
    assert strategy.estimatedTotalAssets() == 0

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    # this loss should have already been realized on harvest, though, and we removed all funds from strategy so no more slippage.
    # make sure we account for all of the fees that went to the treasury (~10% of a huge profit)
    treasury = vault.rewards()
    fees = (vault.balanceOf(treasury) / (10 ** token.decimals())) * (
        vault.pricePerShare() / (10 ** token.decimals())
    )
    vault.withdraw({"from": whale})
    loss = (startingWhale - token.balanceOf(whale)) / (10 ** token.decimals())

    # check that our loss is ~10% of the donations
    print(
        "\n10% of our donation, should be close to losses:",
        donation * 0.1 / (10 ** token.decimals()),
    )
    print("Losses:", loss)

    # since we harvested on this loss (wasn't just a withdrawal), but also got a big donation, we should have a profit
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


def test_emergency_exit_with_no_gain_or_loss(
    gov,
    token,
    vault,
    whale,
    strategy,
    chain,
    amount,
):
    ## deposit to the vault after approving. turn off health check since we're doing weird shit
    strategy.setDoHealthCheck(False, {"from": gov})
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)

    # make sure we don't re-lock our NFT so we can send it away
    strategy.setManagerParams(False, False, 50, {"from": gov})
    strategy.harvest({"from": gov})
    chain.mine(1)
    chain.sleep(1)

    # send away all funds, will need to alter this based on strategy
    # profits from the last harvest should still be in the vault
    nft_contract = Contract("0xC36442b4a4522E871399CD717aBDD847Ab11FE88")
    nft_contract.transferFrom(strategy, whale, strategy.nftId(), {"from": strategy})
    token.transfer(whale, token.balanceOf(strategy), {"from": strategy})
    assert strategy.estimatedTotalAssets() == 0

    # reset our nftID to 1 since we sent away our NFT
    strategy.setGovParams(
        strategy.refer(),
        strategy.voter(),
        0,
        1,
        86400,
        strategy.nftUnlockTime(),
        {"from": gov},
    )

    # have our whale send in exactly our debtOutstanding
    whale_to_give = vault.debtOutstanding(strategy)
    token.transfer(strategy, whale_to_give, {"from": whale})

    # set emergency and exit, then confirm that the strategy has no funds
    strategy.setEmergencyExit({"from": gov})
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    assert strategy.estimatedTotalAssets() == 0

    # withdraw and confirm we made money, accounting for all of the funds we lost lol
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) + amount + whale_to_give >= startingWhale


def test_emergency_exit_withdraw_before_harvest(
    gov,
    token,
    vault,
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # set emergency and exit, then confirm that the strategy has no funds
    chain.sleep(86400)
    strategy.setEmergencyExit({"from": gov})
    
    # whale withdraws 25% of funds
    to_withdraw = amount / 4
    vault.withdraw(to_withdraw, {"from": whale})

    # turn off healthcheck, we will have a loss on this harvest due to slippage
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    tx = strategy.harvest({"from": gov})
    print("This is our harvest detail:", tx.events["Harvested"])
    harvest_loss = tx.events["Harvested"]["loss"]
    print("This was our harvest loss:", harvest_loss / (10 ** token.decimals()))
    chain.sleep(1)
    assert strategy.estimatedTotalAssets() == 0

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    # this loss should have already been realized on harvest, though, and we removed all funds from strategy so no more slippage.
    tx = vault.withdraw({"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))

    # since we harvested on this loss (wasn't just a withdrawal) then we will see a decrease in share price
    assert vault.pricePerShare() < 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))
