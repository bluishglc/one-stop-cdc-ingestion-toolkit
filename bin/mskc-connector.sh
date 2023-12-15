#!/usr/bin/env bash

# Notes:
#
# There is a different naming & conception between opensource kafka connect and aws msk connect:
# For oss kafka connect, it has a kafka connect cluster first, then install connectors on the connect cluster;
# However, for aws msk connect, there is no way to create a plain kafka connect cluster, a kafka connect cluster
# is always created with a connector, so, in aws api/cli, there is only "aws kafkaconnect create-connector" operation,
# no "aws kafkaconnect create-cluster" operation. This is a conception mismatch between oss kafka connect & aws msk connect
#
# The one-to-one relation between msk connect cluster and msk connector is NOT a good design!!
# This means you always create a new cluster for a new connector, different connectors can NOT share a cluster!!
# The same issue also exists on plugin and connector, a connector and only select one plugin!!

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

setupMskcConnector() {
    printHeading "SETUP MSK CONNECT CONNECTOR"
    checkMskcConnectorCliSetupOpts
    # load all dependencies configs
    loadS3Config
    loadVpcConfig
    loadMskClusterConfig
    loadMskcPluginConfig
    loadMskcWorkerConfigConfig
    # create database username & password secret
    # this action should happen before create execution role
    # because the execution role need grant read permission against secret arn.
    createMskcConnectorSecret
    # create execution role first
    createMskcConnectorExecutionRole
    # create log group
    createMskcConnectorLogGroup
    case $MSKC_PLUGIN_NAME in
        osci-plugin-mysql-gsr-avro)
            # create glue schema registry
            createMskcConnectorRegistry
        ;;
    esac
    # kick off creating msk connect cluster
    createMskcConnector
    # keep monitoring cluster state until it's ready...
    monitorMskcConnector "CREATING"
    # immediately save cluster configs
    saveMskcConnectorConfig
}

removeMskcConnector() {
    printHeading "REMOVE MSK CONNECT CONNECTOR"
    checkMskcConnectorCliRemoveOpts
    loadVpcConfig
    loadMskClusterConfig
    loadMskcConnectorConfig
    echo -ne "[INFO]: Deleting the msk connect connector [ $MSKC_CONNECTOR_NAME ] ...\n\n"
    aws kafkaconnect delete-connector --no-paginate --no-cli-pager --connector-arn "$MSKC_CONNECTOR_ARN" &> /dev/null || true
    monitorMskcConnector "DELETING" || true
    deleteMskcConnectorKafkaTopics  || true
    deleteMskcConnectorLogGroup || true
    deleteMskcConnectorExecutionRole || true
    deleteMskcConnectorSecret || true
    deleteMskcConnectorConfig || true
    echo -ne "[INFO]: All done!\n\n"
}

# ---------------------------------------------    Operation Functions    -------------------------------------------- #

createMskcConnectorSecret() {
    echo -ne "[INFO]: Creating the secret with given database username and password...\n\n"
    cat << EOF > $OSCI_TMP_DIR/secret.json
{
    "username": "$MSKC_CONNECTOR_DATABASE_USER",
    "password": "$MSKC_CONNECTOR_DATABASE_PASSWORD"
}
EOF
    # need store ARN to config file!!!
    MSKC_CONNECTOR_DATABASE_SECRET_ARN=$(aws secretsmanager create-secret \
        --no-paginate --no-cli-pager --output text \
        --name $MSKC_CONNECTOR_DATABASE_SERVER_NAME \
        --secret-string file://$OSCI_TMP_DIR/secret.json \
        --query ARN)
    # remove for sake of security
    rm -f $OSCI_TMP_DIR/secret.json
}

deleteMskcConnectorSecret() {
    echo -ne "[INFO]: Deleting the secret of database username and password...\n\n"
    aws secretsmanager delete-secret \
        --force-delete-without-recovery --cli-read-timeout 10 --cli-connect-timeout 10 \
        --secret-id $MSKC_CONNECTOR_DATABASE_SERVER_NAME &> /dev/null
}

