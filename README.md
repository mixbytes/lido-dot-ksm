# Lido KSM/DOT Liquid Staking Protocol

The Lido KSM/DOT Liquid Staking Protocol, built on Kusama(Polkadot) chain, allows their users to earn staking rewards on the Kusama chain without locking KSM or maintaining staking infrastructure.

Users can deposit KSM to the Lido smart contract and receive stKSM tokens in return. The smart contract then stakes tokens with the DAO-picked node operators. Users' deposited funds are pooled by the DAO, node operators never have direct access to the users' assets.

Unlike staked KSM directly on Kusama network, the stKSM token is free from the limitations associated with a lack of liquidity and can be transferred at any time.
The stKSM token balance corresponds to the amount of Kusama chain KSM that the holder could withdraw.

Before getting started with this repo, please read:

## Contracts

Most of the protocol is implemented as a set of smart contracts.
These contracts are located in the [contracts/](contracts/) directory.

### [Lido](contracts/Lido.sol)
Main contract that implements stakes pooling, distribution logic and `stKSM` minting/burning mechanic.
Contract also inherits from `stKSM.sol` and impements ERC-20 interface for `stKSM` token.

### [stKSM](contracts/stKSM.sol)
The ERC20 token which uses shares to calculate users balances. A balance of a user depends on how much shares was minted and how much KSM was pooled to `LIDO.sol`.

### [WstKSM](contracts/wstKSM.sol)
The ERC20 token which uses user shares in `stKSM` token to mint `WstKSM`. `stKSM` is a rebaseable token which makes it unusable for some protocols. For using funds in that protocols `stKSM` can be changed to `WstKSM`.

### [Ledger](contracts/Ledger.sol)
This contract contains staking logic of particular ledger. Basically, contract receive "target" stake amount from `Lido.sol` and current staking ledger state from relaychain and spawn XCM calls to relaychain to bring real ledger stake to "target" value.

### [Oracle](contracts/Oracle.sol)
Oracle contains logic to provide actual relaychain staking ledgers state to ledger contracts.
Contract uses consensus mechanism for protecting from malicious members, so in two words that require particular quorum from oracle members to report new state.

### [OracleMaster](contracts/OracleMaster.sol)
The hub for all oracles, which receives all reports from oracles members and simply sends them to oracles and also calls update of ledgers stakes in the `Lido.sol` when a new epoch begins.

### [Controller](contracts/Controller.sol)
Intermediate contract for interaction with relaychain through XCM. This contract basically incapsulate whole stuff about cross-chain communications and provide simple external interface for: calling relaychain's staking operations, bridging KSM from relaychain to parachain and back.

### [AuthManager](contracts/AuthManager.sol)
Simple contract which manages roles for the whole protocol. New and old roles can be added and removed.

### [LedgerFactory](contracts/LedgerFactory.sol)
The factory for creating new ledgers according the beacon proxy pattern. The beacon proxy allows to change an implementation for all proxies in one tx.


## Quick start
### Install dependencies

```bash=
npm install
pip install -r requirements.txt
```

### Compile contracts

```bash
brownie compile
```

### Run tests

```bash
brownie test
```

### Check coverage

```bash
brownie test --coverage
```

## Contract deployments
### Moonbase
Deploy commit: 617b60fd8a0da43e44e11d62793334053269fa1a
|Contract|Address|
|-|-|
|Controller|[0x4b1a55F7c3b5A7C8b2161D0ce572B8409E65D3f2](https://moonbase.moonscan.io/address/0x4b1a55F7c3b5A7C8b2161D0ce572B8409E65D3f2)|
|AuthManager|[0x09a8689Cb43f7E5f63C97E44d5012EEA9656aE4F](https://moonbase.moonscan.io/address/0x09a8689Cb43f7E5f63C97E44d5012EEA9656aE4F)|
|Lido|[0xacA764da021606db2Aa34a0AD731F6b09E029B79](https://moonbase.moonscan.io/address/0xacA764da021606db2Aa34a0AD731F6b09E029B79)|
|Oracle|[0x7eEbaaE0d29C379a370B5275398838604C6a728b](https://moonbase.moonscan.io/address/0x7eEbaaE0d29C379a370B5275398838604C6a728b)|
|OracleMaster|[0x7af965f704cF5EFD7E02D329854ea50bFc2Fe741](https://moonbase.moonscan.io/address/0x7af965f704cF5EFD7E02D329854ea50bFc2Fe741)|
|Ledger|[0x00A265AF0dC232220F5E3eC8f8Da99BD39EB14D7](https://moonbase.moonscan.io/address/0x00A265AF0dC232220F5E3eC8f8Da99BD39EB14D7)|
|LedgerBeacon|[0x50B8f66B0Bf841e138B91Bc1938Ac4F5fE47ffc7](https://moonbase.moonscan.io/address/0x50B8f66B0Bf841e138B91Bc1938Ac4F5fE47ffc7)|
|LedgerFactory|[0x4832b19117633cac45eB7dDec846B4527cc6cCC9](https://moonbase.moonscan.io/address/0x4832b19117633cac45eB7dDec846B4527cc6cCC9)|
|WstKSM|[0x18C8EB26AcBA942f80D4aB7E8678cEFeaE60B9A7](https://moonbase.moonscan.io/address/0x18C8EB26AcBA942f80D4aB7E8678cEFeaE60B9A7)|

### Moonriver (Kusama)
Deploy commit: 2f2725faa0bc371e4d1ddfceacd8c45d8f0905f8
|Contract|Address|
|-|-|
|Controller|[0xA3965dCeE17DceDA55244ff85E979D4D5b8A0D86](https://moonriver.moonscan.io/address/0xA3965dCeE17DceDA55244ff85E979D4D5b8A0D86)|
|AuthManager|[0x1077799f07c4DC45872E832902571f56e1f9185B](https://moonriver.moonscan.io/address/0x1077799f07c4DC45872E832902571f56e1f9185B)|
|Lido|[0xFfc7780C34B450d917d557E728f033033CB4fA8C](https://moonriver.moonscan.io/address/0xFfc7780C34B450d917d557E728f033033CB4fA8C)|
|Oracle|[0xA73Bc334b3c64a66969677CbE7103e38DBC8858D](https://moonriver.moonscan.io/address/0xA73Bc334b3c64a66969677CbE7103e38DBC8858D)|
|OracleMaster|[0x698ec30D747996670A4063505E34Dfbd6d1E1db5](https://moonriver.moonscan.io/address/0x698ec30D747996670A4063505E34Dfbd6d1E1db5)|
|Ledger|[0x93f220D3e997D21D423687cBCa5874a7EAbEbE8B](https://moonriver.moonscan.io/address/0x93f220D3e997D21D423687cBCa5874a7EAbEbE8B)|
|LedgerBeacon|[0x36Cf86FFa541fed07550ffD9536DBFaAC73da7Eb](https://moonriver.moonscan.io/address/0x36Cf86FFa541fed07550ffD9536DBFaAC73da7Eb)|
|LedgerFactory|[0x780825fD0E7b09A8c136aD41090E356c138E0EdE](https://moonriver.moonscan.io/address/0x780825fD0E7b09A8c136aD41090E356c138E0EdE)|
|WstKSM|[0x3bfd113ad0329a7994a681236323fb16E16790e3](https://moonriver.moonscan.io/address/0x3bfd113ad0329a7994a681236323fb16E16790e3)|
