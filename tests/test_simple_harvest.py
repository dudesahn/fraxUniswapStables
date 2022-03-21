import brownie
from brownie import Contract
from brownie import config
import math
from eth_abi.packed import encode_abi_packed
import pytest


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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # harvest, store asset amount
    chain.sleep(1)
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    strategy.harvest({"from": gov})
    chain.sleep(1)
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting vault total assets: ", old_assets / (10 ** token.decimals()))

    # simulate one day, since that's how long we lock for
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])
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

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # Display estimated APR
    print(
        "\nEstimated APR: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate 1 day of earnings so our LP will unlock
    chain.mine(1)
    chain.sleep(86400)

    # turn off auto-restake since we want to withdraw after this harvest
    strategy.setManagerParams(False, False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])

    # simulate 1 day for share price to rise
    chain.mine(1)
    chain.sleep(86400)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale)
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


# simulate some trading in the uniswap pool with our whale
def test_simple_harvest_with_uni_fees(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # harvest, store asset amount
    chain.sleep(1)
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    strategy.harvest({"from": gov})
    chain.sleep(1)  # we currently lock for a day
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # have our whale trade in the uniV3 pool a bunch to generate some fees
    uni_values_token = [token.address, 500, frax.address]
    uni_values_frax = [frax.address, 500, token.address]
    uni_types = ("address", "uint24", "address")
    packed_path_token = encode_abi_packed(uni_types, uni_values_token)
    packed_path_frax = encode_abi_packed(uni_types, uni_values_frax)
    uni_router = Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564")
    token.approve(uni_router, 2**256 - 1, {"from": whale})
    frax.approve(uni_router, 2**256 - 1, {"from": whale})
    print("\nLet's do some trading!")
    for i in range(3):
        to_swap = (
            token.balanceOf(whale) / 5
        )  # whale has like $200m USDC, we don't need to do that lol
        exact_input = (packed_path_token, whale.address, 2**256 - 1, to_swap, 1)
        uni_router.exactInput(exact_input, {"from": whale})
        chain.sleep(1)
        chain.mine(1)
        to_swap = frax.balanceOf(whale)
        exact_input_frax = (packed_path_frax, whale.address, 2**256 - 1, to_swap, 1)
        uni_router.exactInput(exact_input_frax, {"from": whale})
        print("Done with round", i)
        chain.sleep(1)
        chain.mine(1)

    tradingLosses = newWhale - token.balanceOf(whale)
    print("USDC lost trading", tradingLosses / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting vault total assets: ", old_assets / (10 ** token.decimals()))

    # simulate one day, since that's how long we lock for
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    if no_profit:
        assert math.isclose(new_assets, old_assets, abs_tol=10)
    else:
        assert new_assets >= old_assets
    print("\nVault total assets after harvest: ", new_assets / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # Display estimated APR
    print(
        "\nEstimated APR with trading fees: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate 1 day of earnings so our LP will unlock
    chain.sleep(86400)
    chain.mine(1)

    # turn off auto-restake since we want to withdraw after this harvest
    strategy.setManagerParams(False, False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("\nThe is our harvest info:", harvest.events["Harvested"])

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # simulate 1 day for share price to rise
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale) - tradingLosses
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


# simulate some trading in the uniswap pool with our whale to unbalance it
# @pytest.mark.skip(reason="currently crashes testing")
def test_simple_harvest_imbalanced_pool(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # harvest, store asset amount
    chain.sleep(1)
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    strategy.harvest({"from": gov})
    chain.sleep(1)  # we currently lock for a day
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # have our whale trade in the uniV3 pool a bunch to generate some fees
    uni_values_token = [token.address, 500, frax.address]
    uni_values_frax = [frax.address, 500, token.address]
    uni_types = ("address", "uint24", "address")
    packed_path_token = encode_abi_packed(uni_types, uni_values_token)
    packed_path_frax = encode_abi_packed(uni_types, uni_values_frax)
    uni_router = Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564")
    token.approve(uni_router, 2**256 - 1, {"from": whale})
    frax.approve(uni_router, 2**256 - 1, {"from": whale})
    print("\nLet's do some trading!")
    to_swap = (
        token.balanceOf(whale) / 5
    )  # whale has like $200m USDC, we don't need to do that lol
    for i in range(2):
        exact_input = (packed_path_token, whale.address, 2**256 - 1, to_swap, 1)
        uni_router.exactInput(exact_input, {"from": whale})
        chain.sleep(1)
        chain.mine(1)
        print("Done with round", i)

    tradingLosses = newWhale - token.balanceOf(whale)
    print("USDC lost trading", tradingLosses / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting vault total assets: ", old_assets / (10 ** token.decimals()))

    # simulate one day, since that's how long we lock for
    chain.sleep(86400)
    chain.mine(1)

    # harvest, store new asset amount
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    if no_profit:
        assert math.isclose(new_assets, old_assets, abs_tol=10)
    else:
        assert new_assets >= old_assets
    print("\nVault total assets after harvest: ", new_assets / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # Display estimated APR
    print(
        "\nEstimated APR with trading fees: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate 1 day of earnings so our LP will unlock
    chain.sleep(86400)
    chain.mine(1)

    # turn off auto-restake since we want to withdraw after this harvest
    strategy.setManagerParams(False, False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("\nThe is our harvest info:", harvest.events["Harvested"])

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # simulate 1 day for share price to rise
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale) - tradingLosses
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))


# simulate some trading in the uniswap pool with our whale to unbalance it, then try to assess where we are with checkTrueHoldings
# @pytest.mark.skip(reason="currently reverts in testing")
def test_simple_harvest_imbalanced_pool_check_holdings(
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
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    newWhale = token.balanceOf(whale)

    # harvest, store asset amount
    chain.sleep(1)
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    strategy.harvest({"from": gov})
    chain.sleep(1)  # we currently lock for a day
    chain.mine(1)

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # have our whale trade in the uniV3 pool a bunch to generate some fees
    uni_values_token = [token.address, 500, frax.address]
    uni_values_frax = [frax.address, 500, token.address]
    uni_types = ("address", "uint24", "address")
    packed_path_token = encode_abi_packed(uni_types, uni_values_token)
    packed_path_frax = encode_abi_packed(uni_types, uni_values_frax)
    uni_router = Contract("0xE592427A0AEce92De3Edee1F18E0157C05861564")
    token.approve(uni_router, 2**256 - 1, {"from": whale})
    frax.approve(uni_router, 2**256 - 1, {"from": whale})
    print("\nLet's do some trading!")
    to_swap = (
        token.balanceOf(whale) / 5
    )  # whale has like $200m USDC, we don't need to do that lol
    for i in range(2):
        exact_input = (packed_path_token, whale.address, 2**256 - 1, to_swap, 1)
        uni_router.exactInput(exact_input, {"from": whale})
        chain.sleep(1)
        chain.mine(1)
        print("Done with round", i)

    tradingLosses = newWhale - token.balanceOf(whale)
    print("USDC lost trading", tradingLosses / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    old_assets = vault.totalAssets()
    assert old_assets > 0
    assert strategy.estimatedTotalAssets() > 0
    print("\nStarting vault total assets: ", old_assets / (10 ** token.decimals()))

    # simulate one day, since that's how long we lock for
    chain.sleep(86400)
    chain.mine(1)

    # try to check our true holdings to see this profit
    tx = strategy.setManagerParams(True, True, {"from": gov})

    # harvest, store new asset amount
    chain.sleep(1)
    harvest = strategy.harvest({"from": gov})
    print("The is our harvest info:", harvest.events["Harvested"])
    chain.sleep(1)
    new_assets = vault.totalAssets()
    # confirm we made money, or at least that we have about the same
    if no_profit:
        assert math.isclose(new_assets, old_assets, abs_tol=10)
    else:
        assert new_assets >= old_assets
    print("\nVault total assets after harvest: ", new_assets / (10 ** token.decimals()))

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # Display estimated APR
    print(
        "\nEstimated APR with trading fees: ",
        "{:.2%}".format(
            ((new_assets - old_assets) * (365)) / (strategy.estimatedTotalAssets())
        ),
    )

    # simulate 1 day of earnings so our LP will unlock
    chain.sleep(86400)
    chain.mine(1)

    # turn off auto-restake since we want to withdraw after this harvest
    strategy.setManagerParams(False, False, {"from": gov})
    harvest = strategy.harvest({"from": gov})
    print("\nThe is our harvest info:", harvest.events["Harvested"])

    # check on our NFT LP
    real_balance = strategy.balanceOfNFTpessimistic() / (10 ** token.decimals())
    virtual_balance = strategy.balanceOfNFToptimistic() / (10 ** token.decimals())
    slippage = (virtual_balance - real_balance) / real_balance
    print("\nHere's how much is in our NFT (pessimistic):", real_balance)
    print("Here's how much is in our NFT (optimistic):", virtual_balance)
    print("This is our slippage:", "{:.4%}".format(slippage))

    # simulate 1 day for share price to rise
    chain.sleep(86400)
    chain.mine(1)

    # withdraw and check on our losses (due to slippage on big swaps in/out)
    tx = vault.withdraw(amount, whale, 10_000, {"from": whale})
    loss = startingWhale - token.balanceOf(whale) - tradingLosses
    print("Losses from withdrawal slippage:", loss / (10 ** token.decimals()))
    assert vault.pricePerShare() > 10 ** token.decimals()
    print("Vault share price", vault.pricePerShare() / (10 ** token.decimals()))