deleteMskcConnectorConfig() {
    echo -ne "[INFO]: Deleting the msk connect connector configuration...\n\n"
    (IFS=;cat <<< $(jq 'del(.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'"))' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
}

deleteMskcConnectorKafkaTopics() {
    echo -ne "[INFO]: Deleting the msk connect connector kafka topics...\n\n"
    case $MSK_CLUSTER_AUTH_TYPE in
        NONE)
            kafka-topics.sh \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --delete \
                --topic "__amazon_msk_connect.*${MSKC_CONNECTOR_NAME}.*|osci.${MSKC_CONNECTOR_DATABASE_SERVER_NAME}.*"
        ;;
        IAM)
            kafka-topics.sh \
                --command-config $OSCI_CNF_DIR/kafka-client.properties \
                --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS \
                --delete \
                --topic "__amazon_msk_connect.*${MSKC_CONNECTOR_NAME}.*|osci.${MSKC_CONNECTOR_DATABASE_SERVER_NAME}.*"
        ;;
    esac
}

createMskcConnectorLogGroup() {
    echo -ne "[INFO]: Creating the msk connect connector log group...\n\n"
    aws logs create-log-group --log-group-name /mskc-connector/$MSKC_CONNECTOR_NAME
}

deleteMskcConnectorLogGroup() {
    echo -ne "[INFO]: Deleting the msk connect connector log group...\n\n"
    aws logs delete-log-group --log-group-name /mskc-connector/$MSKC_CONNECTOR_NAME
}

createMskcConnectorExecutionRole() {
    # Tip: AWS managed role name usually follow 'AbcDef' pattern, In order to distinguish managed roles and
    # user-defined roles, A suggestion is: naming user defined role with other patterns, like 'abc-def' here
    MSKC_CONNECTOR_EXECUTION_ROLE_NAME="osci-connector-execution-role-$MSKC_CONNECTOR_NAME"

    echo -ne "[INFO]: Creating the msk connect connector execution role [ $MSKC_CONNECTOR_EXECUTION_ROLE_NAME ] ...\n\n"

    # output to jq for validating & formatting, then write to file.
    cat << EOF > $OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.original.json
{
    "Version":"2012-10-17",
    "Statement":[
        {
            "Effect":"Allow",
            "Principal":{
                "Service":"kafkaconnect.amazonaws.com"
            },
            "Action":"sts:AssumeRole",
            "Condition":{
                "StringEquals":{
                    "aws:SourceAccount":"$AWS_ACCOUNT_ID"
                },
                "ArnLike":{
                    "aws:SourceArn":"arn:aws:kafkaconnect:$REGION:$AWS_ACCOUNT_ID:connector/$MSKC_CONNECTOR_NAME/*"
                }
            }
        }
    ]
}
EOF
    # 1. leverage jq to validate & format original json
    # 2. print original json file as cli output
    echo -ne "[INFO]: The cli input json to create msk connector execution role assume policy:\n\n"
    jq . $OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.original.json && echo ""

    # save valid & formatted json to formal file.
    jq . $OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.original.json > $OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.json

    # log cli input json
    echo -ne "\n[ $(date '+%F %T') ]\n\n" >> $OSCI_LOG_DIR/mskc-connector-execution-role-assume-policy.json.log
    cat $OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.json >> $OSCI_LOG_DIR/mskc-connector-execution-role-assume-policy.json.log

    # start to create execution role...
    MSKC_CONNECTOR_EXECUTION_ROLE_ARN=$(aws iam create-role \
        --no-paginate --no-cli-pager --output text \
        --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME" \
        --assume-role-policy-document file://$OSCI_TMP_DIR/mskc-connector-execution-role-assume-policy.json \
        --query Role.Arn)

    # output to jq for validating & formatting, then write to file.
    cat << EOF > $OSCI_TMP_DIR/mskc-connector-execution-role-policy.original.json
{
    "Version":"2012-10-17",
    "Statement":[
        $(
            case $MSK_CLUSTER_AUTH_TYPE in
                IAM)
                    populateMskClusterOperationPermissions
                ;;
            esac
            printSecretsManagerOperationPermissions
        )
    ]
}
EOF
    # 1. leverage jq to validate & format original json
    # 2. print original json file as cli output
    echo -ne "[INFO]: The cli input json to create msk connector execution role policy:\n\n"
    jq . $OSCI_TMP_DIR/mskc-connector-execution-role-policy.original.json && echo ""

    # save valid & formatted json to formal file.
    jq . $OSCI_TMP_DIR/mskc-connector-execution-role-policy.original.json > $OSCI_TMP_DIR/mskc-connector-execution-role-policy.json

    # log cli input json
    echo -ne "\n[ $(date '+%F %T') ]\n\n" >> $OSCI_LOG_DIR/mskc-connector-execution-role-policy.json.log
    cat $OSCI_TMP_DIR/mskc-connector-execution-role-policy.json >> $OSCI_LOG_DIR/mskc-connector-execution-role-policy.json.log


    # add inline policy
    aws iam put-role-policy \
        --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME" \
        --policy-name "default" \
        --policy-document file://$OSCI_TMP_DIR/mskc-connector-execution-role-policy.json

    # attach managed policy
    # the msk connect connector need r/w permission to operate glue schema registry
    aws iam attach-role-policy \
        --policy-arn "arn:aws:iam::aws:policy/AWSGlueSchemaRegistryFullAccess" \
        --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME"
}

