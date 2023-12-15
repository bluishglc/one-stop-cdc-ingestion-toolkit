#!/usr/bin/env bash

export OSCI_HOME="$(cd "`dirname $(readlink -nf "$0")`"/..; pwd -P)"

source "$OSCI_HOME/bin/constants.sh"
source "$OSCI_HOME/bin/common.sh"
source "$OSCI_HOME/bin/util.sh"
source "$OSCI_HOME/bin/s3.sh"
source "$OSCI_HOME/bin/vpc.sh"
source "$OSCI_HOME/bin/msk-cluster.sh"
source "$OSCI_HOME/bin/mskc-plugin.sh"
source "$OSCI_HOME/bin/mskc-worker.sh"
source "$OSCI_HOME/bin/mskc-connector.sh"
source "$OSCI_HOME/bin/kafka-client.sh"
source "$OSCI_HOME/bin/global.sh"

# variables with default values, could be overridden by cli options
MSK_CLUSTER_AUTH_TYPE="NONE"
MSKC_CONNECTOR_MCU_COUNT=1
MSKC_CONNECTOR_WORKER_COUNT=1
MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY="BACKWARD"

parseArgs() {
    optString="home-bucket:,vpc-id:,subnet-ids:,security-group-ids:,\
               msk-cluster-name:,msk-cluster-name:,msk-cluster-arn:,msk-cluster-auth-type:,kafka-bootstrap-servers:,topic:,\
               mskc-plugin-name:,mskc-plugin-arn:,mskc-worker-config-name:,mskc-worker-config-arn:,\
               mskc-connector-name:,mskc-connector-mcu-count:,mskc-connector-worker-count:,mskc-connector-database-hostname:,mskc-connector-database-port:,\
               mskc-connector-database-user:,mskc-connector-database-password:,mskc-connector-database-server-id:,\
               mskc-connector-database-server-name:,mskc-connector-database-include-list:,mskc-connector-topic-prefix:,\
               mskc-connector-schema-registry-url:,mskc-connector-schema-registry-name:,mskc-connector-schema-history-internal-kafka-topic:,\
               mskc-connector-schema-registry-compatibility:"
    # IMPORTANT!! -o option can not be omitted, even there are no any short options!
    # otherwise, parsing will go wrong!
    OPTS=$(getopt -o "" -l "$optString" -- "$@")
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo ""
        printUsage
        exit 1
    fi
    eval set -- "$OPTS"
    while true; do
        case "$1" in
            --home-bucket)
                HOME_BUCKET=${2}
                shift 2
                ;;
            --vpc-id)
                VPC_ID=${2}
                shift 2
                ;;
            --subnet-ids)
                IFS=', ' read -r -a SUBNET_IDS <<< "${2,,}"
                shift 2
                ;;
            --security-group-ids)
                IFS=', ' read -r -a SECURITY_GROUP_IDS <<< "${2,,}"
                shift 2
                ;;
            --msk-cluster-name)
                MSK_CLUSTER_NAME=${2}
                shift 2
                ;;
            --msk-cluster-arn)
                MSK_CLUSTER_ARN=${2}
                shift 2
                ;;
            --msk-cluster-auth-type)
                MSK_CLUSTER_AUTH_TYPE=${2}
                shift 2
                ;;
            --kafka-bootstrap-servers)
                KAFKA_BOOTSTRAP_SERVERS=${2}
                shift 2
                ;;
            --topic)
                TOPIC=${2}
                shift 2
                ;;
            --mskc-plugin-name)
                MSKC_PLUGIN_NAME=${2}
                setMskcPluginNameCascadeOpts
                shift 2
                ;;
            --mskc-plugin-arn)
                MSKC_PLUGIN_ARN=${2}
                shift 2
                ;;
            --mskc-worker-config-name)
                MSKC_WORKER_CONFIG_NAME=${2}
                shift 2
                ;;
            --mskc-worker-config-arn)
                MSKC_WORKER_CONFIG_ARN=${2}
                shift 2
                ;;
            --mskc-connector-name)
                MSKC_CONNECTOR_NAME=${2}
                shift 2
                ;;
            --mskc-connector-mcu-count)
                MSKC_CONNECTOR_MCU_COUNT=${2}
                shift 2
                ;;
            --mskc-connector-worker-count)
                MSKC_CONNECTOR_WORKER_COUNT=${2}
                shift 2
                ;;
            --mskc-connector-database-hostname)
                MSKC_CONNECTOR_DATABASE_HOSTNAME=${2}
                shift 2
                ;;
            --mskc-connector-database-port)
                MSKC_CONNECTOR_DATABASE_PORT=${2}
                shift 2
                ;;
            --mskc-connector-database-user)
                MSKC_CONNECTOR_DATABASE_USER=${2}
                shift 2
                ;;
            --mskc-connector-database-password)
                MSKC_CONNECTOR_DATABASE_PASSWORD=${2}
                shift 2
                ;;
            --mskc-connector-database-server-id)
                MSKC_CONNECTOR_DATABASE_SERVER_ID=${2}
                shift 2
                ;;
            --mskc-connector-database-server-name)
                MSKC_CONNECTOR_DATABASE_SERVER_NAME=${2}
                shift 2
                ;;
            --mskc-connector-database-include-list)
                MSKC_CONNECTOR_DATABASE_INCLUDE_LIST=${2}
                shift 2
                ;;
            --mskc-connector-topic-prefix)
                MSKC_CONNECTOR_TOPIC_PREFIX=${2}
                shift 2
                ;;
            --mskc-connector-schema-registry-url)
                MSKC_CONNECTOR_SCHEMA_REGISTRY_URL=${2}
                shift 2
                ;;
            --mskc-connector-schema-registry-name)
                MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME=${2}
                shift 2
                ;;
            --mskc-connector-schema-history-internal-kafka-topic)
                MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC=${2}
                shift 2
                ;;
            --mskc-connector-schema-registry-compatibility)
                MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY=${2}
                shift 2
                ;;
            --) # No more arguments
                shift
                break
                ;;
            *)
                echo ""
                echo "Invalid option $1." >&2
                printUsage
                exit 1
                ;;
        esac
    done
    shift $((OPTIND-1))
}

