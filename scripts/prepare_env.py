import json
import yaml
from pathlib import Path
from brownie import *
from substrateinterface import Keypair
from hashlib import blake2b
import base58


def get_derivative_account(root_account, index):
    seed_bytes = b'modlpy/utilisuba'

    root_account_bytes = bytes.fromhex(Keypair(root_account).public_key[2:])
    index_bytes = int(index).to_bytes(2, 'little')

    entropy = blake2b(seed_bytes + root_account_bytes + index_bytes, digest_size=32).digest()
    input_bytes = bytes([42]) + entropy
    checksum = blake2b(b'SS58PRE' + input_bytes).digest()
    return base58.b58encode(input_bytes + checksum[:2]).decode()




class Contracts:
    user = None
    proxy_admin = None
    lido = None
    vksm = None
    oracle_master = None
    wstksm = None
    auth_manager = None
    controller = None
    ledgers = None
    validators = None

    def __init__(self, _user, _proxy_admin, _lido, _vksm, _oracle_master, _wstksm, _auth_manager, _controller, _ledgers, _validators):
        self.user = _user
        self.proxy_admin = _proxy_admin
        self.lido = _lido
        self.vksm = _vksm
        self.oracle_master = _oracle_master
        self.wstksm = _wstksm
        self.auth_manager = _auth_manager
        self.controller = _controller
        self.ledgers = _ledgers
        self.validators = _validators

NETWORK="kusama"

def load_deployments(network):
    path = './deployments/' + network + '.json'
    if Path(path).is_file():
        with open(path) as file:
            return json.load(file)
    else:
        return {}

def load_deployment_config(network):
    with open('./deployment-config.yml') as file:
        return yaml.safe_load(file)['networks'][network]

CONFIG = load_deployment_config(NETWORK)
DEPLOYMENTS = load_deployments(NETWORK)


def gen_ledger_account(index):
    sovereign = CONFIG['sovereign_account']
    root_index = CONFIG['root_derivative_index']

    controller = get_derivative_account(sovereign, root_index)
    return get_derivative_account(controller, index)


#contracts = run('./scripts/prepare_env.py') from brownie console --network=moonbase
def main():
    user = accounts.load(CONFIG['deployer'])

    proxy_admin = ProxyAdminMock.at(DEPLOYMENTS['ProxyAdmin'])

    lido = Lido.at(DEPLOYMENTS['Lido'])
    vksm = vKSM_mock.at(CONFIG['precompiles']['vksm'])
    oracle_master = OracleMaster.at(DEPLOYMENTS['OracleMaster'])
    wstksm = WstKSM.at(DEPLOYMENTS['WstKSM'])
    auth_manager = AuthManager.at(DEPLOYMENTS['AuthManager'])
    controller = Controller.at(DEPLOYMENTS['Controller'])

    ledgers = [ Ledger.at(addr) for addr in lido.getLedgerAddresses() ]

    # current validators in moonbase
    validator_1 = Keypair("5CX2ov8tmW6nZwy6Eouzc7VxFHcAyZioNm5QjEUYc7zjbS66").public_key
    validator_2 = Keypair("5FRiNmoi9HFGFrY3K9xsSCeewRtA2pcXTZVZrwLacPCfvHum").public_key
    validator_3 = Keypair("5EcdgHV81hu6YpPucSMrWbdQRBUr18XypiiGsgQ7HREYdrWG").public_key
    validator_4 = Keypair("5FCEmzonc34D2SXXv2CMsDoFWCVivH2a2Mwe32t9BT1TcpAD").public_key
    validator_5 = Keypair("5Ehgvgk1LERD5aTEWw6HLdKZurBqcRYbHXvrAtTgYPhUpr1R").public_key

    validators = [validator_1, validator_2, validator_3, validator_4, validator_5]

    # 5CxXVE7pHqzR4kzfz6nop529odm8eVemFFtStruyNQvdTopo
    # 5GxgDNMhbvMhuJzXC2voX5nKUyNaNQFCZxgnoa18eGiBBZwt
    # 5Cqb9WXVQQF73a1dcJEBFS2bWrukaC6dmzjeWZeJHj3NMwvB

    return Contracts(user, proxy_admin, lido, vksm, oracle_master, wstksm, auth_manager, controller, ledgers, validators)
