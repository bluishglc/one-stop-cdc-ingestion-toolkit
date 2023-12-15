#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

# This a step to setup a mskc connector, however, usually, this is a one-time job,
# once a copy of worker-configuration is created, no need to create it anymore.
setupMskcWorkerConfig() {
    printHeading "SETUP MSK CONNECT WORKER CONFIGURATION"
    checkMskcWorkerConfigCliSetupOpts
    if [[ "$(isMskcWorkerConfigExisting)" == "false" ]]; then
        createMskcWorkerConfig
        # immediately save cluster configs
        saveMskcWorkerConfigConfig
    else
        if [[ "$(isMskcWorkerConfigConfigured)" == "true" ]]; then
            echo -ne "[INFO]: The msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] already exists.\n\n"
        else
            cat << EOF | sed 's/^ *//'
                [ERROR]: The msk connect worker-configuration: [ $MSKC_WORKER_CONFIG_NAME ] exists in your aws account,
                         but it is not configured in osci, please check your osci configuration file.

EOF
            exit 1
        fi
    fi
}

configureMskcWorkerConfig() {
    printHeading "CONFIGURE MSK CONNECT WORKER CONFIGURATION"
    checkMskcWorkerConfigCliConfigureOpts
    # immediately save cluster configs
    saveMskcWorkerConfigConfig
}