populateMskClusterOperationPermissions() {
    cat << EOF
{
    "Effect":"Allow",
    "Action":[
        "kafka-cluster:Connect",
        "kafka-cluster:AlterCluster",
        "kafka-cluster:DescribeCluster"
    ],
    "Resource":"arn:aws:kafka:$REGION:$AWS_ACCOUNT_ID:cluster/$MSK_CLUSTER_NAME/*"
},
{
    "Effect":"Allow",
    "Action":[
        "kafka-cluster:DescribeTopic",
        "kafka-cluster:CreateTopic",
        "kafka-cluster:WriteData",
        "kafka-cluster:ReadData"
    ],
    "Resource":"arn:aws:kafka:$REGION:$AWS_ACCOUNT_ID:topic/$MSK_CLUSTER_NAME/*"
},
{
    "Effect":"Allow",
    "Action":[
        "kafka-cluster:AlterGroup",
        "kafka-cluster:DescribeGroup"
    ],
    "Resource":"arn:aws:kafka:$REGION:$AWS_ACCOUNT_ID:group/$MSK_CLUSTER_NAME/*"
},
EOF
}

printSecretsManagerOperationPermissions() {
    cat << EOF
{
    "Effect":"Allow",
    "Action":[
        "secretsmanager:GetResourcePolicy",
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecretVersionIds"
    ],
    "Resource":[
        "$MSKC_CONNECTOR_DATABASE_SECRET_ARN"
    ]
}
EOF
}

deleteMskcConnectorExecutionRole() {
    echo -ne "[INFO]: Deleting the msk connect connector execution role...\n\n"
    aws iam delete-role-policy --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME" --policy-name "default" || true  # go on even failed
    aws iam detach-role-policy --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/AWSGlueSchemaRegistryFullAccess" || true  # go on even failed
    aws iam delete-role --role-name "$MSKC_CONNECTOR_EXECUTION_ROLE_NAME" || true # go on even failed
}

createMskcConnectorRegistry() {
    echo -ne "[INFO]: Creating the glue schema registry [ $MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME ] ...\n\n"
    # if find registry...
    if aws glue get-registry --registry-id "RegistryName=$MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME" &> /dev/null; then
        echo -ne "[INFO]: The glue schema registry [ $MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME ] already exists.\n\n"
    else
        aws glue create-registry --registry-name "$MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME" &> /dev/null
    fi
}

