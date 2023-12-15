#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

setupMskCluster() {
    printHeading "SETUP MSK CLUSTER"
    checkMskClusterCliOpts
    loadS3Config
    loadVpcConfig
    createMskLogGroup
    # kick off creating msk cluster
    createMskCluster
    # keep monitoring cluster state until it's ready...
    monitorMskCluster "CREATING"
    # extract cluster info, i.e., KAFKA_BOOTSTRAP_SERVERS
    # these info are only available after cluster is ready.
    extractMskClusterInfo
    # immediately save cluster configs
    saveMskClusterConfig
}

removeMskCluster() {
    printHeading "REMOVE MSK CLUSTER"
    checkMskClusterCliOpts
    loadMskClusterConfig
    deleteMskCluster || true
    monitorMskCluster "DELETING" || true
    deleteMskClusterConfig || true
    deleteMskLogGroup || true
    echo -ne "[INFO]: All done!\n\n"
}

configureMskCluster() {
    printHeading "CONFIGURE MSK CLUSTER"
    checkMskClusterCliConfigureOpts
    saveMskClusterConfig
}

# ---------------------------------------------    Operation Functions    -------------------------------------------- #

createMskCluster() {
    echo -ne "[INFO]: Creating the msk cluster [ $MSK_CLUSTER_NAME ] ...\n\n"
    # write to an original file first as a debug measure in case the json is invalid.
    # then validate & format json with jq and save it to formal file.
    cat << EOF > $OSCI_TMP_DIR/create-cluster-v2.original.json
{
    "ClusterName": "$MSK_CLUSTER_NAME",
    "Provisioned": {
        "BrokerNodeGroupInfo": {
            "ClientSubnets": $(jq -c '.VPC.SubnetIds' $OSCI_CONF_FILE),
            "InstanceType": "kafka.m5.large",
            "SecurityGroups": $(jq -c '.VPC.SecurityGroupIds' $OSCI_CONF_FILE),
            "StorageInfo": {
                "EbsStorageInfo": {
                    "ProvisionedThroughput": {
                        "Enabled": false
                    },
                    "VolumeSize": 1000
                }
            },
            "ZoneIds": $(aws ec2 describe-subnets --subnet-ids "${SUBNET_IDS[@]}" --query Subnets[*].AvailabilityZoneId)
        },
        "ClientAuthentication": $(populateClientAuthentication),
        "EncryptionInfo": {
            "EncryptionInTransit": $(populateEncryptionInTransit)
        },
        "ConfigurationInfo": {
            "Arn": "arn:aws:kafka:us-east-1:366020657890:configuration/auto-create-topics/6726a1cd-608c-4a41-a508-e9e3e6fec1fc-10",
            "Revision": 1
        },
        "EnhancedMonitoring": "PER_TOPIC_PER_PARTITION",
        "KafkaVersion": "3.4.0",
        "LoggingInfo": {
            "BrokerLogs": {
                "CloudWatchLogs": {
                    "Enabled": true,
                    "LogGroup": "/msk/$MSK_CLUSTER_NAME"
                },
                "S3": {
                    "Bucket": "$HOME_BUCKET",
                    "Enabled": true,
                    "Prefix": "logs/"
                }
            }
        },
        "NumberOfBrokerNodes": 3,
        "StorageMode": "LOCAL"
    }
}
EOF
    # 1. leverage jq to validate & format original json
    # 2. print original json file as cli output
    echo -ne "[INFO]: The cli input json to create msk cluster:\n\n"
    jq . $OSCI_TMP_DIR/create-cluster-v2.original.json && echo ""

    # save valid & formatted json to formal file.
    jq . $OSCI_TMP_DIR/create-cluster-v2.original.json > $OSCI_TMP_DIR/create-cluster-v2.json

    # log cli input json
    echo -ne "\n[ $(date '+%F %T') ]\n\n" >> $OSCI_LOG_DIR/create-cluster-v2.json.log
    cat $OSCI_TMP_DIR/create-cluster-v2.json >> $OSCI_LOG_DIR/create-cluster-v2.json.log

    # start to create cluster...
    MSK_CLUSTER_ARN=$(aws kafka create-cluster-v2 \
        --no-paginate --no-cli-pager --output text \
        --cluster-name $MSK_CLUSTER_NAME \
        --cli-input-json file://$OSCI_TMP_DIR/create-cluster-v2.json \
        --query ClusterArn)
}

