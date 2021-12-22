import json
import yaml
from pathlib import Path
from brownie import *
from substrateinterface import Keypair

NETWORK="moonbase"

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

#contracts = run('./scripts/prepare_env.py') from brownie console --network=moonbase
def main():
    user = accounts.load(CONFIG['deployer'])

    lido = Lido.at(DEPLOYMENTS['Lido'])
    vksm = vKSM_mock.at(CONFIG['precompiles']['vksm'])
    oracle_master = OracleMaster.at(DEPLOYMENTS['OracleMaster'])
    wstksm = WstKSM.at(DEPLOYMENTS['WstKSM'])
    auth_manager = AuthManager.at(DEPLOYMENTS['AuthManager'])
    controller = Controller.at(DEPLOYMENTS['Controller'])

    ledger_1 = Ledger.at(lido.enabledLedgers(0))
    ledger_2 = Ledger.at(lido.enabledLedgers(1))
    ledger_3 = Ledger.at(lido.enabledLedgers(2))

    # current validators in moonbase
    validator_1 = Keypair("5CX2ov8tmW6nZwy6Eouzc7VxFHcAyZioNm5QjEUYc7zjbS66").public_key
    validator_2 = Keypair("5FRiNmoi9HFGFrY3K9xsSCeewRtA2pcXTZVZrwLacPCfvHum").public_key
    validator_3 = Keypair("5EcdgHV81hu6YpPucSMrWbdQRBUr18XypiiGsgQ7HREYdrWG").public_key
    validator_4 = Keypair("5FCEmzonc34D2SXXv2CMsDoFWCVivH2a2Mwe32t9BT1TcpAD").public_key
    validator_5 = Keypair("5Ehgvgk1LERD5aTEWw6HLdKZurBqcRYbHXvrAtTgYPhUpr1R").public_key

    return (user, lido, vksm, oracle_master, wstksm, auth_manager, controller, ledger_1, ledger_2, ledger_3)