# NOTE: The debezium-mysql-connector only uses a single task, see:
# https://debezium.io/documentation/reference/1.8/connectors/mysql.html#mysql-property-tasks-max
# So, it does not work with autoscaled capacity mode for Amazon MSK Connect. We should instead
# use provisioned capacity mode and set workerCount equal to '1' in our connector configuration.
createMskcConnector() {
    echo -ne "[INFO]: Creating the msk connect connector [ $MSKC_CONNECTOR_NAME ] ...\n\n"
    # output to jq for validating & formatting, then write to file.
    cat << EOF > $OSCI_TMP_DIR/create-connector.original.json
{
    "capacity": {
        "provisionedCapacity": {
            "mcuCount": $MSKC_CONNECTOR_MCU_COUNT,
            "workerCount": $MSKC_CONNECTOR_WORKER_COUNT
        }
    },
    "connectorName": "$MSKC_CONNECTOR_NAME",
    "connectorConfiguration": $(createConnectorConfiguration),
    "kafkaCluster": {
        "apacheKafkaCluster": {
            "bootstrapServers": "$KAFKA_BOOTSTRAP_SERVERS",
            "vpc": {
                "securityGroups": $(jq -c '.VPC.SecurityGroupIds' $OSCI_CONF_FILE),
                "subnets": $(jq -c '.VPC.SubnetIds' $OSCI_CONF_FILE)
            }
        }
    },
    "kafkaClusterClientAuthentication": {
        "authenticationType": "$MSK_CLUSTER_AUTH_TYPE"
    },
    "kafkaClusterEncryptionInTransit": {
        "encryptionType": "$([[ "$MSK_CLUSTER_AUTH_TYPE" == "NONE" ]] && echo "PLAINTEXT" || echo "TLS")"
    },
    "kafkaConnectVersion": "2.7.1",
    "logDelivery": {
        "workerLogDelivery": {
            "cloudWatchLogs": {
                "enabled": true,
                "logGroup": "/mskc-connector/$MSKC_CONNECTOR_NAME"
            },
            "s3": {
                "bucket": "$HOME_BUCKET",
                "enabled": true,
                "prefix": "logs/"
            }
        }
    },
    "plugins": [
        {
            "customPlugin": {
                "customPluginArn": "$MSKC_PLUGIN_ARN",
                "revision": 1
            }
        }
    ],
    "serviceExecutionRoleArn": "$MSKC_CONNECTOR_EXECUTION_ROLE_ARN",
    "workerConfiguration": {
        "revision": 1,
        "workerConfigurationArn": "$MSKC_WORKER_CONFIG_ARN"
    }
}
EOF
    # 1. leverage jq to validate & format original json
    # 2. print original json file as cli output
    echo -ne "[INFO]: The cli input json to create msk connector:\n\n"
    jq . $OSCI_TMP_DIR/create-connector.original.json && echo ""

    # save valid & formatted json to formal file.
    jq . $OSCI_TMP_DIR/create-connector.original.json > $OSCI_TMP_DIR/create-connector.json

    # log cli input json
    echo -ne "\n[ $(date '+%F %T') ]\n\n" >> $OSCI_LOG_DIR/create-connector.json.log
    cat $OSCI_TMP_DIR/create-connector.json >> $OSCI_LOG_DIR/create-connector.json.log

    # start to create connector...
    MSKC_CONNECTOR_ARN=$(aws kafkaconnect create-connector \
        --no-paginate --no-cli-pager --output text \
        --connector-name $MSKC_CONNECTOR_NAME \
        --cli-input-json file://$OSCI_TMP_DIR/create-connector.json \
        --query connectorArn)
}

createConnectorConfiguration() {
    case $MSKC_PLUGIN_NAME in
        osci-plugin-mysql-gsr-avro)
            createMysqlGsrAvroConnectorConfig
        ;;
        osci-plugin-mysql-confluent-avro)
            createMysqlConfluentAvroConnectorConfig
        ;;
    esac
}

createMysqlGsrAvroConnectorConfig() {
    cat << EOF
{
        "tasks.max": "1",
        $(createDebeziumMysqlConnectorConfig)
        $(createGsrAvroConverterConfig)
    }
EOF
}

createMysqlConfluentAvroConnectorConfig() {
    cat << EOF
{
        "tasks.max": "1",
        $(createDebeziumMysqlConnectorConfig)
        $(createConfluentAvroConverterConfig)
    }
EOF
}