monitorMskCluster() {
    if [[ -n "$MSK_CLUSTER_ARN" ]]; then
        waitState="$1"
        now=$(date +%s)
        while true; do
            # tips: use list to monitor cluster status not describe,
            # because when cluster is deleted, it will fail / break
            # to query state with describe command, however, this list won't!
            clusterState=$(aws kafka describe-cluster-v2 \
                                --no-paginate --no-cli-pager --output text \
                                --cluster-arn $MSK_CLUSTER_ARN \
                                --query ClusterInfo.State)

            if [[ -z "$clusterState" ]]; then
                echo -ne "[INFO]: The msk cluster does not exist or has been deleted.                    \n\n"
                break
            elif [[ "$clusterState" == "$waitState" ]]; then
                for i in {0..5}; do
                    echo -ne "\E[33;5m>>> [INFO]: The msk cluster state is [ $clusterState ], duration [ $(date -u --date now-${now}sec '+%H:%M:%S') ] ....\r\E[0m"
                    sleep 1
                done
            else
                echo -ne "\e[0A\e[K[INFO]: The msk cluster state is [ $clusterState ] now!\n\n"
                break
            fi
        done
    else
        echo -ne "[INFO]: The msk cluster does not exist or has been deleted.                    \n\n"
    fi
}

extractMskClusterInfo() {
    # get kafka broker
    KAFKA_BOOTSTRAP_SERVERS=$(aws kafka get-bootstrap-brokers \
        --no-paginate --no-cli-pager --output text \
        --cluster-arn $MSK_CLUSTER_ARN)
}

describeMskCluster() {
    aws kafka describe-cluster-v2 --no-paginate --no-cli-pager --cluster-arn $MSK_CLUSTER_ARN
}

deleteMskCluster() {
    echo -ne "[INFO]: Deleting the msk cluster [ $MSK_CLUSTER_NAME ] ...\n\n"
    aws kafka delete-cluster --no-paginate --no-cli-pager --cluster-arn $MSK_CLUSTER_ARN
}

populateClientAuthentication() {
    case $MSK_CLUSTER_AUTH_TYPE in
        NONE)
            populateUnauthenticatedClientAuthentication
        ;;
        IAM)
            createIamClientAuthentication
        ;;
    esac
}

populateUnauthenticatedClientAuthentication() {
    cat << EOF
{
    "Unauthenticated": {
        "Enabled": true
    }
}
EOF
}

createIamClientAuthentication() {
    cat << EOF
{
    "Sasl": {
        "Iam": {
            "Enabled": true
        }
    }
}
EOF
}

populateEncryptionInTransit() {
    case $MSK_CLUSTER_AUTH_TYPE in
        # Note: for unauthenticated client authentication,
        # The EncryptionInTransit could be PLAINTEXT or TLS,
        # If we do NOT set EncryptionInTransit explicitly,
        # The TLS will be enabled by default.
        # Here, we don't want to add an extra param like `--encryption PLAINTEXT|TLS`,
        # To be simple, we let unauthenticated client authentication always use PLAINTEXT,
        # If you need a cluster with unauthenticated client authentication & TLS encryption,
        # you can replace following `populatePlaintextEncryptionInTransit` with `populateTlsEncryptionInTransit`
        NONE)
            populatePlaintextEncryptionInTransit
        ;;
        # Note: for IAM, SASL/SCRAM, TLS authentication, TLS encryption is REQUIRED!
        # Actually, we don't need configure TLS for IAM explicitly, because TLS encryption is always
        # enabled by default, here, we set it explicitly just for human readable.
        IAM)
            populateTlsEncryptionInTransit
        ;;
    esac
}

populatePlaintextEncryptionInTransit() {
    cat <<EOF
{
    "ClientBroker": "PLAINTEXT",
    "InCluster": false
}
EOF
}

populateTlsEncryptionInTransit() {
    cat <<EOF
{
    "ClientBroker": "TLS",
    "InCluster": true
}
EOF
}

createMskLogGroup() {
    echo -ne "[INFO]: Creating the msk cluster log group...\n\n"
    if [[ "$(isMskLogGroupExisting)" == "false" ]]; then
        aws logs create-log-group --log-group-name /msk/$MSK_CLUSTER_NAME
    else
        echo -ne "[INFO]: The msk log group [ /msk/$MSK_CLUSTER_NAME ] already exists.\n\n"
    fi
}

deleteMskLogGroup() {
    echo -ne "[INFO]: Deleting the msk cluster log group...\n\n"
    if [[ "$(isMskLogGroupExisting)" == "true" ]]; then
        aws logs delete-log-group --log-group-name /msk/$MSK_CLUSTER_NAME
    fi
}

