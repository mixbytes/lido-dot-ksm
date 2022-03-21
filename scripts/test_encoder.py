from brownie import *


def main():
    # NOTE: change address to encoder address in specific chain
    encoder = RelayEncoder.at('0x14C9D16e3d1f688609761F82437Be62E9aDB1C76')
    enc = interface.IRelayEncoder('0x0000000000000000000000000000000000000805')

    # bond
    i = 1
    while i < 2**32:
        if (encoder.encode_bond(i, i, "0x00") != enc.encode_bond(i, i, "0x00")):
            print("Error: " + str(i))
        i *= 2

    # bond_extra
    i = 1
    while i < 2**32:
        if (encoder.encode_bond_extra(i) != enc.encode_bond_extra(i)):
            print("Error: " + str(i))
        i *= 2

    # unbond
    i = 1
    while i < 2**32:
        if (encoder.encode_unbond(i) != enc.encode_unbond(i)):
            print("Error: " + str(i))
        i *= 2

    # rebond
    i = 1
    while i < 2**32:
        if (encoder.encode_rebond(i) != enc.encode_rebond(i)):
            print("Error: " + str(i))
        i *= 2

    # withdraw_unbonded
    i = 1
    while i < 2**32:
        if (encoder.encode_withdraw_unbonded(i) != enc.encode_withdraw_unbonded(i)):
            print("Error: " + str(i))
        i *= 2

    # nominate
    i = 1
    nominees = [i]
    while i < 2**32:
        if (encoder.encode_nominate(nominees) != enc.encode_nominate(nominees)):
            print("Error: " + str(i))
        i *= 2
        nominees.append(i)