createDebeziumMysqlConnectorConfig() {
    cat << EOF
"connector.class": "io.debezium.connector.mysql.MySqlConnector",
"topic.prefix": "$MSKC_CONNECTOR_TOPIC_PREFIX",
"include.schema.changes": "true",
"database.hostname": "$MSKC_CONNECTOR_DATABASE_HOSTNAME",
"database.password": "\${secretsmanager:$MSKC_CONNECTOR_DATABASE_SERVER_NAME:password}",
"database.port": "$MSKC_CONNECTOR_DATABASE_PORT",
"database.server.id": "$MSKC_CONNECTOR_DATABASE_SERVER_ID",
"database.server.name": "$MSKC_CONNECTOR_DATABASE_SERVER_NAME",
"database.user": "\${secretsmanager:$MSKC_CONNECTOR_DATABASE_SERVER_NAME:username}",
"database.include.list": "$MSKC_CONNECTOR_DATABASE_INCLUDE_LIST",
"schema.history.internal.kafka.bootstrap.servers": "$KAFKA_BOOTSTRAP_SERVERS",
"schema.history.internal.kafka.topic": "$MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC",
EOF
    case $MSK_CLUSTER_AUTH_TYPE in
        IAM)
            cat << EOF
"database.history.consumer.sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
"database.history.consumer.sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
"database.history.consumer.sasl.mechanism": "AWS_MSK_IAM",
"database.history.consumer.security.protocol": "SASL_SSL",
"database.history.producer.sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
"database.history.producer.sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
"database.history.producer.sasl.mechanism": "AWS_MSK_IAM",
"database.history.producer.security.protocol": "SASL_SSL",
"schema.history.internal.consumer.sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
"schema.history.internal.consumer.sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
"schema.history.internal.consumer.sasl.mechanism": "AWS_MSK_IAM",
"schema.history.internal.consumer.security.protocol": "SASL_SSL",
"schema.history.internal.producer.sasl.client.callback.handler.class": "software.amazon.msk.auth.iam.IAMClientCallbackHandler",
"schema.history.internal.producer.sasl.jaas.config": "software.amazon.msk.auth.iam.IAMLoginModule required;",
"schema.history.internal.producer.sasl.mechanism": "AWS_MSK_IAM",
"schema.history.internal.producer.security.protocol": "SASL_SSL",
EOF
        ;;
    esac
}

createGsrAvroConverterConfig() {
    cat << EOF
"internal.key.converter.schemas.enable": "false",
"internal.value.converter.schemas.enable": "false",
"key.converter": "org.apache.kafka.connect.storage.StringConverter",
"key.converter.schemas.enable": "false",
"value.converter": "com.amazonaws.services.schemaregistry.kafkaconnect.AWSKafkaAvroConverter",
"value.converter.avroRecordType": "GENERIC_RECORD",
"value.converter.region": "$REGION",
"value.converter.registry.name": "$MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME",
"value.converter.schemaAutoRegistrationEnabled": "true",
"value.converter.compatibilitySetting": "$MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY"
EOF
}

createConfluentAvroConverterConfig() {
    cat << EOF
"internal.key.converter.schemas.enable": "false",
"internal.value.converter.schemas.enable": "false",
"key.converter": "org.apache.kafka.connect.storage.StringConverter",
"key.converter.schemas.enable": "false",
"value.converter": "io.confluent.connect.avro.AvroConverter",
"value.converter.schema.registry.url": "$MSKC_CONNECTOR_SCHEMA_REGISTRY_URL",
"value.converter.registry.name": "$MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME"
EOF
}

monitorMskcConnector() {
    if [[ -n "$MSKC_CONNECTOR_ARN" ]]; then
        waitState="$1"
        now=$(date +%s)
        while true; do
            # tips: use list to monitor connector status not describe,
            # because when connector is deleted, it will fail / break
            # to query state with describe command, however, this list won't!
            connectorState=$(aws kafkaconnect list-connectors \
	                            --no-paginate --no-cli-pager --output text \
                                --query 'connectors[?connectorArn==`'"${MSKC_CONNECTOR_ARN}"'`].connectorState')

            if [[ -z "$connectorState" ]]; then
                echo -ne "[INFO]: The msk connect connector does not exist or has been deleted.                    \n\n"
                break
            elif [[ "$connectorState" == "$waitState" ]]; then
                for i in {0..5}; do
                    echo -ne "\E[33;5m>>> [INFO]: The msk connect connector state is [ $connectorState ], duration [ $(date -u --date now-${now}sec '+%H:%M:%S') ] ....\r\E[0m"
                    sleep 1
                done
            else
                echo -ne "\e[0A\e[K[INFO]: The msk connect connector state is [ $connectorState ] now!\n\n"
                break
            fi
        done
    else
        echo -ne "[INFO]: The msk connect connector does not exist or has been deleted.                    \n\n"
    fi
}

