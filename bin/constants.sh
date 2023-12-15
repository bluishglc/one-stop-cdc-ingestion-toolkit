#!/usr/bin/env bash

OSCI_CNF_DIR=$OSCI_HOME/cnf
OSCI_LOG_DIR=$OSCI_HOME/log
OSCI_TMP_DIR=$OSCI_HOME/tmp

OSCI_CONF_FILE=$OSCI_CNF_DIR/osci-conf.json

MSKC_PLUGINS=(osci-plugin-mysql-avro osci-plugin-mysql-gsr-avro osci-plugin-mysql-confluent-avro)

MYSQL_GSR_AVRO_PLUGIN_URL='https://github.com/bluishglc/one-stop-cdc-ingestion-toolkit/releases/download/v1.0/debezium-mysql-connector-2.2.0-gsr-avro-converter-1.1.15-msk-config-providers-0.1.0.zip'
MYSQL_CONFLUENT_AVRO_PLUGIN_URL='https://github.com/bluishglc/one-stop-cdc-ingestion-toolkit/releases/download/v1.0/debezium-mysql-connector-2.2.0-confluent-avro-converter-7.4.0-msk-config-providers-0.1.0.zip'

# The following 2 plugin zip file don't contain "msk-config-providers-0.1.0" package. keep them, may be useful for some cases in the future.
# MYSQL_GSR_AVRO_PLUGIN_URL='https://github.com/bluishglc/one-stop-cdc-ingestion-toolkit/releases/download/v1.0/debezium-mysql-connector-2.2.0-gsr-avro-converter-1.1.15.zip'
# MYSQL_CONFLUENT_AVRO_PLUGIN_URL='https://github.com/bluishglc/one-stop-cdc-ingestion-toolkit/releases/download/v1.0/debezium-mysql-connector-2.2.0-confluent-avro-converter-7.4.0.zip'

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
REGION=$(aws configure get region)

MSK_CLUSTER_AUTH_TYPES=(NONE IAM)

