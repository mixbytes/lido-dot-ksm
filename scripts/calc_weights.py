read = 1_000_000 * 25
write = 1_000_000 * 100

NETWORK="moonbase"

as_derevative = 0
bond_base = 0
bond_extra_base = 0
unbond_base = 0
withdraw_unbonded_kill = 0
withdraw_unbonded_per_unit = 0
rebond_base = 0
rebond_per_unit = 0
chill_base = 0
nominate_base = 0
nominate_per_unit = 0
transfer_to_para_base = 0
transfer_to_relay_base = 0

def rw(rd, wr):
    return read * rd + write * wr

if (NETWORK == "kusama"):
    as_derevative = 150_000_000 * 2 # TODO: change ((as_derevative + rw(1,1)) * 2)
    bond_base = 47_083_000 + rw(5, 4)
    bond_extra_base = 79_677_000 + rw(8, 7)
    unbond_base = 87_481_000 + rw(12, 8)
    withdraw_unbonded_kill = 72_430_000 + rw(13, 11)
    withdraw_unbonded_per_unit = 2_000
    nominate_base = 60_257_000 + rw(12, 6)
    nominate_per_unit = 4_191_000 + rw(1, 0)
    chill_base = 52_552_000 + rw(8, 6)
    rebond_base = 78_279_000 + rw(9, 8)
    rebond_per_unit = 55_000
    transfer_to_para_base = 1_100_000_000 # TODO: change
    transfer_to_relay_base = 4_000_000_000

if (NETWORK == "moonbase"):
    as_derevative = 131_000_000 * 2
    bond_base = 47_262_000 + rw(5, 4)
    bond_extra_base = 79_887_000 + rw(8, 7)
    unbond_base = 85_963_000 + rw(12, 8)
    withdraw_unbonded_kill = 72_077_000 + rw(13, 11)
    withdraw_unbonded_per_unit = 0
    nominate_base = 59_971_000 + rw(12, 6)
    nominate_per_unit = 4_119_000 + rw(1, 0)
    chill_base = 51_777_000 + rw(8, 6)
    rebond_base = 76_896_000 + rw(9, 8)
    rebond_per_unit = 51_000
    transfer_to_para_base = 875_000_000
    transfer_to_relay_base = 4_000_000_000

print('         - ' + '{0:_}'.format(as_derevative) + ' #AS_DERIVATIVE')
print('         - ' + '{0:_}'.format(bond_base) + ' #BOND_BASE')
print('         - ' + '{0:_}'.format(bond_extra_base) + ' #BOND_EXTRA_BASE')
print('         - ' + '{0:_}'.format(unbond_base) + ' #UNBOND_BASE')
print('         - ' + '{0:_}'.format(withdraw_unbonded_kill) + ' #WITHDRAW_UNBONDED_KILL')
print('         - ' + '{0:_}'.format(withdraw_unbonded_per_unit) + ' #WITHDRAW_UNBONDED_PER_UNIT')
print('         - ' + '{0:_}'.format(rebond_base) + ' #REBOND_BASE')
print('         - ' + '{0:_}'.format(rebond_per_unit) + ' #REBOND_PER_UNIT')
print('         - ' + '{0:_}'.format(chill_base) + ' #CHILL_BASE')
print('         - ' + '{0:_}'.format(nominate_base) + ' #NOMINATE_BASE')
print('         - ' + '{0:_}'.format(nominate_per_unit) + ' #NOMINATE_PER_UNIT')
print('         - ' + '{0:_}'.format(transfer_to_para_base) + ' #TRANSFER_TO_PARA_BASE')
print('         - ' + '{0:_}'.format(transfer_to_relay_base) + ' #TRANSFER_TO_RELAY_BASE')