findMskcConnectorLogErrors() {
    loadMskcConnectorConfig
    s3LogHome=s3://$HOME_BUCKET/logs/AWSLogs/$AWS_ACCOUNT_ID/KafkaConnectLogs/$REGION/$(basename $MSKC_CONNECTOR_ARN)
    localLogHome=$OSCI_TMP_DIR/$(basename $MSKC_CONNECTOR_ARN)
    rm -rf $localLogHome && mkdir -p $localLogHome
    aws s3 cp --recursive $s3LogHome $localLogHome >& /dev/null
    gzip -d -r -f $localLogHome >& /dev/null
    grep --color=always -r -i -E 'error|failed|exception' $localLogHome
}

describeMskcConnector() {
    aws kafka describe-cluster-v2 --no-paginate --no-cli-pager --cluster-arn $MSKC_CONNECTOR_ARN
}

# ---------------------------------------------    Config Functions    ----------------------------------------------- #

# This toolkit can manage multiple connectors, so connectors configs are stored as an array in json file,
# any connector related operations always need indicate connector name, then the toolkit load its config by name.
loadMskcConnectorConfig() {
    if [[ "$(hasMskcConnectorConfig)" == "true" ]]; then
        # plugin common config items
        MSKC_CONNECTOR_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorName' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_ARN=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorArn' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_EXECUTION_ROLE_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorExecutionRoleName' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_EXECUTION_ROLE_ARN=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorExecutionRoleArn' $OSCI_CONF_FILE)
        MSKC_WORKER_CONFIG_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcWorkerConfigName' $OSCI_CONF_FILE)
        MSKC_PLUGIN_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcPluginName' $OSCI_CONF_FILE)
        MSK_CLUSTER_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskClusterName' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_MCU_COUNT=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorMcuCount' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_WORKER_COUNT=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorWorkerCount' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_HOSTNAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabaseHostname' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_PORT=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabasePort' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_SECRET_ARN=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabaseSecretArn' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_SERVER_ID=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabaseServerId' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_SERVER_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabaseServerName' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_DATABASE_INCLUDE_LIST=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorDatabaseIncludeList' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_TOPIC_PREFIX=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorTopicPrefix' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorSchemaRegistryName' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorSchemaHistoryInternalKafkaTopic' $OSCI_CONF_FILE)
        MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorSchemaRegistryCompatibility' $OSCI_CONF_FILE)
        # plugin-specific configs
        case $MSKC_PLUGIN_NAME in
            osci-plugin-mysql-confluent-avro)
                MSKC_CONNECTOR_SCHEMA_REGISTRY_URL=$(jq -r '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'") | .MskcConnectorSchemaRegistryUrl' $OSCI_CONF_FILE)
            ;;
        esac

        checkMskcConnectorCfgOpts
    else
        echo -ne "[ERROR]: The msk connect connector: [ $MSKC_CONNECTOR_NAME ] does not exist!\n\n"
        exit 1
    fi
}

