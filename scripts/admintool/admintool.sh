#!/bin/bash
set -e -o pipefail

display_help()
{
    echo
    echo "usage: $0 -a admin_id -l ip_list -n consensus_name -m crypto_method -d block_duration -t"
    echo "option:"
    echo "-a admin_id    admin identifier"
    echo "    default value is 'admin'"
    echo
    echo "-l ip_list     list all the node's IP and port"
    echo "    default value is '127.0.0.1:4000,127.0.0.1:4001,127.0.0.1:4002,127.0.0.1:4003'"
    echo
    echo "-n consensus_name  name of consensus algorithm"
    echo "    default value is 'tendermint', other is 'raft' and 'poa'"
    echo
    echo "-m crypto_method    name of crypto algorithm"
    echo "    default value is 'SECP'"
    echo
    echo "-d block_duration    block generating duration(millisecond)"
    echo "    default value is '3000'"
    echo
    echo "-t consensus test flag, only valid for tendermint"
    echo
    echo "-h enable jsonrpc http"
    echo "   default enable 'true'"
    echo
    echo "-w enable jsonrpc websocket "
    echo "   default enable 'true'"
    echo
    echo "-H define jsonrpc HTTP port"
    echo "   default port is '1337'"
    echo
    echo "-W define jsonrpc websocket port"
    echo "   default port is '4337'"
    echo
    echo "-k start with kafka"
    echo
    echo "-Q node id"
    echo
    exit 0
}

CONFIG_DIR=${PWD}
BINARY_DIR=$(readlink -f $(dirname $(readlink -f $0))/../..)
export PATH=${PATH}:${BINARY_DIR}/bin

# parse options
while getopts 'a:l:n:m:d:t:h:w:H:W:Q:k' OPT; do
    case $OPT in
        a)
            ADMIN_ID="$OPTARG";;
        l)
            IP_LIST="$OPTARG";;
        n)
            CONSENSUS_NAME="$OPTARG";;
        m)
            CRYPTO_METHOD="$OPTARG";;
        d)
            DURATION="$OPTARG";;
        t)
            IS_TEST=true;;
        k)
            START_KAFKA=true;;
        h)
            HTTP_ENABLE="$OPTARG";;
        w)
            WS_ENABLE="$OPTARG";;
        H)
            HTTP_PORT="$OPTARG";;
        W)
            WS_PORT="$OPTARG";;
        Q)
            NODE="$OPTARG";;
        ?)
            display_help
    esac
done

#set default value
: ${ADMIN_ID:="admin"}

[ -z "$IP_LIST" ] && DEV_MOD=1
: ${IP_LIST:="127.0.0.1:4000,127.0.0.1:4001,127.0.0.1:4002,127.0.0.1:4003"}

