import pytest
from pathlib import Path
from brownie import project, config, network, Contract

# import oz project
project.load(Path.home() / ".brownie" / "packages" / config["dependencies"][0])


def deploy_with_proxy(contract, proxy_admin, *args):
    TransparentUpgradeableProxy = project.OpenzeppelinContractsProject.TransparentUpgradeableProxy
    owner = proxy_admin.owner()
    logic_instance = contract.deploy({'from': owner})
    encoded_inputs = logic_instance.initialize.encode_input(*args)
    contract_name = contract._name

    proxy_instance = TransparentUpgradeableProxy.deploy(
        logic_instance,
        proxy_admin,
        encoded_inputs,
        {'from': owner, 'gas_limit': 10**6}
    )

    # dirty hack to replace cached contract abi inside brownie state
    network.__dict__['state'].__dict__['_remove_contract'](proxy_instance)
    with_proxy = Contract.from_abi(contract_name, proxy_instance, contract.abi, owner)
    network.__dict__['state'].__dict__['_add_contract'](with_proxy)

    return with_proxy


@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    pass


@pytest.fixture(scope="module")
def proxy_admin(accounts):
    ProxyAdmin = project.OpenzeppelinContractsProject.ProxyAdmin
    return ProxyAdmin.deploy({'from': accounts[0]})


@pytest.fixture(scope="module")
def vKSM(vKSM_mock, accounts):
    return vKSM_mock.deploy({'from': accounts[0]})


@pytest.fixture(scope="module")
def vAccounts(vAccounts_mock, vKSM, accounts):
    return vAccounts_mock.deploy(vKSM, {'from': accounts[0]})


@pytest.fixture(scope="module")
def aux(AUX_mock, accounts):
    return AUX_mock.deploy({'from': accounts[0]})


@pytest.fixture(scope="module")
def auth_manager(AuthManager, proxy_admin, accounts):
    am = deploy_with_proxy(AuthManager, proxy_admin, accounts[0])
    am.addByString('ROLE_SPEC_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_PAUSE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_FEE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_ORACLE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_LEDGER_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_STAKE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_ORACLE_MEMBERS_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_ORACLE_QUORUM_MANAGER', accounts[0], {'from': accounts[0]})
    return am


@pytest.fixture(scope="module")
def oracle_master(Oracle, OracleMaster, Ledger, accounts, chain):
    o = Oracle.deploy({'from': accounts[0]})
    om = OracleMaster.deploy({'from': accounts[0]})
    om.initialize(o, 1, {'from': accounts[0]})
    return om


@pytest.fixture(scope="module")
def lido(Lido, vKSM, vAccounts, aux, auth_manager, oracle_master, proxy_admin, chain, Ledger, accounts):
    lc = Ledger.deploy({'from': accounts[0]})
    l = deploy_with_proxy(Lido, proxy_admin, auth_manager, vKSM, aux, vAccounts)
    l.setLedgerClone(lc)
    oracle_master.setLido(l)
    l.setOracleMaster(oracle_master)
    era_sec = 60 * 60 * 6
    l.setRelaySpec((chain.time(), era_sec, era_sec * 28, 16, 1)) # kusama settings except min nominator bond
    return l


