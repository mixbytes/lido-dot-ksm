from substrateinterface import Keypair
from substrateinterface import SubstrateInterface
from pathlib import Path
from brownie import *
import base58
from hashlib import blake2b


def get_derivative_account(root_account, index):
    seed_bytes = b'modlpy/utilisuba'
    root_account_bytes = bytes.fromhex(Keypair(root_account).public_key[2:])
    index_bytes = int(index).to_bytes(2, 'little')

    entropy = blake2b(seed_bytes + root_account_bytes + index_bytes, digest_size=32).digest()
    input_bytes = bytes([42]) + entropy
    checksum = blake2b(b'SS58PRE' + input_bytes).digest()
    return base58.b58encode(input_bytes + checksum[:2]).decode()


project.load(Path.home() / ".brownie" / "packages" / config["dependencies"][0])
if hasattr(project, 'OpenzeppelinContracts410Project'):
    OpenzeppelinContractsProject = project.OpenzeppelinContracts410Project
else:
    OpenzeppelinContractsProject = project.OpenzeppelinContractsProject

LiquidstakingOracleProject = project.LidoDotKsmProject


# global configs
CONFS = 1
GAS_PRICE = "3 gwei"
GAS_LIMIT = 10*10**6


# oracles
ALL_ROLES = ['ROLE_SPEC_MANAGER',
             'ROLE_PAUSE_MANAGER',
             'ROLE_FEE_MANAGER',
             'ROLE_ORACLE_MANAGER',
             'ROLE_LEDGER_MANAGER',
             'ROLE_STAKE_MANAGER',
             'ROLE_ORACLE_MEMBERS_MANAGER',
             'ROLE_ORACLE_QUORUM_MANAGER']


# stashes
ROOT_DERIVATIVE = '5HYQeRamG9nQyRYAUoyHMuZ9tnSTPNSyim4uCBXuBCHJJm6a'
STASH_IDX = [40, 41, 42]
STASH = [ get_derivative_account(ROOT_DERIVATIVE, idx) for idx in STASH_IDX ]


# Oracles
ORACLES = [accounts.add(private_key='0x925eda0e60dac4a29712e1f9cfe1a3f1efe4270596e46722295248428f25e6ee'), accounts.add(private_key='0x0801d35e1dbb9e47f89ff7971c627617eef53ced08e622e82bc551540efdcb4d')]
QUORUM = 2


# contracts/precompiles/deployer
DEPLOYER = accounts.from_mnemonic("rough spider regular borrow shrimp noble scare strike color goddess diesel laugh")
PROXY_ADMIN = OpenzeppelinContractsProject.ProxyAdmin.at('0x18d5d0ae23C60E109d88F9E92068c307c02D1fdd', owner=DEPLOYER)
VKSM = interface.IERC20('0xFFFFFFFF1FCACBD218EDC0EBA20FC2308C778080')
CONTROLLER = Controller.at('0xD52E642Fc8ddabEb803F1382970a3c13822ca47e')

#xcmTransactor = interface.IXcmTransactor('0x0000000000000000000000000000000000000806')
#relayEncoder = interface.IRelayEncoder('0x0000000000000000000000000000000000000805')
#xtoken = interface.IxTokens('0x0000000000000000000000000000000000000804')


# utils
def ss58decode(address):
    return Keypair(ss58_address=address).public_key


def get_opts(sender=DEPLOYER, gas_price=GAS_PRICE, gas_limit=GAS_LIMIT):
    return {'from': sender, 'gas_price': gas_price, 'gas_limit': gas_limit}


def deploy_with_proxy(container, proxy_admin, deployer, *args):
    owner = proxy_admin.owner()
    _implementation = container.deploy(get_opts(deployer))
    encoded_inputs = _implementation.initialize.encode_input(*args)

    _instance = OpenzeppelinContractsProject.TransparentUpgradeableProxy.deploy(
        _implementation,
        proxy_admin,
        encoded_inputs,
        get_opts(deployer)
    )
    OpenzeppelinContractsProject.TransparentUpgradeableProxy.remove(_instance)

    return container.at(_instance.address)


# deploy functions
def deploy_proxy_admin(deployer):
    ProxyAdmin = OpenzeppelinContractsProject.ProxyAdmin
    return ProxyAdmin.deploy(get_opts(deployer))


def deploy_auth_manager(deployer, admin, auth_super_admin):
    return deploy_with_proxy(AuthManager, admin, deployer, auth_super_admin)


def deploy_oracle_clone(deployer):
    return Oracle.deploy(get_opts(deployer))


