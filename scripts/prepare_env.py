import json
import yaml
from pathlib import Path
from brownie import *

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

    return (user, lido, vksm, oracle_master, wstksm, auth_manager, controller)