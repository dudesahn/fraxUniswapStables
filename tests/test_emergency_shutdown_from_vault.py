import brownie
from brownie import Contract
from brownie import config
import math


def test_emergency_shutdown_from_vault(
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

    # simulate one day of earnings
    chain.sleep(86400)

    # this is a profitable harvest
    chain.mine(1)
    tx = strategy.harvest({"from": gov})
    profit = tx.events["Harvested"]["profit"]
    assert profit > 0

    # simulate one day of earnings
    chain.sleep(86400)

    # set emergency and exit, then confirm that the strategy has no funds
    vault.setEmergencyShutdown(True, {"from": gov})
    chain.sleep(1)
    # turn off health check since we will be taking a loss from big slippage
    strategy.setDoHealthCheck(False, {"from": gov})
    tx = strategy.harvest({"from": gov})
    loss = tx.events["Harvested"]["loss"]
    assert loss > 0
    chain.sleep(1)
    assert math.isclose(strategy.estimatedTotalAssets(), 0, abs_tol=5)

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # since we have a few profitable harvests, even though our whale burns all of his shares, treasury/strategist will still hold 20%
    # of the profitable harvest #1, thus, share price below 0
    # this loss should have already been realized on harvest, and we removed all funds from strategy so no more slippage.
    tx = vault.withdraw({"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() < 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))
