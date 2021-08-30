import pytest


@pytest.fixture(scope="function", autouse=True)
def isolate(fn_isolation):
    pass


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
def auth_manager(AuthManager, accounts):
    am = AuthManager.deploy(accounts[0], {'from': accounts[0]})
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
def lido(Lido, vKSM, vAccounts, aux, auth_manager, oracle_master, chain, Ledger, accounts):
    lc = Ledger.deploy({'from': accounts[0]})
    l = Lido.deploy({'from': accounts[0]})
    l.initialize(auth_manager, vKSM, aux, vAccounts, {'from': accounts[0]})
    l.setLedgerClone(lc)
    oracle_master.setLido(l)
    l.setOracleMaster(oracle_master)
    era_sec = 60 * 60 * 6
    l.setRelaySpec((chain.time(), era_sec, era_sec * 28, 16, 1)) # kusama settings except min nominator bond
    return l


