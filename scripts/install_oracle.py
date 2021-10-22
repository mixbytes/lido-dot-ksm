from substrateinterface import Keypair
from substrateinterface import SubstrateInterface
from pathlib import Path
from brownie import project, config, accounts, interface, ZERO_ADDRESS

ALL_ROLES = ['ROLE_SPEC_MANAGER',
             'ROLE_PAUSE_MANAGER',
             'ROLE_FEE_MANAGER',
             'ROLE_ORACLE_MANAGER',
             'ROLE_LEDGER_MANAGER',
             'ROLE_STAKE_MANAGER',
             'ROLE_ORACLE_MEMBERS_MANAGER',
             'ROLE_ORACLE_QUORUM_MANAGER']

# set you own proxy accounts
STASH = [
  'ExDErakRQnQcCwhULxEPJGfYFpGK3qSYfJFcUk3dweJ3w6P',
  'HobfP8gG3rqvdU7C2qcfEn1ruXwfE5fEmtZUcmCr7TX4ibU',
  'GLKzK731vwPo3W8ipLyaf979Mx1hbhuqFqMULU5xppWjyPe',
  'DVKFDQNXF5QDSDVAqTfvs8gZWLyd4r6n6rqrtS5RLGKRUbq'
]

# charlie
STASH10 = 'Fr4NzY1udSFFLzb2R3qxVQkwz9cZraWkyfH4h3mVVk7BK7P'
# dave
STASH11 = 'DfnTB4z7eUvYRqcGtTpFsLC69o6tvBSC1pEv8vWPZFtCkaK'
# eve
STASH12 = 'HnMAUz7r2G8G3hB27SYNyit5aJmh2a5P4eMdDtACtMFDbam'
# Oracle accounts
OR1 = '0x925eda0e60dac4a29712e1f9cfe1a3f1efe4270596e46722295248428f25e6ee'
OR2 = '0x0801d35e1dbb9e47f89ff7971c627617eef53ced08e622e82bc551540efdcb4d'
# Oracle quorum
QUORUM = 2

# Parachain soverein account
MOONBEAM = 'F7fq1jSAsQD9BqmTx3UAhwpMNa9WJGMmru2o7Evn83gSgfb'

VALIDATORS = [
    'GsvVmjr1CBHwQHw84pPHMDxgNY3iBLz6Qn7qS3CH8qPhrHz',  # //Alice//stash
    'JKspFU6ohf1Grg3Phdzj2pSgWvsYWzSfKghhfzMbdhNBWs5'   # //Bob//stash
]

alith = accounts.add(private_key=0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133)
baltathar = accounts.add(private_key=0x8075991ce870b93a8870eca0c0f91913d12f47948ca0fd25b49c6fa7cdbeee8b)

oracle1 = accounts.add(private_key=OR1)
oracle2 = accounts.add(private_key=OR2)

x = interface.XcmPrecompile('0x0000000000000000000000000000000000000801')
vKSM = interface.IvKSM('0x0000000000000000000000000000000000000801')

# set after deployment
lido = None

UNIT = 1_000_000_000_000

# set Kusama relay chain node websocket endpoint address
RELAY_URL = 'ws://localhost:9951'

# the last transaction
t = None

project.load(Path.home() / ".brownie" / "packages" / config["dependencies"][0])
if hasattr(project, 'OpenzeppelinContracts410Project'):
    OpenzeppelinContractsProject = project.OpenzeppelinContracts410Project
else:
    OpenzeppelinContractsProject = project.OpenzeppelinContractsProject

LiquidstakingOracleProject = project.LiquidstakingOracleProject

# assert(1 <= QUORUM <= 2, 'supported QUORUM of 1 or 2')


def ss58decode(address):
    return Keypair(ss58_address=address, ss58_format=2).public_key


stash = [ss58decode(S) for S in STASH]