#calc size of nodes
TMP=${IP_LIST//[^\:]}
SIZE=${#TMP}

: ${CONSENSUS_NAME:="tendermint"}

: ${CRYPTO_METHOD:="SECP"}

: ${DURATION:=3000}

: ${IS_TEST:=false}

sed -i "s/tendermint/$CONSENSUS_NAME/g" ${BINARY_DIR}/bin/cita

create_genesis(){
    if [ ! -e "${BINARY_DIR}/scripts/admintool/init_data.json" ]; then
        cp ${BINARY_DIR}/scripts/admintool/init_data_example.json ${CONFIG_DIR}/init_data.json
    else
        cp ${BINARY_DIR}/scripts/admintool/init_data.json ${CONFIG_DIR}/init_data.json
    fi
    python ${BINARY_DIR}/scripts/admintool/create_genesis.py --authorities "${CONFIG_DIR}/authorities" --init_data "${CONFIG_DIR}/init_data.json" --resource "${CONFIG_DIR}/resource/"
    rm -rf ${CONFIG_DIR}/init_data.json
}

create_key(){
    python ${BINARY_DIR}/scripts/admintool/create_keys_addr.py ${CONFIG_DIR} ${1} create_key_addr
}

consensus(){
    python ${BINARY_DIR}/scripts/admintool/create_node_config.py ${CONFIG_DIR} $CONSENSUS_NAME ${1} $DURATION $IS_TEST
}

# rabbitmq and kafka
env(){
    rm -rf ${CONFIG_DIR}/node${1}/.env
    port=`expr 9092 + ${1}`
    echo "KAFKA_URL=localhost:$port"                             >> ${CONFIG_DIR}/node${1}/.env
    echo "AMQP_URL=amqp://guest:guest@localhost/node${1}"     >> ${CONFIG_DIR}/node${1}/.env
    echo "DATA_PATH=./data"                                       >> ${CONFIG_DIR}/node${1}/.env
}

auth(){
    cp -f ${BINARY_DIR}/scripts/admintool/auth_example.json  ${CONFIG_DIR}/node${1}/auth.json
}

network(){
    python ${BINARY_DIR}/scripts/admintool/create_network_config.py ${CONFIG_DIR} ${1} $SIZE $IP_LIST
    mv ${CONFIG_DIR}/network.toml ${CONFIG_DIR}/node${1}/
}


chain(){
    cp genesis.json ${CONFIG_DIR}/node${1}/genesis.json
    if [ -d "${CONFIG_DIR}/resource" ]; then
        cp -rf resource ${CONFIG_DIR}/node${1}/
    fi
    cp -f ${BINARY_DIR}/scripts/admintool/chain_check_example.json      ${CONFIG_DIR}/node${1}/chain.json
}

jsonrpc(){
    H_PORT=${HTTP_PORT:-1337}
    W_PORT=${WS_PORT:-4337}
    if [ -n "$DEV_MOD" ]; then
        ((H_PORT=${H_PORT}+${1}))
        ((W_PORT=${W_PORT}+${1}))
    fi
    python ${BINARY_DIR}/scripts/admintool/create_jsonrpc_config.py ${HTTP_ENABLE:-"true"} $H_PORT ${WS_ENABLE:-"true"} $W_PORT ${CONFIG_DIR}
    mv ${CONFIG_DIR}/jsonrpc.json ${CONFIG_DIR}/node${1}/
}

# Kafka Configuration creating
kafka(){
    if [ "$START_KAFKA" == "true" ];then
        ${BINARY_DIR}/scripts/admintool/create_kafka_config.sh $1 $CONFIG_DIR/node${1}
        ${BINARY_DIR}/scripts/admintool/create_zookeeper_config.sh $1 $CONFIG_DIR/node${1}
    fi
}

forever(){
    cp -f ${BINARY_DIR}/scripts/admintool/forever_example.toml          ${CONFIG_DIR}/node${1}/forever.toml
}

node(){
    mkdir -p ${CONFIG_DIR}/node${1}
    cp -rf $CONFIG_DIR/backup/*  ${CONFIG_DIR}/
    create_key $1
    jsonrpc $1
    consensus $1
    chain $1
    python ${BINARY_DIR}/scripts/admintool/create_network_config.py ${CONFIG_DIR} 1 $SIZE $IP_LIST
    mv ${CONFIG_DIR}/network.toml ${CONFIG_DIR}/node${1}/
    auth $1
    env $1
    kafka $1
    forever $1
}

default(){
    for ((ID=0;ID<$SIZE;ID++))
    do
        mkdir -p ${CONFIG_DIR}/node${ID}
        create_key $ID
    done
    create_genesis
    for ((ID=0;ID<$SIZE;ID++))
    do
        mkdir -p ${CONFIG_DIR}/node${ID}
        jsonrpc $ID
        consensus $ID
        chain $ID
        network $ID
        auth $ID
        env $ID
        kafka $ID
        forever $ID
    done
    mkdir -p $CONFIG_DIR/backup
    rm -rf $CONFIG_DIR/backup/*
    mv ${CONFIG_DIR}/*.json ${CONFIG_DIR}/authorities $CONFIG_DIR/backup/
    if [ -d "${CONFIG_DIR}/resource" ]; then
        mv ${CONFIG_DIR}/resource $CONFIG_DIR/backup/
    fi
}

echo "************************begin create node config******************************"
if [ -z $NODE ]; then
    default
else
    node $NODE
fi
echo "************************end create node config********************************"
echo "WARN: remember then delete all privkey files!!!"
