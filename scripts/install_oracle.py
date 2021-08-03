from brownie import *
import pytest

def main():

    alith  = accounts.add(private_key=0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133)
    baltathar =  accounts.add(private_key=0x8075991ce870b93a8870eca0c0f91913d12f47948ca0fd25b49c6fa7cdbeee8b) 
 
    lido = LidoMock.deploy({'from': alith})

    oracle = LidoOracle.deploy({'from':alith})

    oracle.setLido( lido.address, {'from':alith})
    oracle.addOracleMember( alith.address, {'from':alith})
    oracle.addOracleMember( baltathar.address, {'from':alith})

    oracle.setQuorum( 2, {'from':alith})

