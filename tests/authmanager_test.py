from brownie import reverts, web3


def test_add_remove(auth_manager, proxy_admin, accounts):

    role1 = web3.keccak(text='ROLE_SPEC_MANAGER').hex()

    assert auth_manager.has(role1, accounts[0])
    auth_manager.remove(role1, accounts[0], {'from': accounts[0]})

    with reverts("MEMBER_NOT_FOUND"):
        auth_manager.remove(role1, accounts[0], {'from': accounts[0]})

    assert not auth_manager.has(role1, accounts[0])

    auth_manager.add(role1, accounts[0], {'from': accounts[0]})
    with reverts("ALREADY_MEMBER"):
        auth_manager.add(role1, accounts[0], {'from': accounts[0]})

    assert auth_manager.has(role1, accounts[0])


def test_remove_superuser(auth_manager, proxy_admin, accounts):
    super_role = auth_manager.SUPER_ROLE()
    # manager has the only super accounts[0]
    with reverts("INVALID"):
        auth_manager.remove(super_role, accounts[0], {'from': accounts[0]})
    # Add new super user
    auth_manager.add(super_role, accounts[1], {'from': accounts[0]})
    # It cannot remove itself
    with reverts("INVALID"):
        auth_manager.remove(super_role, accounts[1], {'from': accounts[1]})
    # now the new super can remove the old one
    auth_manager.remove(super_role, accounts[0], {'from': accounts[1]})
    # but cannot remove itself
    with reverts("INVALID"):
        auth_manager.remove(super_role, accounts[1], {'from': accounts[1]})
