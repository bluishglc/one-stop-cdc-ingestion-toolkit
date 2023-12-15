#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

# This a step to setup a mskc plugin, however, usually, this is a one-time job,
# once a plugin is installed, no need to create it anymore.
installMskcPlugin() {
    printHeading "INSTALL MSK CONNECT PLUGIN [ $MSKC_PLUGIN_NAME ]"
    checkMskcPluginCliOpts
    loadS3Config
    if [[ "$(isMskcPluginExisting)" == "false" ]]; then
        uploadMskcPlugin
        createMskcPlugin
        # immediately save cluster configs
        saveMskcPluginConfig
    else
        if [[ "$(hasMskcPluginConfigs)" == "true" ]]; then
            echo -ne "[INFO]: The msk connect plugin [ $MSKC_PLUGIN_NAME ] already exists.\n\n"
        else
            cat << EOF | sed 's/^ *//'
                [ERROR]: The msk connect plugin: [ $MSKC_PLUGIN_NAME ] exists in your aws account,
                         but it is not configured in osci, please check your osci configuration file.
EOF
            exit 1
        fi
    fi
}

configureMskcPlugin() {
    printHeading "CONFIGURE MSK CONNECT PLUGIN"
    checkMskcPluginCliConfigureOpts
    # immediately save cluster configs
    saveMskcPluginConfig
}

removeMskcPlugin() {
    echo -ne "[INFO]: Deleting the msk connect plugin [ $MSKC_PLUGIN_NAME ] ...\n\n"
    checkMskcPluginCliOpts
    loadMskcPluginConfig
    aws kafkaconnect delete-custom-plugin --custom-plugin-arn "$MSKC_PLUGIN_ARN" || true
    pluginFileS3Path=s3://$HOME_BUCKET/plugins/$MSKC_PLUGIN_FILE_NAME
    if aws s3 ls $pluginFileS3Path &> /dev/null; then
        aws s3 rm $pluginFileS3Path
    fi
}

# ---------------------------------------------    Operation Functions    -------------------------------------------- #

isMskcPluginExisting() {
    lookupResult=$(aws kafkaconnect list-custom-plugins \
        --no-paginate --no-cli-pager --output text \
        --query 'customPlugins[?name==`'"${MSKC_PLUGIN_NAME}"'`].name')
    if [[ -n $lookupResult ]]; then
        echo "true"
    else
        echo "false"
    fi
}

hasMskcPluginConfigs() {
    mskcPluginConfig=$(jq '.MskcPlugins[] | select (.MskcPluginName == "'"$MSKC_PLUGIN_NAME"'")' $OSCI_CONF_FILE)
    if [[ -n $mskcPluginConfig ]]; then
        echo "true"
    else
        echo "false"
    fi
}

uploadMskcPlugin() {
    pluginFileLocalPath=$OSCI_TMP_DIR/$MSKC_PLUGIN_FILE_NAME
    pluginFileS3Path=s3://$HOME_BUCKET/plugins/$MSKC_PLUGIN_FILE_NAME
    if aws s3 ls $pluginFileS3Path &> /dev/null; then
        echo -ne "[INFO]: The plugin file [ $MSKC_PLUGIN_FILE_NAME ] already exists on s3 home bucket.\n\n"
    else
        echo -ne "[INFO]: Downloading the plugin file [ $MSKC_PLUGIN_FILE_NAME ] ...\n\n"
        wget $MSKC_PLUGIN_URL -O $pluginFileLocalPath &> /dev/null
        aws s3 cp $pluginFileLocalPath s3://$HOME_BUCKET/plugins/$MSKC_PLUGIN_FILE_NAME
        echo -ne "[INFO]: The plugin file [ $MSKC_PLUGIN_FILE_NAME ] is uploaded to s3 home bucket.\n\n"
    fi
}

createMskcPlugin() {
    echo -ne "[INFO]: Creating the msk connect plugin [ $MSKC_PLUGIN_NAME ] ...\n\n"
    MSKC_PLUGIN_ARN=$(aws kafkaconnect create-custom-plugin \
            --no-paginate --no-cli-pager --output text \
            --name $MSKC_PLUGIN_NAME \
            --content-type ZIP \
            --location "s3Location={bucketArn=arn:aws:s3:::$HOME_BUCKET,fileKey=plugins/$MSKC_PLUGIN_FILE_NAME}" \
            --query customPluginArn)
    if [[ -n $MSKC_PLUGIN_ARN ]]; then
        echo -ne "[INFO]: The plugin [ $MSKC_PLUGIN_NAME ] is installed successfully!\n\n"
    else
        echo -ne "[ERROR]: The plugin [ $MSKC_PLUGIN_NAME ] is installed failed!\n\n"
        exit 1
    fi
}

