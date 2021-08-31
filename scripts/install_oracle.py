from brownie import *
import pytest
from substrateinterface import Keypair
from substrateinterface import SubstrateInterface

ALL_ROLES = [ 'ROLE_SPEC_MANAGER','ROLE_PAUSE_MANAGER', 'ROLE_FEE_MANAGER', 'ROLE_ORACLE_MANAGER','ROLE_LEDGER_MANAGER',
                'ROLE_STAKE_MANAGER', 'ROLE_ORACLE_MEMBERS_MANAGER', 'ROLE_ORACLE_QUORUM_MANAGER' ]

QUORUM = 2
# set you own proxy accounts
STASH1='F7yiRjEEJs6xwNyrrt96rgKC2GxCa2uHN9iVX3KJi9QwpwT'
STASH2='H6zbEa7FZC56nndNzEbbKgBCp9rnZS7KH6vLyRJgV7z4Sei'

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
lido = None
oracleMaster = None

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

    stash = ss58decode( STASH1 )
    print(f"stash {STASH1} = {stash} addLedger")
    
    _lido.addLedger( stash, stash, 100, {'from': alith})

    stash = ss58decode( STASH2 )
    print(f"stash {STASH2} = {stash} addLedger")

    _lido.addLedger( stash, stash, 100, {'from': alith})

def main():
    global lido
    global oracleMaster

    print("configure AuthManager")

    mgr  = AuthManager.deploy(ZERO_ADDRESS, {'from':alith, 'required_confs': 2})

    for role in ALL_ROLES:
        mgr.addByString(role, alith, {'from': alith })

    # mgr = AuthManager.at('0x9c1da847B31C0973F26b1a2A3d5c04365a867703')

    print("configure Lido")
    lido = Lido.deploy({'from': alith, 'required_confs': 2})

    print("Oracle deploy")
    oracle = Oracle.deploy({'from':alith, 'required_confs': 2})
    print("Oracle master")
    oracleMaster = OracleMaster.deploy({'from': alith, 'required_confs': 2})
    oracleMaster.initialize(oracle, QUORUM, {'from': alith})

    print("Ledger")
    lc = Ledger.deploy({'from': alith, 'required_confs': 2 })

    lido.initialize(mgr, vKSM, x, x, {'from': alith})
    lido.setLedgerClone(lc, {'from':alith})

    print("setLido for oracleMaster")
    oracleMaster.setLido(lido, {'from':alith})
    lido.setOracleMaster(oracleMaster, {'from':alith, 'required_confs': 2})
    # Dev Kusama has 3 min era
    era_sec = 60 * 3
    lido.setRelaySpec((chain.time(), era_sec, era_sec * (28+3), 16, 1))

    print("addOracleMember")
    oracleMaster.addOracleMember( alith.address, {'from':alith})
    oracleMaster.addOracleMember( baltathar.address, {'from':alith})

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
    global oracleMaster
    report = createReport(RELAY_URL, STASH1)
    print(report)

    t = oracleMaster.reportRelay( report[0], report[1:], {'from': alith} )
    if QUORUM>1:
        t = oracleMaster.reportRelay( report[0], report[1:], {'from': baltathar} )
    print( t.info() )