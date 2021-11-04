from substrateinterface import Keypair
from substrateinterface import SubstrateInterface
from pathlib import Path
from brownie import *

ALL_ROLES = ['ROLE_SPEC_MANAGER',
             'ROLE_PAUSE_MANAGER',
             'ROLE_FEE_MANAGER',
             'ROLE_ORACLE_MANAGER',
             'ROLE_LEDGER_MANAGER',
             'ROLE_STAKE_MANAGER',
             'ROLE_ORACLE_MEMBERS_MANAGER',
             'ROLE_ORACLE_QUORUM_MANAGER']

# Oracle accounts
OR1 = '0x925eda0e60dac4a29712e1f9cfe1a3f1efe4270596e46722295248428f25e6ee'
OR2 = '0x0801d35e1dbb9e47f89ff7971c627617eef53ced08e622e82bc551540efdcb4d'
# Oracle quorum
QUORUM = 2

alith = accounts.add(private_key=0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133)
baltathar = accounts.add(private_key=0x8075991ce870b93a8870eca0c0f91913d12f47948ca0fd25b49c6fa7cdbeee8b)

oracle1 = accounts.add(private_key=OR1)
oracle2 = accounts.add(private_key=OR2)

x = interface.XcmPrecompile('0x0000000000000000000000000000000000000801')
vKSM = interface.IvKSM('0x0000000000000000000000000000000000000801')

# set after deployment
lido = None

UNIT = 1_000_000_000_000

project.load(Path.home() / ".brownie" / "packages" / config["dependencies"][0])
if hasattr(project, 'OpenzeppelinContracts410Project'):
    OpenzeppelinContractsProject = project.OpenzeppelinContracts410Project
else:
    OpenzeppelinContractsProject = project.OpenzeppelinContractsProject

LiquidstakingOracleProject = project.LidoDotKsmProject

# assert(1 <= QUORUM <= 2, 'supported QUORUM of 1 or 2')


def ss58decode(address):
    return Keypair(ss58_address=address, ss58_format=2).public_key


stash = [ss58decode(S) for S in STASH]