printUsage() {
    echo ""
    printHeading "USAGE"
    echo ""
}

# ----------------------------------------------    Scripts Entrance    ---------------------------------------------- #

ACTION="$1"

shift

if [[ "$ACTION" == "exec" ]]; then
    eval "$@"
    exit 0
fi

# BE CAREFUL: parseArgs depends on aws cli installed by initEc2 to query emr cluster nodes
# initEc2 depends on parseArgs to parse --access-key-id and --secret-access-key, so???
parseArgs "$@"

case $ACTION in
    configure)
        configure
    ;;
    setup)
        setup
    ;;
    quickstart)
        quickstart
    ;;
    configure-s3)
        configureS3
    ;;
    configure-vpc)
        configureVpc
    ;;
    setup-msk-cluster)
        setupMskCluster
    ;;
    remove-msk-cluster)
        removeMskCluster
    ;;
    configure-msk-cluster)
        configureMskCluster
    ;;
    install-mskc-plugin)
        installMskcPlugin
    ;;
    configure-mskc-plugin)
        configureMskcPlugin
    ;;
    remove-mskc-plugin)
        removeMskcPlugin
    ;;
    setup-mskc-worker-config)
        setupMskcWorkerConfig
    ;;
    configure-mskc-worker-config)
        configureMskcWorkerConfig
    ;;
    remove-mskc-worker-config)
        removeMskcWorkerConfig
    ;;
    remove-mskc-plugin)
        removeMskcPlugin
    ;;
    setup-mskc-connector)
        setupMskcConnector
    ;;
    remove-mskc-connector)
        removeMskcConnector
    ;;
    find-mskc-connector-log-errors)
        findMskcConnectorLogErrors
    ;;
    list-topics)
        listTopics
    ;;
    consume-topic)
        consumeTopic
    ;;
    clean-topics)
        cleanTopics
    ;;
    list-configs)
        listConfigs
    ;;
    print-configs)
        printConfigs
    ;;
    help)
        printUsage
    ;;
    *)
        printUsage
    ;;
esac

