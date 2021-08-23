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
def lido(Lido, vKSM, vAccounts, aux, Ledger, accounts):
    lc = Ledger.deploy({'from': accounts[0]})
    l = Lido.deploy({'from': accounts[0]})
    l.initialize(vKSM, aux, vAccounts, {'from': accounts[0]})
    l.setLedgerClone(lc)
    return l


@pytest.fixture(scope="module")
def oracle_master(lido, Oracle, OracleMaster, Ledger, accounts, chain):
    o = Oracle.deploy({'from': accounts[0]})
    om = OracleMaster.deploy({'from': accounts[0]})
    om.initialize(lido, accounts[0], accounts[0], accounts[0], o, {'from': accounts[0]})
    om.setRelaySpec(chain.time(), 60 * 60 * 24 * 6) # kusama period
    lido.setOracleMaster(om, {'from': accounts[0]})
    return om