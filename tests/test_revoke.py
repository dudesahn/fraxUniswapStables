import brownie
from brownie import Contract
from brownie import config
import math


def test_revoke_strategy_from_vault(
    gov,
    token,
    vault,
    whale,
    chain,
    strategy,
    amount,
    no_profit,
):

    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})

    # wait a day
    chain.sleep(86400)
    chain.mine(1)

    vaultAssets_starting = vault.totalAssets()
    vault_holdings_starting = token.balanceOf(vault)
    strategy_starting = strategy.estimatedTotalAssets()
    vault.revokeStrategy(strategy.address, {"from": gov})
    
    # turn off health check since we will be taking a loss
    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("This is our harvest info after revoking:", harvest.events["Harvested"])
    chain.sleep(1)
    vaultAssets_after_revoke = vault.totalAssets()
    
    # our share price should be below 1 since we took a loss only
    assert vault.pricePerShare() < 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))

    # confirm we made money, or at least that we have lost less than 1% due to slippage
    assert vaultAssets_after_revoke >= vaultAssets_starting * 0.99
    assert token.balanceOf(vault) >= vault_holdings_starting + strategy_starting
    assert strategy.estimatedTotalAssets() == 0

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    # these losses will be socialized to the vault since we harvested first
    tx = vault.withdraw({"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