# Oops, it's terrible! there is no cli/api to delete a worker configuration!
removeMskcWorkerConfig() {
    checkMskcWorkerConfigCliRemoveOpts
    # echo -ne "[INFO]: Deleting the msk connect worker configuration [ $MSKC_WORKER_CONFIG_NAME ] ...\n\n"
    # aws kafkaconnect delete-worker-configuration --worker-configuration-arn "$MSKC_PLUGIN_ARN"
    # remove configuration
    (IFS=;cat <<< $(jq 'del(.MskcWorkerConfig)' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    cat << EOF | sed 's/^ *//'
        [WARNING]: The msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] is just deleted from configuration file!
                   It is not really deleted from aws console, because for now, there is no delete api for worker-configuration!

EOF
}

# ---------------------------------------------    Operation Functions    -------------------------------------------- #

createMskcWorkerConfig() {
    # Notes:
    # 1. we only set options which only works in worker configuration, i.e. config.providers.*, and put all other options in connector configuration
    # 2. we always manage database credentials via secretsmanager, this is best practice.
    # 3. key.converter & value.converter are just placeholder here, because they are required for worker conf, they will be overridden on connector configuration
    # 4. --properties-file-content only accept base64 encoded string, and not wrapped(a single line)!
    echo -ne "[INFO]: Creating the msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] ...\n\n"
    cat << EOF | base64 --wrap=0 > $OSCI_TMP_DIR/properties-file-content.properties
key.converter=org.apache.kafka.connect.storage.StringConverter
value.converter=org.apache.kafka.connect.storage.StringConverter
config.providers=secretsmanager
config.providers.secretsmanager.class=com.amazonaws.kafka.config.providers.SecretsManagerConfigProvider
config.providers.secretsmanager.param.region=$REGION
EOF

    MSKC_WORKER_CONFIG_ARN=$(aws kafkaconnect create-worker-configuration \
        --no-paginate --no-cli-pager --output text \
        --name $MSKC_WORKER_CONFIG_NAME \
        --properties-file-content file://$OSCI_TMP_DIR/properties-file-content.properties \
        --query workerConfigurationArn)
    if [[ -n $MSKC_WORKER_CONFIG_ARN ]]; then
        echo -ne "[INFO]: The msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] is created successfully!\n\n"
    else
        echo -ne "[ERROR]: the msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] is created failed!\n\n"
        exit 1
    fi
}

isMskcWorkerConfigExisting() {
    lookupResult=$(aws kafkaconnect list-worker-configurations \
        --no-paginate --no-cli-pager --output text \
        --query 'workerConfigurations[?name==`'"${MSKC_WORKER_CONFIG_NAME}"'`].name')
    if [[ -n $lookupResult ]]; then
        echo "true"
    else
        echo "false"
    fi
}

isMskcWorkerConfigConfigured() {
    mskcWorkerConfigConfig=$(jq '.MskcWorkerConfig | select (.MskcWorkerConfigName == "'"$MSKC_WORKER_CONFIG_NAME"'")' $OSCI_CONF_FILE)
    if [[ -n $mskcWorkerConfigConfig ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# --------------------------------------------    Configure Functions    --------------------------------------------- #

loadMskcWorkerConfigConfig() {
    if [[ "$(isMskcWorkerConfigConfigured)" == "true" ]]; then
        MSKC_WORKER_CONFIG_NAME=$(jq -r '.MskcWorkerConfig.MskcWorkerConfigName' $OSCI_CONF_FILE)
        MSKC_WORKER_CONFIG_ARN=$(jq -r '.MskcWorkerConfig.MskcWorkerConfigArn' $OSCI_CONF_FILE)
        checkMskcWorkerConfigCfgOpts
    else
        cat << EOF | sed 's/^ *//'
            [ERROR]: Can not find the msk connect worker-configuration: [ $MSKC_WORKER_CONFIG_NAME ]!
                     1. It may not exist in your aws account, please check out your aws msk console.
                     2. It exists, but may not be in osci configuration, please check out your osci configuration file.
EOF

        exit 1
    fi
}


saveMskcWorkerConfigConfig() {
    echo -ne "[INFO]: Saving the msk connect worker-configuration [ $MSKC_WORKER_CONFIG_NAME ] configuration ...\n\n"
    mskcWorkerConfigConfig=$(jo MskcWorkerConfigName=$MSKC_WORKER_CONFIG_NAME MskcWorkerConfigArn=$MSKC_WORKER_CONFIG_ARN)
    (IFS=;cat <<< $(jq --argjson mskcWorkerConfigConfig "$mskcWorkerConfigConfig" '.MskcWorkerConfig=$mskcWorkerConfigConfig' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved!!
    # every config items must keep consistent with config file
    # and only load action can set: MskcWorkerConfig_CONFIGURED=true
    loadMskcWorkerConfigConfig
    printMskcWorkerConfigConfig
}

printMskcWorkerConfigConfig() {
    printHeading "MSK CONNECT WORKER CONFIGURATION CONFIGURATION"
    jq '.MskcWorkerConfig' $OSCI_CONF_FILE && echo ""
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkMskcWorkerConfigCliConfigureOpts() {
    echo -ne "[INFO]: Checking the msk connect worker-configuration 'configure' command options...\n\n"
    if [[ -z $MSKC_WORKER_CONFIG_NAME ||
          -z $MSKC_WORKER_CONFIG_ARN ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-worker-config-name ]
            [ --mskc-worker-config-arn ]

EOF
        exit 1
    fi
}

checkMskcWorkerConfigCliSetupOpts() {
    echo -ne "[INFO]: Checking the msk connect worker-configuration 'setup' command options...\n\n"
    if [[ -z $MSKC_WORKER_CONFIG_NAME ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-worker-config-name ]

EOF
        exit 1
    fi
}

checkMskcWorkerConfigCliRemoveOpts() {
    echo -ne "[INFO]: Checking the msk connect worker-configuration 'remove' command options...\n\n"
    if [[ -z $MSKC_WORKER_CONFIG_NAME ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-worker-config-name ]

EOF
        exit 1
    fi
}

checkMskcWorkerConfigCfgOpts() {
    echo -ne "[INFO]: Checking the msk connect worker-configuration configuration options...\n\n"
    if [[ -z $MSKC_WORKER_CONFIG_NAME ||
          -z $MSKC_WORKER_CONFIG_ARN ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ MskcWorkerConfigName ]
            [ MskcWorkerConfigArn ]

EOF
        exit 1
    fi
}