def deploy_with_proxy(container, proxy_admin, *args):
    owner = proxy_admin.owner()
    _implementation = container.deploy({'from': owner, 'required_confs': 2})
    encoded_inputs = _implementation.initialize.encode_input(*args)

    _instance = OpenzeppelinContractsProject.TransparentUpgradeableProxy.deploy(
        _implementation,
        proxy_admin,
        encoded_inputs,
        {'from': owner, 'gas_limit': 10**6, 'required_confs': 2}
    )
    OpenzeppelinContractsProject.TransparentUpgradeableProxy.remove(_instance)

    return container.at(_instance.address)


def prompt():
    pass


def config(_lido=None):
    _lido = _lido or lido
    for S in STASH:
        s = ss58decode(S)
        print(f"stash {S} = {s} addLedger")
        _lido.addLedger(s, s, 100, {'from': alith})


def main():
    global lido

    ProxyAdmin = OpenzeppelinContractsProject.ProxyAdmin

    proxy_admin = ProxyAdmin.deploy({'from': alith, 'required_confs': 2})

    print("configure AuthManager")
    mgr = deploy_with_proxy(LiquidstakingOracleProject.AuthManager, proxy_admin, ZERO_ADDRESS)

    for role in ALL_ROLES:
        mgr.addByString(role, alith, {'from': alith})

    print("configure Lido")

    lido = deploy_with_proxy(LiquidstakingOracleProject.Lido, proxy_admin, mgr.address, vKSM, x, x)

    print("Lido proxy {lido}")

    print("Oracle deploy")
    oracle = LiquidstakingOracleProject.Oracle.deploy({'from': alith, 'required_confs': 2})
    print("Oracle master")
    oracleMaster = LiquidstakingOracleProject.OracleMaster.deploy({'from': alith, 'required_confs': 2})
    oracleMaster.initialize(oracle, QUORUM, {'from': alith})

    print("Ledger")
    lc = LiquidstakingOracleProject.Ledger.deploy({'from': alith, 'required_confs': 2})

    lido.setLedgerClone(lc, {'from': alith})

    #print("setLido for oracleMaster")
    #oracleMaster.setLido(lido, {'from': alith})
    lido.setOracleMaster(oracleMaster, {'from': alith, 'required_confs': 2})
    # Dev Kusama has 3 min era
    era_sec = 60 * 3
    lido.setRelaySpec(1, era_sec, era_sec * (28+3), 16, 1, {'from': alith})

    print("addOracleMember")
    oracleMaster.addOracleMember(oracle1.address, {'from': alith})
    oracleMaster.addOracleMember(oracle2.address, {'from': alith})

    # mint
    x.mint(alith.address, 100 * UNIT, {'from': alith})
    x.mint(baltathar.address, 100 * UNIT, {'from': alith})

    alith.transfer(oracle1, "10 ether")
    alith.transfer(oracle2, "10 ether")

    config(lido)
    deposit(lido)


def new_proxy(n=4):
    # send XCMP message to create anonimouse proxy accounts
    for _ in range(n):
        x.sendUmp("0x1e0400000000000000", {'from': alith})


def deposit(_lido=None):
    _lido = _lido or lido

    vKSM.approve(_lido.address, 20 * UNIT, {'from': alith})
    vKSM.approve(_lido.address, 30 * UNIT, {'from': baltathar})

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
            [(item['value'], item['era']) for item in stash['unlocking']],
            [],  # stash['claimedRewards'],
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
    for s in stash:
        lido.nominate(s, [ss58decode(item) for item in VALIDATORS], {'from': alith})


def report(_lido=None):
    _lido = _lido or lido
    oracleMaster = OracleMaster.at(_lido.ORACLE_MASTER())
    for S in STASH:
        print(f"report for {S}")
        r = createReport(RELAY_URL, S)

        t = oracleMaster.reportRelay(r[0], r[1:], {'from': oracle1})
        if QUORUM > 1:
            t = oracleMaster.reportRelay(r[0], r[1:], {'from': oracle2})
        print(t.info())
