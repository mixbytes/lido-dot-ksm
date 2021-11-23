from substrateinterface import Keypair
from substrateinterface import SubstrateInterface
from pathlib import Path
from brownie import *
import base58
from hashlib import blake2b
import json
import yaml
from pathlib import Path
from colorama import Fore, Back, Style, init

init(autoreset=True)


NETWORK="moonbase"

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


def load_deployments(network):
    path = "./deployments/" + network + '.json'
    if Path(path).is_file():
        with open(path) as file:
            return json.load(file)
    else:
        return {}


def save_deployments(deployments, network):
    path = "./deployments/" + network + '.json'
    with open(path, 'w') as file:
        json.dump(deployments, file)


def load_deployment_config(network):
    with open('./deployment-config.yml') as file:
        return yaml.safe_load(file)['networks'][network]


CONFIG = load_deployment_config(NETWORK)
DEPLOYMENTS = load_deployments(NETWORK)


# global configs
CONFS = 1
GAS_PRICE = "3 gwei"
GAS_LIMIT = 10*10**6



# utils
def ss58decode(address):
    return Keypair(ss58_address=address).public_key


def get_opts(sender, gas_price=GAS_PRICE, gas_limit=GAS_LIMIT):
    return {'from': sender, 'gas_price': gas_price, 'gas_limit': gas_limit}


def get_deployment(container):
    info = container.get_verification_info()
    name = info['contract_name']
    if name in DEPLOYMENTS:
        return DEPLOYMENTS[name]
    else:
        return None


def add_new_deploy(container, address):
    info = container.get_verification_info()
    name = info['contract_name']
    DEPLOYMENTS[name] = address
    save_deployments(DEPLOYMENTS, NETWORK)


def yes_or_no(question):
    reply = input(question+' (y/n): ').lower().strip()
    if reply[0] == 'y':
        return True
    if reply[0] == 'n':
        return False
    else:
        return yes_or_no(Fore.RED + "Uhhhh... please enter y/n ")

def check_and_get_deployment(container):
    deployment = get_deployment(container)
    name = container.get_verification_info()["contract_name"]
    if deployment:
        if yes_or_no(Fore.RED + f'Found old deployment for {name} at {deployment}, use it?'):
            return container.at(deployment)
        else:
            print(Fore.RED + f'REDEPLOYING {name} contract to new address')
    return None


def deploy_with_proxy(container, proxy_admin, deployer, *args):
    print("")

    deployment = check_and_get_deployment(container)
    if deployment:
        return deployment

    name = container.get_verification_info()["contract_name"]
    print(Fore.GREEN + f'DEPLOYING {name} ...')

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

    add_new_deploy(container, _instance.address)
    print(Fore.GREEN + f'Contract {name} deployed at {Fore.YELLOW}{_instance.address} {Fore.GREEN}under {Fore.RED} proxy')
    return container.at(_instance.address)


def deploy(container, deployer, *args):
    print("")

    deployment = check_and_get_deployment(container)
    if deployment:
        return deployment

    name = container.get_verification_info()["contract_name"]
    print(Fore.GREEN + f'DEPLOYING {name} ...')

    inst = None
    if args:
        inst = container.deploy(*args, get_opts(deployer))
    else:
        inst = container.deploy(get_opts(deployer))

    add_new_deploy(container, inst.address)
    print(Fore.GREEN + f'Contract {name} deployed at {Fore.YELLOW}{inst.address}')

    return inst


# deploy functions
def deploy_proxy_admin(deployer):
    return deploy(OpenzeppelinContractsProject.ProxyAdmin, deployer)


def deploy_auth_manager(deployer, proxy_admin, auth_super_admin):
    return deploy_with_proxy(AuthManager, proxy_admin, deployer, auth_super_admin)


def deploy_oracle_clone(deployer):
    return deploy(Oracle, deployer)


def deploy_oracle_master(deployer):
    return deploy(OracleMaster, deployer)


def deploy_ledger_clone(deployer):
    return deploy(Ledger, deployer)


def deploy_controller(deployer, proxy_admin):
    return deploy_with_proxy(Controller, proxy_admin, deployer)


def deploy_lido(deployer, proxy_admin, auth_manager, vksm, controller, treasury, developers):
    return deploy_with_proxy(Lido, proxy_admin, deployer, auth_manager, vksm, controller, treasury, developers)


