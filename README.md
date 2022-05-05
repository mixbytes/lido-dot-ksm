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
|Controller|[0xa7477a06027149c551457cFc9f76e179e9267146](https://moonbase.moonscan.io/address/0xa7477a06027149c551457cFc9f76e179e9267146)|
|AuthManager|[0x0D5A598086F89e8B22e5e5F30fc315C07F2e5291](https://moonbase.moonscan.io/address/0x0D5A598086F89e8B22e5e5F30fc315C07F2e5291)|
|Lido|[0x708702be8e5e91320f5503AA8df076a1fe9f39a6](https://moonbase.moonscan.io/address/0x708702be8e5e91320f5503AA8df076a1fe9f39a6)|
|Oracle|[0x7Fab8A0f5c7F5B3A87A1A63AD62c6C450a4b8ceE](https://moonbase.moonscan.io/address/0x7Fab8A0f5c7F5B3A87A1A63AD62c6C450a4b8ceE)|
|OracleMaster|[0x68a6520c459faAcB662E1f5206B63D8fa698Fea7](https://moonbase.moonscan.io/address/0x68a6520c459faAcB662E1f5206B63D8fa698Fea7)|
|Ledger|[0xDcBDCa2bD5c1f64452318bEda8a6350a0545cA35](https://moonbase.moonscan.io/address/0xDcBDCa2bD5c1f64452318bEda8a6350a0545cA35)|
|LedgerBeacon|[0x8589b22F597a9c02376A7f60B7Bb7aB6295A570e](https://moonbase.moonscan.io/address/0x8589b22F597a9c02376A7f60B7Bb7aB6295A570e)|
|LedgerFactory|[0xD446000EFd2931a2890d0F0FF0d6e856beb98441](https://moonbase.moonscan.io/address/0xD446000EFd2931a2890d0F0FF0d6e856beb98441)|
|WstKSM|[0x9fc8EBF545CdcD3363137ebac72c06165acA4c06](https://moonbase.moonscan.io/address/00x9fc8EBF545CdcD3363137ebac72c06165acA4c06)|
|Withdrawal|[0x5b95D3632B0377fae76CC029E98D63BdcF55B378](https://moonbase.moonscan.io/address/0x5b95D3632B0377fae76CC029E98D63BdcF55B378)|

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
|Withdrawal|[0x50afC32c3E5D25aee36D035806D80eE0C09c2a16](https://moonriver.moonscan.io/address/0x50afC32c3E5D25aee36D035806D80eE0C09c2a16)|

### Moonbeam (Polkadot)
Deploy commit: 7db47f7fef94eb40781f62beb551ae45d82dd40f
|Contract|Address|
|-|-|
|Controller|[0xa4b43F9B0aef0b22365727e93E91c096a09ef091](https://moonscan.io/address/0xa4b43F9B0aef0b22365727e93E91c096a09ef091)|
|AuthManager|[0x78d36208D2Eb3a1E6D84a727Ee1C012FF4cc293F](https://moonscan.io/address/0x78d36208D2Eb3a1E6D84a727Ee1C012FF4cc293F)|
|Lido|[0xFA36Fe1dA08C89eC72Ea1F0143a35bFd5DAea108](https://moonscan.io/address/0xFA36Fe1dA08C89eC72Ea1F0143a35bFd5DAea108)|
|Oracle|[0x91069b93062c1Fdd6998741C9CA3C6eA57672956](https://moonscan.io/address/0x91069b93062c1Fdd6998741C9CA3C6eA57672956)|
|OracleMaster|[0x29767b69c2c39b22667dfD960e95911AC6e0CCEd](https://moonscan.io/address/0x29767b69c2c39b22667dfD960e95911AC6e0CCEd)|
|Ledger|[0x891F6825afEbfbB4Bf6889b86724ac859477E4C4](https://moonscan.io/address/0x891F6825afEbfbB4Bf6889b86724ac859477E4C4)|
|LedgerBeacon|[0xB9675751CE5840acD4c0Ba0E2d5a9188A8f34Bb8](https://moonscan.io/address/0xB9675751CE5840acD4c0Ba0E2d5a9188A8f34Bb8)|
|LedgerFactory|[0xf8B73E2Ffb2d0e25cf3166A22ea3Fe1F73483F49](https://moonscan.io/address/0xf8B73E2Ffb2d0e25cf3166A22ea3Fe1F73483F49)|
|WstKSM|[0x191cf2602Ca2e534c5Ccae7BCBF4C46a704bb949](https://moonscan.io/address/0x191cf2602Ca2e534c5Ccae7BCBF4C46a704bb949)|
|Withdrawal|[0x25442Adf37379BE90ed1F7FcCd9c9417b10aA4DC](https://moonscan.io/address/0x25442Adf37379BE90ed1F7FcCd9c9417b10aA4DC)|