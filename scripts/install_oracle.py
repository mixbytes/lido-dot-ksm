from brownie import *
import pytest
from substrateinterface import Keypair
from substrateinterface import SubstrateInterface

# set you own proxy accounts
STASH2='H8ST31GnWD6AaGchQMDnqvMgZz6Nb9HGREA1R8XbRH3dkW5'
STASH1='HGcoj2TGFpVHjtbkaXfn9Zen4SB3cY7t7Pez7s72AYNRLbo'

# charlie
STASH10='Fr4NzY1udSFFLzb2R3qxVQkwz9cZraWkyfH4h3mVVk7BK7P'
# dave
STASH11='DfnTB4z7eUvYRqcGtTpFsLC69o6tvBSC1pEv8vWPZFtCkaK'
# eve
STASH12='HnMAUz7r2G8G3hB27SYNyit5aJmh2a5P4eMdDtACtMFDbam'

# Parachain soverein account
MOONBEAM='F7fq1jSAsQD9BqmTx3UAhwpMNa9WJGMmru2o7Evn83gSgfb'

VALIDATORS = [
    'GsvVmjr1CBHwQHw84pPHMDxgNY3iBLz6Qn7qS3CH8qPhrHz', # //Alice//stash
    'JKspFU6ohf1Grg3Phdzj2pSgWvsYWzSfKghhfzMbdhNBWs5'  # //Bob//stash 
]

alith  = accounts.add(private_key=0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133)
baltathar =  accounts.add(private_key=0x8075991ce870b93a8870eca0c0f91913d12f47948ca0fd25b49c6fa7cdbeee8b) 


x = interface.XcmPrecompile('0x0000000000000000000000000000000000000801')
vKSM = interface.IvKSM('0x0000000000000000000000000000000000000801')

# set after deployment
lido = None #Lido.at('0x263E845eD8536782b1FFDe3908ad36d4d023b139')
lidoOracle = None # LidoOracle.at('0xDa98d56F3357422ba9397F102E8C311Fd3fE004A')

UNIT = 1_000_000_000_000

# set Kusama relay chain node websocket endpoint address
RELAY_URL='ws://localhost:9951'

# the last transaction
t = None


def ss58decode( address ):
    return Keypair(ss58_address=address, ss58_format=2).public_key

stash = ss58decode( STASH1 )

def prompt():
    pass
    
def config(_lido=None):
    
    _lido = _lido or lido

    ledger = Ledger.deploy({'from': alith, 'required_confs': 2})
    
    print(f"set ledger {ledger.address} for lido {_lido.address}" )
    
    print("ledger's deployed")
    _lido.setLedgerMaster( ledger.address, {'from': alith, 'required_confs': 2})

    stash = ss58decode( STASH1 )
    print(f"stash {STASH1} = {stash} ") 
    
    _lido.addStash( stash, stash, {'from': alith})   


def test():
    global lido
    global lidoOracle
    global t
    
    lidoOracle = LidoOracle.deploy({'from':alith, 'required_confs': 2})
    
    lido = Lido.deploy({'from': alith, 'required_confs': 2})
    
    #lidoOracle = LidoOracle.deploy({'from':alith, 'required_confs': 2})
    lidoOracle.setLido( lido.address, {'from':alith})
    print("addOracleMember")
    lidoOracle.addOracleMember( alith.address, {'from':alith})
    lidoOracle.addOracleMember( baltathar.address, {'from':alith})    
    
    ledger = Ledger.deploy({'from': alith, 'required_confs': 2})
    lido.setOracle( lidoOracle.address, {'from': alith})
    print("set Ledger")
    lido.setLedgerMaster( ledger.address, {'from': alith, 'required_confs': 2})
    
    print("add Stash")
    stash = ss58decode( STASH1 )
    lido.addStash( stash, stash, {'from': alith, 'required_confs': 2})   
    
    #stash = ss58decode( STASH2 )
    #lido.addStash( stash, stash, {'from': alith})   
    
    ledgerAddress = lido.findLedger( stash )
    print(f"ledger address {ledgerAddress}")
    
    ledger = Ledger.at( ledgerAddress )
    
    #t = ledger.reportRelay(0,1,2, (stash, stash, 0, 0, 0, [], [], 0 ), {'from': alith })
    t = lidoOracle.reportRelay(2, (stash, stash, 0, 0, 0, [], [], 0 ), {'from': alith }) 
    
    print(t.info())