saveMskcConnectorConfig() {
    echo -ne "[INFO]: Saving the msk connect connector [ $MSKC_CONNECTOR_NAME ] configuration ...\n\n"
    mskcConnectorConfig=$(jo -p \
        MskcConnectorName=$MSKC_CONNECTOR_NAME \
        MskcConnectorArn=$MSKC_CONNECTOR_ARN \
        MskcConnectorExecutionRoleName=$MSKC_CONNECTOR_EXECUTION_ROLE_NAME \
        MskcConnectorExecutionRoleArn=$MSKC_CONNECTOR_EXECUTION_ROLE_ARN \
        MskcWorkerConfigName=$MSKC_WORKER_CONFIG_NAME \
        MskcPluginName=$MSKC_PLUGIN_NAME \
        MskClusterName=$MSK_CLUSTER_NAME \
        MskcConnectorMcuCount=$MSKC_CONNECTOR_MCU_COUNT \
        MskcConnectorWorkerCount=$MSKC_CONNECTOR_WORKER_COUNT \
        MskcConnectorDatabaseHostname=$MSKC_CONNECTOR_DATABASE_HOSTNAME \
        MskcConnectorDatabasePort=$MSKC_CONNECTOR_DATABASE_PORT \
        MskcConnectorDatabaseSecretArn=$MSKC_CONNECTOR_DATABASE_SECRET_ARN \
        MskcConnectorDatabaseServerId=$MSKC_CONNECTOR_DATABASE_SERVER_ID \
        MskcConnectorDatabaseServerName=$MSKC_CONNECTOR_DATABASE_SERVER_NAME \
        MskcConnectorDatabaseIncludeList=$MSKC_CONNECTOR_DATABASE_INCLUDE_LIST \
        MskcConnectorTopicPrefix=$MSKC_CONNECTOR_TOPIC_PREFIX \
        MskcConnectorSchemaRegistryUrl=$MSKC_CONNECTOR_SCHEMA_REGISTRY_URL \
        MskcConnectorSchemaRegistryName=$MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME \
        MskcConnectorSchemaHistoryInternalKafkaTopic=$MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC \
        MskcConnectorSchemaRegistryCompatibility=$MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY)
    # NOTE: jq can NOT modify json file directly, we need manually write back file with cat <<< ... > xxx.json, however, in this way,
    # we will lose json format, we have to remove default IFS, but this will impact on other scripts, so we encapsulate all in a subshell!
    (IFS=;cat <<< $(jq --argjson mskcConnectorConfig "$mskcConnectorConfig" '.MskcConnectors += [$mskcConnectorConfig]' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved!!
    # every config items must keep consistent with config file
    # and only load action can set: MSKC_CONNECTOR_CONFIGURED=true
    loadMskcConnectorConfig
    printMskcConnectorConfig
}

hasMskcConnectorConfig() {
    mskcConnectorConfig=$(jq '.MskcConnectors[] | select (.MskcConnectorName == "'"$MSKC_CONNECTOR_NAME"'")' $OSCI_CONF_FILE)
    if [[ -n $mskcConnectorConfig ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkMskcConnectorCliSetupOpts() {
    echo -ne "[INFO]: Checking the msk connect connector 'setup' command options...\n\n"
    if [[ -z $MSKC_CONNECTOR_NAME ||
        -z $MSKC_WORKER_CONFIG_NAME ||
        -z $MSKC_PLUGIN_NAME ||
        -z $MSK_CLUSTER_NAME ||
        -z $MSKC_CONNECTOR_MCU_COUNT ||
        -z $MSKC_CONNECTOR_WORKER_COUNT ||
        -z $MSKC_CONNECTOR_DATABASE_HOSTNAME ||
        -z $MSKC_CONNECTOR_DATABASE_PORT ||
        -z $MSKC_CONNECTOR_DATABASE_USER ||
        -z $MSKC_CONNECTOR_DATABASE_PASSWORD ||
        -z $MSKC_CONNECTOR_DATABASE_SERVER_ID ||
        -z $MSKC_CONNECTOR_DATABASE_SERVER_NAME ||
        -z $MSKC_CONNECTOR_DATABASE_INCLUDE_LIST ||
        -z $MSKC_CONNECTOR_TOPIC_PREFIX ||
        -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME ||
        -z $MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC ||
        -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY ]]; then

        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-connector-name ]
            [ --mskc-worker-config-name ]
            [ --mskc-plugin-name ]
            [ --msk-cluster-name ]
            [ --mskc-connector-mcu-count ]
            [ --mskc-connector-worker-count ]
            [ --mskc-connector-database-hostname ]
            [ --mskc-connector-database-port ]
            [ --mskc-connector-database-user ]
            [ --mskc-connector-database-password ]
            [ --mskc-connector-database-server-id ]
            [ --mskc-connector-database-server-name ]
            [ --mskc-connector-database-include-list ]
            [ --mskc-connector-topic-prefix ]
            [ --mskc-connector-schema-registry-name ]
            [ --mskc-connector-schema-history-internal-kafka-topic ]
            [ --mskc-connector-schema-registry-compatibility ]

EOF
        exit 1
    fi
    # plugin "osci-plugin-mysql-confluent-avro" required opts,
    # use case not if, in order to extend to multiple plugins in the future.
    case $MSKC_PLUGIN_NAME in
        osci-plugin-mysql-confluent-avro)
            if [[ -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_URL ]]; then
                cat << EOF | sed 's/^ *//'
                    [ERROR]: One or multiple following options are missing in command line:

                    [ --mskc-connector-schema-registry-url ]

EOF
                exit 1
            fi
        ;;
    esac
    checkMskClusterAuthType
}

checkMskcConnectorCliRemoveOpts() {
    echo -ne "[INFO]: Checking the msk connect connector 'remove' command options...\n\n"
    if [[ -z $MSKC_CONNECTOR_NAME ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-connector-name ]

EOF
        exit 1
    fi
}

checkMskcConnectorCfgOpts() {
    echo -ne "[INFO]: Checking the msk connect connector configuration options...\n\n"
    if [[ -z $MSKC_CONNECTOR_NAME ||
          -z $MSKC_CONNECTOR_ARN ||
          -z $MSKC_CONNECTOR_EXECUTION_ROLE_NAME ||
          -z $MSKC_CONNECTOR_EXECUTION_ROLE_ARN ||
          -z $MSKC_PLUGIN_NAME ||
          -z $MSK_CLUSTER_NAME ||
          -z $MSKC_WORKER_CONFIG_NAME ||
          -z $MSKC_CONNECTOR_MCU_COUNT ||
          -z $MSKC_CONNECTOR_WORKER_COUNT ||
          -z $MSKC_CONNECTOR_DATABASE_HOSTNAME ||
          -z $MSKC_CONNECTOR_DATABASE_PORT ||
          -z $MSKC_CONNECTOR_DATABASE_SECRET_ARN ||
          -z $MSKC_CONNECTOR_DATABASE_SERVER_ID ||
          -z $MSKC_CONNECTOR_DATABASE_SERVER_NAME ||
          -z $MSKC_CONNECTOR_DATABASE_INCLUDE_LIST ||
          -z $MSKC_CONNECTOR_TOPIC_PREFIX ||
          -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_NAME ||
          -z $MSKC_CONNECTOR_SCHEMA_HISTORY_INTERNAL_KAFKA_TOPIC ||
          -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_COMPATIBILITY ]]; then

        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ MskcConnectorName ]
            [ MskcConnectorArn ]
            [ MskcConnectorExecutionRoleName ]
            [ MskcConnectorExecutionRoleArn ]
            [ MskcWorkerConfigName ]
            [ MskcPluginName ]
            [ MskClusterName ]
            [ MskcConnectorMcuCount ]
            [ MskcConnectorWorkerCount ]
            [ MskcConnectorDatabaseHostname ]
            [ MskcConnectorDatabasePort ]
            [ MskcConnectorDatabaseSecretArn ]
            [ MskcConnectorDatabaseServerId ]
            [ MskcConnectorDatabaseServerName ]
            [ MskcConnectorDatabaseIncludeList ]
            [ MskcConnectorTopicPrefix ]
            [ MskcConnectorSchemaRegistryName ]
            [ MskcConnectorSchemaHistoryInternalKafkaTopic ]
            [ MskcConnectorSchemaRegistryCompatibility ]

EOF
        exit 1
    fi
    # plugin "osci-plugin-mysql-confluent-avro" required opts,
    # use case not if, in order to extend to multiple plugins in the future.
    case $MSKC_PLUGIN_NAME in
        osci-plugin-mysql-confluent-avro)
            if [[ -z $MSKC_CONNECTOR_SCHEMA_REGISTRY_URL ]]; then
                cat << EOF | sed 's/^ *//'
                    [ERROR]: One or multiple following options are missing in command line:

                    [ --mskc-connector-schema-registry-url ]

EOF
                exit 1
            fi
        ;;
    esac
}

printMskcConnectorConfig() {
    printHeading "MSK CONNECT CONNECTOR CONFIGURATION"
    jq '.MskcConnectors' $OSCI_CONF_FILE && echo ""
}
