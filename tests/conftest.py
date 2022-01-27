import pytest
from pathlib import Path
from brownie import project, config

# import oz project
project.load(Path.home() / ".brownie" / "packages" / config["dependencies"][0])
if hasattr(project, 'OpenzeppelinContracts410Project'):
    OpenzeppelinContractsProject = project.OpenzeppelinContracts410Project
else:
    OpenzeppelinContractsProject = project.OpenzeppelinContractsProject


def deploy_with_proxy(contract, proxy_admin, *args):
    TransparentUpgradeableProxy = OpenzeppelinContractsProject.TransparentUpgradeableProxy
    owner = proxy_admin.owner()
    logic_instance = contract.deploy({'from': owner})
    encoded_inputs = logic_instance.initialize.encode_input(*args)

    proxy_instance = TransparentUpgradeableProxy.deploy(
        logic_instance,
        proxy_admin,
        encoded_inputs,
        {'from': owner, 'gas_limit': 10**6}
    )

    TransparentUpgradeableProxy.remove(proxy_instance)
    return contract.at(proxy_instance.address, owner=owner)


@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    pass


@pytest.fixture(scope="module")
def proxy_admin(accounts):
    ProxyAdmin = OpenzeppelinContractsProject.ProxyAdmin
    return ProxyAdmin.deploy({'from': accounts[0]})


@pytest.fixture(scope="module")
def vKSM(vKSM_mock, accounts):
    return vKSM_mock.deploy({'from': accounts[0]})


@pytest.fixture(scope="module")
def auth_manager(AuthManager, proxy_admin, accounts):
    am = deploy_with_proxy(AuthManager, proxy_admin, accounts[0])
    am.addByString('ROLE_SPEC_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_BEACON_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_PAUSE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_FEE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_LEDGER_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_STAKE_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_ORACLE_MEMBERS_MANAGER', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_ORACLE_QUORUM_MANAGER', accounts[0], {'from': accounts[0]})

    am.addByString('ROLE_SET_TREASURY', accounts[0], {'from': accounts[0]})
    am.addByString('ROLE_SET_DEVELOPERS', accounts[0], {'from': accounts[0]})
    return am


@pytest.fixture(scope="module")
def oracle_master(Oracle, OracleMaster, Ledger, accounts, chain):
    o = Oracle.deploy({'from': accounts[0]})
    om = OracleMaster.deploy({'from': accounts[0]})
    om.initialize(o, 1, {'from': accounts[0]})
    return om


@pytest.fixture(scope="module")
def withdrawal(Withdrawal, vKSM, accounts):
    wdr = Withdrawal.deploy({'from': accounts[0]})
    wdr.initialize(35, vKSM, {'from': accounts[0]})
    return wdr


@pytest.fixture(scope="module")
def controller(Controller_mock, accounts, chain):
    c = Controller_mock.deploy({'from': accounts[0]})
    return c


@pytest.fixture(scope="module")
def admin(accounts):
    return accounts[0]


@pytest.fixture(scope="module")
def treasury(accounts):
    return accounts.add()


@pytest.fixture(scope="module")
def developers(accounts):
    return accounts.add()


@pytest.fixture(scope="module")
def lido(Lido, vKSM, controller, auth_manager, oracle_master, withdrawal, proxy_admin, chain, Ledger, LedgerBeacon, LedgerFactory, accounts, developers, treasury):
    lc = Ledger.deploy({'from': accounts[0]})
    _lido = deploy_with_proxy(Lido, proxy_admin, auth_manager, vKSM, controller, developers, treasury, oracle_master, withdrawal, 50000 * 10**18)
    ledger_beacon = LedgerBeacon.deploy(lc, _lido, {'from': accounts[0]})
    ledger_factory = LedgerFactory.deploy(_lido, ledger_beacon, {'from': accounts[0]})
    _lido.setLedgerBeacon(ledger_beacon)
    _lido.setLedgerFactory(ledger_factory)
    era_sec = 60 * 60 * 6
    _lido.setRelaySpec((chain.time(), era_sec, era_sec * 28, 16, 1, 0))  # kusama settings except min nominator bond
    oracle_master.setAnchorEra(0, chain.time(), era_sec)
    return _lido


@pytest.fixture(scope="module")
def mocklido(Lido, LedgerMock, LedgerBeacon, LedgerFactory, Oracle, OracleMaster, Withdrawal, vKSM, controller, auth_manager, admin, developers, treasury):
    lc = LedgerMock.deploy({'from': admin})
    o = Oracle.deploy({'from': admin})
    om = OracleMaster.deploy({'from': admin})
    om.initialize(o, 1, {'from': admin})
    wdr = Withdrawal.deploy({'from': admin})
    wdr.initialize(35, vKSM, {'from': admin})

    _lido = Lido.deploy({'from': admin})
    _lido.initialize(auth_manager, vKSM, controller, developers, treasury, om, wdr, 50000 * 10**18, {'from': admin})
    ledger_beacon = LedgerBeacon.deploy(lc, _lido, {'from': admin})
    ledger_factory = LedgerFactory.deploy(_lido, ledger_beacon, {'from': admin})
    _lido.setLedgerBeacon(ledger_beacon, {'from': admin})
    _lido.setLedgerFactory(ledger_factory, {'from': admin})

    return _lido


@pytest.fixture(scope="module")
def mockledger(mocklido, admin, LedgerMock):
    mocklido.addLedger(0x01, 0x01, 0, {'from': admin})
    return LedgerMock.at(mocklido.findLedger(0x01))


@pytest.fixture(scope="module")
def wstKSM(lido, WstKSM, vKSM, admin):
    _wstKSM = WstKSM.deploy(lido, vKSM, {'from': admin})
    return _wstKSM