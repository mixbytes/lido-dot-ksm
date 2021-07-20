from brownie import *
import pytest

def get_report(active=[]):
    # ( address, balance)
    stash = [ (   a[item[0] ].address, item[1] )  for item in enumerate(active) ] 

    return (10, [ (
        item[0], #stash
        item[0], #controller
        1, #status
        item[1], #active balance
        item[1], #total balance,
        [], #unlocking chunks
        [], #claimed rewards
        item[1] + 10_000 # stash balance
    )  for item in stash ] )


def main():
    lido = LidoMock.deploy({'from': a[0]})

    oracle = LidoOracle.deploy(lido, {'from':a[0]})

    oracle.addOracleMember( a[5].address, {'from':a[0]})
    oracle.addOracleMember( a[6].address, {'from':a[0]})
    oracle.addOracleMember( a[7].address, {'from':a[0]})

    oracle.setQuorum( 2, {'from':a[0]})

    lido.amendStake(1000000);   
    
    print(f" *****************  ERA {oracle.eraId()} **********************");

    tx = oracle.reportRelay(0, get_report( active = [10_000, 20_000] ), {'from': a[5]} )
    print("===== unit 1 =====") 
    tx.info()
    
    tx = oracle.reportRelay(0, get_report( active = [10_000, 20_000, 3] ), {'from': a[7]} )
    print("===== unit 2 =====") 
    tx.info()
    
    # unit 1 repeat call
    #tx = oracle.reportRelay(0, get_report( active = [10_000, 20_000] ), {'from': a[5]} )
    #print("unit 1", tx.info())


    variants = oracle._reportVariants()
    print( "variants:", [ hex(item) for item in variants ]  )
    
    tx = oracle.reportRelay(0, get_report( active = [10_000, 20_000] ), {'from': a[6]} )
    print("===== unit 3 =====")
    tx.info()
    
    
    print(f" *****************  ERA {oracle.eraId()} **********************");
    
    # skip one era
    tx = oracle.reportRelay(2, get_report( active = [10_000, 25_000] ), {'from': a[7]} )
    print("===== unit 2 =====") 
    tx.info()
    
    
    tx = oracle.reportRelay(2, get_report( active = [10_000, 25_000] ), {'from': a[5]} )
    print("===== unit 1 =====")
    tx.info()
    
    
    era = oracle.eraId()
    
    if era <= 2:
        tx = oracle.reportRelay(2, get_report( active = [10_000, 25_000] ), {'from': a[6]} )
        print("===== unit 3 =====")
        tx.info()
    else:
        print("unit 3 skips a voting") 
    
        
    print(f" *****************  ERA {oracle.eraId()} **********************");
    
    print("quorum is 3 of 3")
    
    oracle.setQuorum( 3, {'from':a[0]})
    
    tx = oracle.reportRelay(3, get_report( active = [15_000, 27_000] ), {'from': a[7]} )
    print("===== unit 2 =====") 
    tx.info()
    
    
    tx = oracle.reportRelay(3, get_report( active = [15_000, 27_000] ), {'from': a[5]} )
    print("===== unit 1 =====")
    tx.info()
    
    
    variants = oracle._reportVariants()
    print( "variants:", [ hex(item) for item in variants ]  )
    
    
    print("change quorum back to 2")
    tx = oracle.setQuorum( 2, {'from':a[0]})
    tx.info()
    
    timestamp = oracle._timestamp()
    print(f"timestamp {timestamp}")
    
    #assert s.price() == 99 

    print( "passed" )