# deployment
def main():
    deployer = accounts.at(CONFIG['deployer'])

    auth_super_admin = CONFIG['auth_sudo']
    treasury = CONFIG['treasury']
    developers = CONFIG['developers']

    roles = CONFIG['roles']
    oracles = CONFIG['oracles']
    oracle_quorum = CONFIG['quorum']
    vksm = CONFIG['precompiles']['vksm']
    xcm_transactor = CONFIG['precompiles']['xcm_transactor']
    relay_encoder = CONFIG['precompiles']['relay_encoder']
    x_token = CONFIG['precompiles']['x_token']

    era_sec = CONFIG['relay_spec']['era_duratation']
    max_validators_per_ledger = CONFIG['relay_spec']['max_validators_per_ledger']
    min_nominator_bond = CONFIG['relay_spec']['min_nominator_bond']

    root_derivative_index = CONFIG['root_derivative_index']
    root_derivative_account = ss58decode(get_derivative_account(CONFIG['sovereign_account'], root_derivative_index))
    stash_idxs = CONFIG['stash_indexes']
    stashes = [ss58decode(get_derivative_account(root_derivative_account, idx)) for idx in stash_idxs]

    xcm_max_weight = CONFIG['xcm_max_weight']
    xcm_weights = CONFIG['xcm_weights']


    proxy_admin = deploy_proxy_admin(deployer)

    controller = deploy_controller(deployer, proxy_admin)

    print(f"\n{Fore.GREEN}Configuring controller...")
    controller.init(root_derivative_index, root_derivative_account, vksm, relay_encoder, xcm_transactor, x_token, get_opts(deployer))
    controller.setMaxWeight(xcm_max_weight, get_opts(deployer))
    controller.setWeights([w | (1<<65) for w in xcm_weights], get_opts(deployer))

    auth_manager = deploy_auth_manager(deployer, proxy_admin, auth_super_admin)

    for role in roles:
        print(f"{Fore.GREEN}Setting role: {role}")
        if auth_manager.has(web3.solidityKeccak(["string"], [role]), roles[role]):
            print(f"{Fore.YELLOW}Role {role} already setted, skipping..")
        else:
            auth_manager.addByString(role, roles[role], get_opts(deployer))

    lido = deploy_lido(deployer, proxy_admin, auth_manager, vksm, controller, treasury, developers)

    oracle_clone = deploy_oracle_clone(deployer)

    oracle_master = deploy_oracle_master(deployer)

    oracle_master.initialize(oracle_clone, oracle_quorum, get_opts(deployer))

    ledger_clone = deploy_ledger_clone(deployer)

    print(f'\n{Fore.GREEN}Lido configuration...')
    lido.setOracleMaster(oracle_master, get_opts(roles['ROLE_ORACLE_MANAGER']))
    lido.setLedgerClone(ledger_clone, get_opts(roles['ROLE_ORACLE_MANAGER']))
    lido.setRelaySpec((1, era_sec, era_sec * (28+3), max_validators_per_ledger, min_nominator_bond), get_opts(roles['ROLE_SPEC_MANAGER']))
    oracle_master.setAnchorEra(0, 1, era_sec)

    print(f'\n{Fore.GREEN}Adding oracle members...')
    for oracle in ORACLES:
        print(f"{Fore.YELLOW}Adding oracle member: {oracle}")
        oracle_master.addOracleMember(oracle, get_opts(roles['ROLE_ORACLE_MEMBERS_MANAGER']))

    ledgers = []
    print(f'\n{Fore.GREEN}Adding ledgers...')
    for i in range(len(stashes)):
        s_bytes = ss58decode(stashes[i])
        print(f"{Fore.GREEN}Added ledger, idx: {stash_idxs[i]} stash: {stashes[i]}")
        lido.addLedger(s_bytes, s_bytes, stash_idxs[i], 100, get_opts(roles['ROLE_LEDGER_MANAGER']))
        ledgers.append(lido.findLedger(s_bytes))

#    for ledger in ledgers:
#        print("Refreshing allowances for ledger:", ledger)
#        Ledger.at(ledger).refreshAllowances(get_opts(deployer))
#
#    print("Refreshing allowances for lido")
#    lido.refreshAllowances(get_opts(roles['ROLE_LEDGER_MANAGER']));



def prompt():
    pass


