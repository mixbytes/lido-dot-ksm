# Lido KSM/DOT Liquid Staking Protocol

The Lido KSM/DOT Liquid Staking Protocol, built on Kusama(Polkadot) chain, allows their users to earn staking rewards on the Kusama chain without locking KSM or maintaining staking infrastructure.

Users can deposit KSM to the Lido smart contract and receive LKSM tokens in return. The smart contract then stakes tokens with the DAO-picked node operators. Users' deposited funds are pooled by the DAO, node operators never have direct access to the users' assets.

Unlike staked KSM directly on Kusama network, the LKSM token is free from the limitations associated with a lack of liquidity and can be transferred at any time. 
The LKSM token balance corresponds to the amount of Kusama chain KSM that the holder could withdraw.

Before getting started with this repo, please read:

## Contracts

Most of the protocol is implemented as a set of smart contracts.
These contracts are located in the [contracts/](contracts/) directory. 
### [Lido](contracts/Lido.sol)

Lido is the core contract which acts as a liquid staking pool. 
The contract is responsible for KSM deposits and withdrawals, minting and burning liquid tokens, delegating funds to node operators, applying fees, and accepting updates from the oracle contract. .
Lido also acts as an ERC20 token which represents staked KSM, LKSM. Tokens are minted upon deposit and burned when redeemed. 
LKSM tokens are pegged 1:1 to the KSM that are held by Lido. LKSM token’s balances are updated when the oracle reports change in total stake every day.


### [LidoOracle](contracts/LidoOracle.sol)



