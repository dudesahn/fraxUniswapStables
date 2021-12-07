import pytest
import brownie
from brownie import Wei, accounts, Contract, config


@pytest.mark.require_network("mainnet-fork")
def test_clone(
    StrategyPoolTogether,
    chain,
    gov,
    unitoken,
    comp_strategy,
    uni_vault,
    uni_want_pool,
    pool_token,
    uni,
    uni_bonus,
    uni_faucet,
    uni_ticket,
    uni_liquidity,
    alice,
):

    # Shouldn't be able to call initialize again
    with brownie.reverts():
        comp_strategy.initialize(
            uni_vault,
            gov,
            gov,
            gov,
            uni_want_pool,
            pool_token,
            uni,
            uni_bonus,
            uni_faucet,
            uni_ticket,
            {"from": gov},
        )

    # Clone the strategy
    tx = comp_strategy.clonePoolTogether(
        uni_vault,
        gov,
        gov,
        gov,
        uni_want_pool,
        pool_token,
        uni,
        uni_bonus,
        uni_faucet,
        uni_ticket,
        {"from": gov},
    )
    uni_strategy = StrategyPoolTogether.at(tx.return_value)
    assert uni_strategy.percentKeep() == 1000

    # Shouldn't be able to call initialize again
    with brownie.reverts():
        uni_strategy.initialize(
            uni_vault,
            gov,
            gov,
            gov,
            uni_want_pool,
            pool_token,
            uni,
            uni_bonus,
            uni_faucet,
            uni_ticket,
            {"from": gov},
        )

    uni_vault.addStrategy(uni_strategy, 10_000, 0, 2 ** 256 - 1, 1_000, {"from": gov})

    # Try a deposit and harvest
    unitoken.transfer(alice, Wei("100 ether"), {"from": uni_liquidity})
    unitoken.approve(uni_vault, 2 ** 256 - 1, {"from": alice})
    uni_vault.deposit({"from": alice})

    # Invest!
    uni_strategy.harvest({"from": gov})

    # Wait one week
    chain.sleep(604801)
    chain.mine()

    # Get profits and withdraw
    uni_strategy.harvest({"from": gov})
    chain.sleep(604801)
    chain.mine()

    uni_vault.withdraw({"from": alice})
    assert unitoken.balanceOf(alice) > Wei("100 ether")