#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

listTopics() {
    printHeading "KAFKA TOPICS"
    loadMskClusterConfig
    echo -ne "[INFO]: The following is all topics on msk cluster [ $MSK_CLUSTER_NAME ] ...\n\n"
    case $MSK_CLUSTER_AUTH_TYPE in
        NONE)
            kafka-topics.sh \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --list
        ;;
        IAM)
            kafka-topics.sh \
                --command-config $OSCI_CNF_DIR/kafka-client.properties \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --list
        ;;
    esac
    echo ""
}

consumeTopic() {
    printHeading "KAFKA TOPIC [ $TOPIC ]"
    checkKafkaClientCliOpts
    loadMskClusterConfig
    case $MSK_CLUSTER_AUTH_TYPE in
        NONE)
            kafka-console-consumer.sh \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --from-beginning --topic $TOPIC
        ;;
        IAM)
            kafka-console-consumer.sh \
                --consumer.config $OSCI_CNF_DIR/kafka-client.properties \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --from-beginning --topic $TOPIC
        ;;
    esac

}

printKafkaMessage() {
    topic="$1"
    printHeading "KAFKA TOPIC [ $topic ]"
}

cleanTopics() {
    loadMskClusterConfig
    case $MSK_CLUSTER_AUTH_TYPE in
        NONE)
            kafka-topics.sh \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --delete \
                --topic "__amazon_msk_connect.*|osci.*|_schemas"
        ;;
        IAM)
            kafka-topics.sh \
                --command-config $OSCI_CNF_DIR/kafka-client.properties \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --delete \
                --topic "__amazon_msk_connect.*|osci.*|_schemas"
        ;;
    esac
    listTopics
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkKafkaClientCliOpts() {
    echo -ne "[INFO]: Checking the kafka client command options...\n\n"
    if [[ -z $TOPIC ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --topic ]

EOF
        exit 1
    fi
}
