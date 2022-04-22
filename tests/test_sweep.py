import brownie
from brownie import Contract
from brownie import config


def test_sweep(
    gov,
    token,
    vault,
    strategist,
    whale,
    strategy,
    chain,
    strategist_ms,
    farmed,
    amount,
):

    ## deposit to the vault after approving
    token.approve(vault, 2**256 - 1, {"from": whale})
    vault.deposit(amount, {"from": whale})
    chain.sleep(1)
    strategy.harvest({"from": gov})
    chain.sleep(1)
    chain.mine(1)
    strategy.sweep(farmed, {"from": gov})

    # Strategy want token doesn't work
    startingWhale = token.balanceOf(whale)
    token.transfer(strategy.address, amount, {"from": whale})
    assert token.address == strategy.want()
    assert token.balanceOf(strategy) > 0
    #     with brownie.reverts("!want"):
    #         strategy.sweep(token, {"from": gov})

    # Vault share token doesn't work
    #     with brownie.reverts("!shares"):
    #         strategy.sweep(vault.address, {"from": gov})

    # we need to be able to sweep out the NFT if things go bad
    # free up our NFT
    strategy.setManagerParams(False, False, 50, {"from": gov})
    chain.sleep(86400)
    strategy.harvest({"from": gov})
    nft = strategy.nftId()
    nftContract = Contract("0xC36442b4a4522E871399CD717aBDD847Ab11FE88")
    assert nftContract.ownerOf(nft) == strategy.address

    # sweep it out
    strategy.sweepNFT(gov.address, {"from": gov})
    assert nftContract.ownerOf(nft) == gov.address
