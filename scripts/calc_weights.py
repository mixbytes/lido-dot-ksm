read = 1_000_000 * 25
write = 1_000_000 * 100

NETWORK="kusama"

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
    as_derevative = (4_636_000 + rw(1, 1)) * 2
    bond_base = 60_400_000 + rw(5, 4)
    bond_extra_base = 98_893_000 + rw(8, 7)
    unbond_base = 106_618_000 + rw(12, 8)
    withdraw_unbonded_kill = 87_523_000 + rw(13, 11)
    withdraw_unbonded_per_unit = 0
    nominate_base = 71_169_000 + rw(12, 6)
    nominate_per_unit = 4_786_000 + rw(1, 0)
    chill_base = 60_865_000 + rw(8, 6)
    rebond_base = 96_930_000 + rw(9, 8)
    rebond_per_unit = 60_000
    transfer_to_para_base = 1_000_000_000
    transfer_to_relay_base = 500_000_000

if (NETWORK == "moonbase"):
    as_derevative = (4_542_000 + rw(1, 1)) * 2
    bond_base = 62_057_000 + rw(5, 4)
    bond_extra_base = 102_780_000 + rw(8, 7)
    unbond_base = 111_135_000 + rw(12, 8)
    withdraw_unbonded_kill = 89_350_000 + rw(13, 11)
    withdraw_unbonded_per_unit = 0
    nominate_base = 73_227_000 + rw(12, 6)
    nominate_per_unit = 4_820_000 + rw(1, 0)
    chill_base = 62_127_000 + rw(8, 6)
    rebond_base = 98_525_000 + rw(9, 8)
    rebond_per_unit = 69_000
    transfer_to_para_base = 875_000_000
    transfer_to_relay_base = 300_000_000

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