def deploy_with_proxy(container, admin, deployer, *args):
    owner = proxy_admin.owner()
    _implementation = container.deploy({'from': deployer, 'required_confs': 2, 'gas_limit': 12*10**6})
    encoded_inputs = _implementation.initialize.encode_input(*args)

    _instance = OpenzeppelinContractsProject.TransparentUpgradeableProxy.deploy(
        _implementation,
        admin,
        encoded_inputs,
        {'from': deployer, 'gas_limit': 10**6, 'required_confs': 2, 'gas_limit': 12*10**6}
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
        _lido.addLedger(s, s, 100, {'from': alith, 'gas_limit': 12*10**6})


def deploy_proxy_admin(deployer):
    ProxyAdmin = OpenzeppelinContractsProject.ProxyAdmin
    return ProxyAdmin.deploy({'from': deployer, 'required_confs': 2, 'gas_limit': 12*10**6})


def deploy_auth_manager(deployer, admin, auth_super_admin):
    return deploy_with_proxy(AuthManager, admin, deployer, auth_super_admin)


def deploy_oracle_clone(deployer):
    return Oracle.deploy({'from': deployer, 'required_confs': 2, 'gas_limit': 12*10**6})


def deploy_oracle_master(deployer):
    return OracleMaster.deploy({'from': deployer, 'required_confs': 2, 'gas_limit': 12*10**6})


def deploy_ledger_clone(deployer):
    return Ledger.deploy({'from': deployer, 'required_confs': 2, 'gas_limit': 12*10**6})


def deploy_lido(deployer, admin, auth_manager, vksm, vaccs, aux, treasury, developers):
    return deploy_with_proxy(Lido, admin, auth_manager, vksm, vaccs, aux, treasury, developers)


def main():
    deployer = alith
    admin = alith
    auth_super_admin = alith
    treasury = alith
    developers = alith
    roles = {
        'ROLE_SPEC_MANAGER': alith,
        'ROLE_PAUSE_MANAGER': alith,
        'ROLE_FEE_MANAGER': alith,
        'ROLE_ORACLE_MANAGER': alith,
        'ROLE_LEDGER_MANAGER': alith,
        'ROLE_STAKE_MANAGER': alith,
        'ROLE_ORACLE_MEMBERS_MANAGER': alith,
        'ROLE_ORACLE_QUORUM_MANAGER': alith
    }
    oracles = [oracle1, oracle2]
    oracle_quorum = QUORUM
    vksm = vKSM.address
    vaccs = vKSM.address
    aux = vKSM.address

    print("Deploying proxy admin...")
    proxy_admin = deploy_proxy_admin(deployer)
    print("Proxy admin:", proxy_admin)

    print("Deploying auth manager...")
    auth_manager = deploy_auth_manager(deployer, admin, auth_super_admin)
    print("Auth manager:", auth_manager)

    print("Setting roles...")
    for role in roles:
        mgr.addByString(role, roles[role], {'from': alith, 'gas_limit': 12*10**6})

    print("Deploying lido...")
    lido = deploy_lido(deployer, admin, auth_manager, vksm, vaccs, aux, treasury, developers)
    print('Lido:', lido)


    print("Deploying oracle clone...")
    oracle_clone = deploy_oracle_clone(deployer)
    print('Oracle clone:', oracle_clone)

    print("Deploying oracle master...")
    oracle_master = deploy_oracle_master(deployer)
    print('Oracle master:', oracle_master)

    print('Oracle master initialization...')
    oracle_master.initialize(oracle_clone, oracle_quorum, {'from': deployer, 'gas_limit': 12*10**6})

    print("Deploying ledger clone...")
    ledger_clone = deploy_ledger_clone(deployer)
    print('Ledger clone:', ledger_clone)

    print('Lido configuration...')
    lido.setOracleMaster(oracle_master, {'from': roles['ROLE_ORACLE_MANAGER'], 'required_confs': 2, 'gas_limit': 12*10**6}):wq:wq:q


    oracle = LiquidstakingOracleProject.Oracle.deploy({'from': alith, 'required_confs': 2, 'gas_limit': 12*10**6})
    print("Oracle master")
    oracleMaster = LiquidstakingOracleProject.OracleMaster.deploy({'from': alith, 'required_confs': 2, 'gas_limit': 12*10**6})
    oracleMaster.initialize(oracle, QUORUM, {'from': alith, 'gas_limit': 12*10**6})

    print("Ledger")
    lc = LiquidstakingOracleProject.Ledger.deploy({'from': alith, 'required_confs': 2, 'gas_limit': 12*10**6})

    lido.setLedgerClone(lc, {'from': alith, 'gas_limit': 12*10**6})

    #print("setLido for oracleMaster")
    #oracleMaster.setLido(lido, {'from': alith})
    lido.setOracleMaster(oracleMaster, {'from': alith, 'required_confs': 2, 'gas_limit': 12*10**6})
    # Dev Kusama has 3 min era
    era_sec = 60 * 3
    lido.setRelaySpec((1, era_sec, era_sec * (28+3), 16, 1), {'from': alith, 'gas_limit': 12*10**6})

    print("addOracleMember")
    oracleMaster.addOracleMember(oracle1.address, {'from': alith, 'gas_limit': 12*10**6})
    oracleMaster.addOracleMember(oracle2.address, {'from': alith, 'gas_limit': 12*10**6})

    # mint
    x.mint(alith.address, 100 * UNIT, {'from': alith, 'gas_limit': 12*10**6})
    x.mint(baltathar.address, 100 * UNIT, {'from': alith, 'gas_limit': 12*10**6})

    alith.transfer(oracle1, "10 ether")
    alith.transfer(oracle2, "10 ether")

    config(lido)


