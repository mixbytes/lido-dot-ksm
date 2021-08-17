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
    lm = Ledger.deploy({'from': accounts[0]})
    l = Lido.deploy(vKSM, aux, vAccounts, {'from': accounts[0]})
    l.setLedgerMaster(lm)
    return l


@pytest.fixture(scope="module")
def oracle(lido, LidoOracle, Ledger, accounts):
    o = LidoOracle.deploy({'from': accounts[0]})
    o.setLido(lido, {'from': accounts[0]})
    lido.setOracle(o, {'from': accounts[0]})
    return o