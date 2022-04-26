import brownie
from brownie import Contract
from brownie import config
import math


def test_odds_and_ends(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    StrategyFraxUniswapDAI,
    amount,
    healthCheck,
):

    ## deposit to the vault after approving. turn off health check before each harvest since we're doing weird shit
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)

    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # we can also withdraw from an empty vault as well, but make sure we're okay with taking a loss
    vault.withdraw(amount, whale, 10000, {"from": whale})

    # we can try migrating too!
    # deploy our new strategy
    new_strategy = strategist.deploy(
        StrategyFraxUniswapDAI,
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

    # update our debtRatio, the big withdrawal and loss previously reduced the debtRatio on the old strategy
    vault.updateStrategyDebtRatio(new_strategy, 10000, {"from": gov})

    # check that we updated our old nftId to 1
    assert strategy.nftId() == 1

    # assert that our old strategy is empty
    updated_total_old = strategy.estimatedTotalAssets()
    assert updated_total_old == 0

    # update our new strategy so it knows what our NFT id is
    new_strategy.setGovParams(
        "0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde",
        "0x93A62dA5a14C80f265DAbC077fCEE437B1a0Efde",
        0,
        nft_id,
        86400,
        0,
        {"from": gov},
    )

    # since we sent away our NFT, we need to mint another one
    token.transfer(new_strategy, 100e6, {"from": whale})
    new_strategy.mintNFT({"from": gov})
    chain.mine(1)
    chain.sleep(1)

    assert new_strategy.nftId() != 1

    # we should already be able to see our money just fine since it's almost all in the LP
    new_strat_balance = new_strategy.estimatedTotalAssets()

    # confirm we made money, or at least that we have about the same
    assert new_strat_balance >= total_old

    startingVault = vault.totalAssets()
    print("\nVault starting assets with new strategy: ", startingVault)

    # harvest to get our NFT staked again
    new_strategy.setDoHealthCheck(False, {"from": gov})
    tx = new_strategy.harvest({"from": gov})
    print("This is our harvest info after adding our new NFT:", tx.events["Harvested"])
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
    assert vaultAssets_2 > startingVault

    print("\nAssets after 1 day harvest: ", vaultAssets_2)

    # check our oracle
    one_eth_in_want = strategy.ethToWant(1e18)
    print("This is how much want one ETH buys:", one_eth_in_want)
    zero_eth_in_want = strategy.ethToWant(0)

    # check our views
    strategy.apiVersion()
    strategy.isActive()

    # tend stuff
    chain.sleep(1)
    strategy.tend({"from": gov})
    chain.sleep(1)
    strategy.tendTrigger(0, {"from": gov})


def test_odds_and_ends_2(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)

    strategy.setEmergencyExit({"from": gov})

    chain.sleep(1)
    strategy.setDoHealthCheck(False, {"from": gov})
    strategy.harvest({"from": gov})
    chain.sleep(1)

    # we can also withdraw from an empty vault as well
    vault.withdraw({"from": whale})


def test_odds_and_ends_liquidatePosition(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    amount,
):
    ## deposit to the vault after approving
    startingWhale = token.balanceOf(whale)
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # harvest, store asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting Assets: ", old_assets / 1e18)

    # simulate one day of earnings
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    assert new_assets >= old_assets or math.isclose(new_assets, old_assets, abs_tol=5)
    print("\nAssets after 1 day: ", new_assets / 1e18)

    # Display estimated APR
    print(
        "\nEstimated APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate a day of waiting for share price to bump back up
    chain.sleep(86400)
    chain.mine(1)

    # transfer funds to our strategy so we have enough for our withdrawal
    to_transfer = amount * 1.1
    token.transfer(strategy, to_transfer, {"from": whale})

    # withdraw and confirm we made money, or at least that we have about the same
    vault.withdraw({"from": whale})
    assert token.balanceOf(whale) + to_transfer >= startingWhale


def test_odds_and_ends_rekt(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)

    # turn off health check since we'll have a big loss, set debtRatio to 0 so we fully realize the loss
    vault.updateStrategyDebtRatio(strategy, 0, {"from": gov})
    strategy.setDoHealthCheck(False, {"from": gov})
    chain.sleep(1)
    tx = strategy.harvest({"from": gov})
    chain.sleep(1)

    # we can also withdraw from an empty vault as well
    # we don't need to set any slippage as long as we've already booked the loss with a harvest
    vault.withdraw({"from": whale})


# goal of this one is to hit a withdraw when we don't have any staked assets
def test_odds_and_ends_liquidate_rekt(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
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

    # simulate 1 day of earnings
    chain.sleep(86400)
    chain.mine(1)
    chain.sleep(1)

    # we can also withdraw from an empty vault as well, but make sure we're okay with losing 100%
    vault.withdraw(amount, whale, 10000, {"from": whale})


def test_weird_reverts_and_trigger(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    other_vault_strategy,
    amount,
):

    # only vault can call this
    with brownie.reverts():
        strategy.migrate(strategist_ms, {"from": gov})

    # can't migrate to a different vault
    with brownie.reverts():
        vault.migrateStrategy(strategy, other_vault_strategy, {"from": gov})

    # can't withdraw from a non-vault address
    with brownie.reverts():
        strategy.withdraw(1e18, {"from": gov})

    # can't do health check with a non-health check contract
    with brownie.reverts():
        strategy.withdraw(1e18, {"from": gov})