def main():
    global lido
    global lidoOracle
 
    lido = Lido.deploy({'from': alith, 'required_confs': 2})
    
    lidoOracle = LidoOracle.deploy({'from':alith, 'required_confs': 2})
    print("setLido")
    lidoOracle.setLido( lido.address, {'from':alith})
    print("setOracle")
    lido.setOracle( lidoOracle.address, {'from': alith})
    print("addOracleMember")
    lidoOracle.addOracleMember( alith.address, {'from':alith})
    lidoOracle.addOracleMember( baltathar.address, {'from':alith})
    lidoOracle.setQuorum( 1, {'from':alith})
    
    # mint 
    x.mint( alith.address, 100 * UNIT , {'from': alith})
    x.mint( baltathar.address, 100 * UNIT, {'from': alith} )
    
    config(lido)
    deposit(lido)
    
def new_proxy():
    # send XCMP message to create anonimouse proxy accounts 
    x.sendUmp("0x1e0400000000000000", {'from': alith})		
    x.sendUmp("0x1e0400000000000000", {'from': alith})		
	

def deposit(_lido = None):
    _lido = _lido or lido
    
    stash = ss58decode( STASH1 )
    print(f"stash {STASH1} = {stash} ") 
    

    vKSM.approve(_lido.address, 20 * UNIT , {'from': alith})
    vKSM.approve(_lido.address, 30 * UNIT , {'from': baltathar})
    
    _lido.deposit(20 * UNIT, {'from': alith})
    _lido.deposit(30 * UNIT, {'from': baltathar})
    
    
def createReport(url, stashAddress):
    substrate = SubstrateInterface(
        url=url,
        ss58_format=2,
        type_registry_preset='kusama',
    )

    substrate.update_type_registry_presets()
    
    result = substrate.query(
        module='Staking',
        storage_function='ActiveEra',
    )
    
    eraId = result.value['index']
    
    result = substrate.query(
        module='Staking',
        storage_function='Nominators',
        params=[stashAddress]
    )
    
    isNominator = result.value is not None
    
    #nominators = set(nominator.value for nominator, _ in result )
            
    result = substrate.query(
        module='System',
        storage_function='Account',
        params=[stashAddress]
    )
        
    free = result.value['data']['free']
    
    result = substrate.query(
        module='Staking',
        storage_function='Bonded',
        params=[stashAddress],
    )
    
    controller = result.value
    
    if controller is not None:
        
         
        result = substrate.query(
            module='Staking',
            storage_function='Ledger',
            params=[controller],
        )  
        
        stash = result.value
        
        return [
            eraId,
            ss58decode(stashAddress),
            ss58decode(controller),
            1 if isNominator else 0,
            stash['active'],
            stash['total'],
            [(item['value'], item['era']) for item in stash['unlocking'] ],
            stash['claimedRewards'],
            free
        ]
    else:
        return [
            eraId,
            ss58decode(stashAddress),
            ss58decode(stashAddress),
            3,
            0,
            0,
            [],
            [],
            free
        ]        
          
def nominate():
    lido.nominate(stash, [ss58decode(item) for item in VALIDATORS], {'from': alith})

def report():    
    report = createReport(RELAY_URL, STASH1)
    print(report)
    
    t= lidoOracle.reportRelay( report[0], report[1:], {'from': baltathar} ) 
    print( t.info() )