#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

removeGsrRegistry() {
    echo ""
}

removeGsrSchemas() {
    kafka-topics.sh --command-config $OSCI_CNF_DIR/kafka-client.properties --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --delete --topic '__amazon_msk_connect.*|fullfillment.*|schemahistory.*'
    listTopics
}