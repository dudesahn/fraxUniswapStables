import brownie
from brownie import Contract
from brownie import config
import math

# test all of our harvest triggers
def test_triggers(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    amount,
    gas_oracle,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)
    starting_assets = vault.totalAssets()
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # simulate a day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest should trigger true; our NFT is unlocked
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be true.", tx)
    assert tx == True

    # harvest
    strategy.harvest({"from": gov})

    # harvest should trigger false; our NFT is locked
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be false.", tx)
    assert tx == False

    # try our manual trigger
    strategy.setForceHarvestTriggerOnce(True, {"from": gov})

    # harvest should trigger true
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be true.", tx)
    assert tx == True

    # harvest should trigger false due to high gas price
    gas_oracle.setMaxAcceptableBaseFee(1 * 1e9, {"from": strategist_ms})
    tx = strategy.harvestTrigger(0, {"from": gov})
    print("\nShould we harvest? Should be false.", tx)
    assert tx == False
    gas_oracle.setMaxAcceptableBaseFee(20000 * 1e9, {"from": strategist_ms})

    # simulate 1 more day to free up our NFT
    chain.sleep(86400)
    chain.mine(1)

    # turn off auto-locking
    strategy.setManagerParams(False, False, 50, {"from": gov})
    strategy.harvest({"from": gov})

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))
