#!/bin/bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

# All one-time, global-level options should be configured with this function.
configure() {
    configureS3
    configureVpc
    configureMskCluster
}

setup() {
    installMskcPlugin
    setupMskcWorkerConfig
    setupMskcConnector
}

quickstart() {
    configureS3
    configureVpc
    setupMskCluster
    installMskcPlugin
    setupMskcWorkerConfig
    setupMskcConnector
}

listConfigs() {
    printS3Config
    printVpcConfig
    printMskClusterConfig
    printMskcPluginConfig
    printMskcWorkerConfigConfig
    printMskcConnectorConfig
}

printConfigs() {
    printHeading "CONFIGURATIONS"
    jq '.' $OSCI_CONF_FILE && echo ""
}