def deploy_oracle_master(deployer):
    return OracleMaster.deploy(get_opts(deployer))


def deploy_ledger_clone(deployer):
    return Ledger.deploy(get_opts(deployer))


def deploy_lido(deployer, admin, auth_manager, vksm, controller, treasury, developers):
    return deploy_with_proxy(Lido, admin, deployer, auth_manager, vksm, controller, treasury, developers)


# deployment
def main():
    deployer = DEPLOYER
    admin = DEPLOYER
    auth_super_admin = DEPLOYER
    treasury = DEPLOYER
    developers = DEPLOYER
    roles = {
        'ROLE_SPEC_MANAGER': DEPLOYER,
        'ROLE_PAUSE_MANAGER': DEPLOYER,
        'ROLE_FEE_MANAGER': DEPLOYER,
        'ROLE_ORACLE_MANAGER': DEPLOYER,
        'ROLE_LEDGER_MANAGER': DEPLOYER,
        'ROLE_STAKE_MANAGER': DEPLOYER,
        'ROLE_ORACLE_MEMBERS_MANAGER': DEPLOYER,
        'ROLE_ORACLE_QUORUM_MANAGER': DEPLOYER
    }
    oracles = ORACLES
    oracle_quorum = QUORUM
    vksm = VKSM.address
    controller = CONTROLLER.address
    era_sec = 21600 # moonbase
    max_validators_per_ledger = 16
    min_moninator_balance = 1 * 10**12
    stashes = STASH
    stash_idxs = STASH_IDX

    proxy_admin = PROXY_ADMIN
    print("Proxy admin:", proxy_admin)

#    print("Deploying auth manager...")
#    auth_manager = deploy_auth_manager(deployer, proxy_admin, auth_super_admin)
#    print("Auth manager:", auth_manager)

#    for role in roles:
#        print("Setting role:", role)
#        auth_manager.addByString(role, roles[role], get_opts(deployer))

    auth_manager = AuthManager.at('0x06A191588c9FFCd323ad99bcED86efDab3331BBc')
    print("Deploying lido...")
    lido = deploy_lido(deployer, proxy_admin, auth_manager, vksm, controller, treasury, developers)
    #lido = Lido.at('0xEBe2Aeaf123922C6f7B5cc98b8a4FD172c6eD92b')
    print('Lido:', lido)


    print("Deploying oracle clone...")
    oracle_clone = deploy_oracle_clone(deployer)
    print('Oracle clone:', oracle_clone)

    print("Deploying oracle master...")
    oracle_master = deploy_oracle_master(deployer)
#    oracle_master = OracleMaster.at('0x70ED8c2786718146b681dfd91796C288C0274C06')
    print('Oracle master:', oracle_master)

    print('Oracle master initialization...')
    oracle_master.initialize(oracle_clone, oracle_quorum, get_opts(deployer))

    print("Deploying ledger clone...")
    ledger_clone = deploy_ledger_clone(deployer)
#    ledger_clone = Ledger.at('0xe3B75E296B8Bf8eEbFa72849D0Ce3Bf942e6C3Eb')
    print('Ledger clone:', ledger_clone)

    print('Lido configuration...')
    lido.setOracleMaster(oracle_master, get_opts(roles['ROLE_ORACLE_MANAGER']))
    lido.setLedgerClone(ledger_clone, get_opts(roles['ROLE_ORACLE_MANAGER']))
    lido.setRelaySpec((1, era_sec, era_sec * (28+3), max_validators_per_ledger, min_moninator_balance), get_opts(roles['ROLE_SPEC_MANAGER']))

    for oracle in ORACLES:
        print("Adding oracle member:", oracle)
        oracle_master.addOracleMember(oracle, get_opts(roles['ROLE_ORACLE_MEMBERS_MANAGER']))

    ledgers = []
    for i in range(len(stashes)):
        s_bytes = ss58decode(stashes[i])
        print("Adding ledger, stash:", stashes[i], stash_idxs[i])
        lido.addLedger(s_bytes, s_bytes, stash_idxs[i], 100, get_opts(roles['ROLE_LEDGER_MANAGER']))
        ledgers.append(lido.findLedger(s_bytes))

#    for ledger in ledgers:
#        print("Refreshing allowances for ledger:", ledger)
#        Ledger.at(ledger).refreshAllowances(get_opts())
#
#    print("Refreshing allowances for lido")
#    lido.refreshAllowances(get_opts(roles['ROLE_LEDGER_MANAGER']));



def prompt():
    pass