isMskLogGroupExisting() {
    lookupResult=$(aws logs describe-log-groups \
        --no-paginate --no-cli-pager --output text \
        --log-group-name-prefix "/msk/$MSK_CLUSTER_NAME" \
        --query 'logGroups[?logGroupName==`'"/msk/$MSK_CLUSTER_NAME"'`].logGroupName')
    if [[ -n $lookupResult ]]; then
        echo "true"
    else
        echo "false"
    fi
}

deleteMskClusterConfig() {
    echo -ne "[INFO]: Deleting the msk cluster configuration...\n\n"
    (IFS=;cat <<< $(jq 'del(.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'"))' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
}

# ---------------------------------------------    Config Functions    ----------------------------------------------- #

# This toolkit can manage multiple msk clusters, so clusters configs are stored as an array in json file,
# any clusters related operations always need indicate cluster name, then the toolkit load its config by name.
loadMskClusterConfig() {
    if [[ "$(hasMskClusterConfigs)" == "true" ]]; then
        MSK_CLUSTER_NAME=$(jq -r '.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'") | .MskClusterName' $OSCI_CONF_FILE)
        MSK_CLUSTER_ARN=$(jq -r '.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'") | .MskClusterArn' $OSCI_CONF_FILE)
        KAFKA_BOOTSTRAP_SERVERS=$(jq -r '.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'") | .KafkaBootstrapServers' $OSCI_CONF_FILE)
        MSK_CLUSTER_AUTH_TYPE=$(jq -r '.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'") | .MskClusterAuthType' $OSCI_CONF_FILE)
        checkMskClusterCfgOpts
    else
        echo -ne "[ERROR]: The msk cluster: [ $MSK_CLUSTER_NAME ] does not exist!\n\n"
        exit 1
    fi
}

saveMskClusterConfig() {
    echo -ne "[INFO]: Saving the msk cluster [ $MSK_CLUSTER_NAME ] configuration ...\n\n"
    mskClusterConfig=$(jo -p MskClusterName=$MSK_CLUSTER_NAME \
        MskClusterArn=$MSK_CLUSTER_ARN \
        KafkaBootstrapServers=$KAFKA_BOOTSTRAP_SERVERS \
        MskClusterAuthType=$MSK_CLUSTER_AUTH_TYPE)
    # NOTE: jq can NOT modify json file directly, we need manually write back file with cat <<< ... > xxx.json, however, in this way,
    # we will lose json format, we have to remove default IFS, but this will impact on other scripts, so we encapsulate all in a subshell!
    (IFS=;cat <<< $(jq --argjson mskClusterConfig "$mskClusterConfig" '.MskClusters += [$mskClusterConfig]' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved!!
    # every config items must keep consistent with config file
    # and only load action can set: MSK_CLUSTER_CONFIGURED=true
    loadMskClusterConfig
    printMskClusterConfig
}

hasMskClusterConfigs() {
    mskClusterConfig=$(jq '.MskClusters[] | select (.MskClusterName == "'"$MSK_CLUSTER_NAME"'")' $OSCI_CONF_FILE)
    if [[ -n $mskClusterConfig ]]; then
        echo "true"
    else
        echo "false"
    fi
}

printMskClusterConfig() {
    printHeading "MSK CLUSTER CONFIGURATION"
    jq '.MskClusters' $OSCI_CONF_FILE && echo ""
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkMskClusterCliConfigureOpts() {
    echo -ne "[INFO]: Checking command line options...\n\n"
    if [[ -z $MSK_CLUSTER_NAME ||
          -z $MSK_CLUSTER_ARN ||
          -z $KAFKA_BOOTSTRAP_SERVERS ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --msk-cluster-name ]
            [ --msk-cluster-arn ]
            [ --kafka-bootstrap-servers ]

EOF
        exit 1
    fi
    checkMskClusterAuthType
}

checkMskClusterCliOpts() {
    echo -ne "[INFO]: Checking command line options...\n\n"
    if [[ -z $MSK_CLUSTER_NAME ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --msk-cluster-name ]

EOF
        exit 1
    fi
    checkMskClusterAuthType
}

checkMskClusterCfgOpts() {
    echo -ne "[INFO]: Checking the msk cluster configuration options...\n\n"
    if [[ -z $MSK_CLUSTER_NAME ||
          -z $MSK_CLUSTER_ARN ||
          -z $KAFKA_BOOTSTRAP_SERVERS ||
          -z $MSK_CLUSTER_AUTH_TYPE ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ MskClusterName ]
            [ MskClusterArn ]
            [ KafkaBootstrapServers ]
            [ MskClusterAuthType ]

EOF
        exit 1
    fi
}