# --------------------------------------------    Configure Functions    --------------------------------------------- #

loadMskcPluginConfig() {
    if [[ "$(hasMskcPluginConfigs)" == "true" ]]; then
        MSKC_PLUGIN_NAME=$(jq -r '.MskcPlugins[] | select (.MskcPluginName == "'"$MSKC_PLUGIN_NAME"'") | .MskcPluginName' $OSCI_CONF_FILE)
        MSKC_PLUGIN_ARN=$(jq -r '.MskcPlugins[] | select (.MskcPluginName == "'"$MSKC_PLUGIN_NAME"'") | .MskcPluginArn' $OSCI_CONF_FILE)
        checkMskcPluginCfgOpts
    else
        cat << EOF | sed 's/^ *//'
            [ERROR]: Can not find the msk connect plugin: [ $MSKC_PLUGIN_NAME ]!
                     1. It may not exist in your aws account, please check out your aws msk console.
                     2. It exists, but may not be in osci configuration, please check out your osci configuration file.
EOF
        exit 1
    fi
}

saveMskcPluginConfig() {
    echo -ne "[INFO]: Saving the msk connect plugin [ $MSKC_PLUGIN_NAME ] configuration ...\n\n"
    # delete the same name plugin first
    (IFS=;cat <<< $(jq 'del(.MskcPlugins[] | select (.MskcPluginName == "'"$MSKC_PLUGIN_NAME"'"))' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    mskcPluginConfig=$(jo MskcPluginName=$MSKC_PLUGIN_NAME MskcPluginArn=$MSKC_PLUGIN_ARN)
    (IFS=;cat <<< $(jq --argjson mskcPluginConfig "$mskcPluginConfig" '.MskcPlugins += [$mskcPluginConfig]' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved!!
    # every config items must keep consistent with config file
    # and only load action can set: MskcPlugin_CONFIGURED=true
    loadMskcPluginConfig
    printMskcPluginConfig
}

printMskcPluginConfig() {
    printHeading "MSK CONNECT PLUGIN CONFIGURATION"
    jq '.MskcPlugins' $OSCI_CONF_FILE && echo ""
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

setMskcPluginNameCascadeOpts() {
    case $MSKC_PLUGIN_NAME in
        osci-plugin-mysql-gsr-avro)
            MSKC_PLUGIN_URL=$MYSQL_GSR_AVRO_PLUGIN_URL
        ;;
        osci-plugin-mysql-confluent-avro)
            MSKC_PLUGIN_URL=$MYSQL_CONFLUENT_AVRO_PLUGIN_URL
        ;;
        *)
            echo -ne "[ERROR]: Unknown plugin name!\n\n"
                    cat << EOF | sed 's/^ *//'
                        [ERROR]: Unknown plugin [ $MSKC_PLUGIN_NAME ], only following plugins are supported:

                        [ osci-plugin-mysql-avro ]
                        [ osci-plugin-mysql-gsr-avro ]
                        [ osci-plugin-mysql-confluent-avro ]

EOF
            exit 1
        ;;
    esac
    MSKC_PLUGIN_FILE_NAME=$(basename $MSKC_PLUGIN_URL)
}

checkMskcPluginCliOpts() {
    echo -ne "[INFO]: Checking the msk connect plugin 'install', 'remove' command options...\n\n"
    if [[ -z $MSKC_PLUGIN_NAME ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-plugin-name ]

EOF
        exit 1
    fi
}

checkMskcPluginCliConfigureOpts() {
    echo -ne "[INFO]: Checking the msk connect plugin 'configure' command options...\n\n"
    if [[ -z $MSKC_PLUGIN_NAME ||
          -z $MSKC_PLUGIN_ARN ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --mskc-plugin-name ]
            [ --mskc-plugin-arn ]

EOF
        exit 1
    fi
}

checkMskcPluginCfgOpts() {
    echo -ne "[INFO]: Checking the msk connect plugin configuration options...\n\n"
    if [[ -z $MSKC_PLUGIN_NAME ||
          -z $MSKC_PLUGIN_ARN ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ MskcPluginName ]
            [ MskcPluginArn ]

EOF
        exit 1
    fi
}
