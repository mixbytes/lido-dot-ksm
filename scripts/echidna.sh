#!/bin/sh

set -e 

DIR=$(dirname $0)
ROOT=$(realpath $DIR/..)

yarn install

docker run --rm -v ${ROOT}:/lido -w /lido  ghcr.io/crytic/echidna/echidna  /bin/bash -c \
   'apt update && apt install  software-properties-common -y && \
    add-apt-repository ppa:ethereum/ethereum && \
    apt-get update && \
    apt-get install solc -y && \
    slither-flat contracts/test/CrytikDistributeTest.sol --contract Lido2Test --solc-remaps @openzeppelin/=node_modules/@openzeppelin/ && \
    cd crytic-export/flattening/ && \
    echidna-test ./Lido2Test.sol  --contract=Lido2Test'