import json
import yaml
from pathlib import Path
from brownie import *
from substrateinterface import Keypair
from hashlib import blake2b
import base58
from colorama import Fore

NETWORK="kusama"

GAS_PRICE = "10 gwei"
GAS_LIMIT = 10*10**6

# utils
def ss58decode(address):
    return Keypair(ss58_address=address).public_key


def get_opts(sender, gas_price=GAS_PRICE, gas_limit=GAS_LIMIT):
    return {'from': sender, 'gas_price': gas_price, 'gas_limit': gas_limit}


def get_derivative_account(root_account, index):
    seed_bytes = b'modlpy/utilisuba'

    root_account_bytes = bytes.fromhex(Keypair(root_account).public_key[2:])
    index_bytes = int(index).to_bytes(2, 'little')

    entropy = blake2b(seed_bytes + root_account_bytes + index_bytes, digest_size=32).digest()
    input_bytes = bytes([42]) + entropy
    checksum = blake2b(b'SS58PRE' + input_bytes).digest()
    return base58.b58encode(input_bytes + checksum[:2]).decode()


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


def main():
    lido = Lido.at(DEPLOYMENTS['Lido'])

    root_derivative_index = CONFIG['root_derivative_index']
    root_derivative_account = ss58decode(get_derivative_account(CONFIG['sovereign_account'], root_derivative_index))

    ledger_stashes = lido.getStashAccounts()
    print(f"{Fore.YELLOW}Existed ledgers: {ledger_stashes}")
    stash_idx = len(ledger_stashes) + 1

    stash = ''

    while(True):
        stash = ss58decode(get_derivative_account(root_derivative_account, stash_idx))
        s_bytes = ss58decode(stash)
        if not(s_bytes in ledger_stashes):
            break
        stash_idx += 1

    stash = ss58decode(get_derivative_account(root_derivative_account, stash_idx))

    s_bytes = ss58decode(stash)
    print(f"{Fore.GREEN}Adding ledger, idx: {stash_idx} stash: {stash}")

    calldata = lido.addLedger.encode_input(s_bytes, s_bytes, stash_idx)
    print(f"{Fore.GREEN}Calldata: {calldata}")