#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

configureVpc() {
    printHeading "CONFIGURE VPC"
    checkVpcCliConfigureOpts
    saveVpcConfig
}

# --------------------------------------------    Configure Functions    --------------------------------------------- #

loadVpcConfig() {
    VPC_ID=$(jq -r '.VPC.VpcId' $OSCI_CONF_FILE)
    SUBNET_IDS=($(jq -rc '.VPC.SubnetIds | @sh' $OSCI_CONF_FILE | tr -d \'))
    SECURITY_GROUP_IDS=($(jq -rc '.VPC.SecurityGroupIds | @sh' $OSCI_CONF_FILE | tr -d \'))
    # another way to build bash array as following
    # readarray -t SUBNET_IDS < <(jq -rc '.SubnetIds[]' $OSCI_CONF_FILE)
    # readarray -t SECURITY_GROUP_IDS < <(jq -rc '.SecurityGroupIds[]' $OSCI_CONF_FILE)
    checkVpcCfgOpts
}

saveVpcConfig() {
    echo -ne "[INFO]: Saving the vpc configuration ...\n\n"
    vpcConfig=$(jo VpcId=$VPC_ID \
        SubnetIds=$(jo -a "${SUBNET_IDS[@]}") \
        SecurityGroupIds=$(jo -a "${SECURITY_GROUP_IDS[@]}"))
    # NOTE: jq can NOT modify json file directly, we need manually write back file with cat <<< ... > xxx.json, however, in this way,
    # we will lose json format, we have to remove default IFS, but this will impact on other scripts, so we encapsulate all in a subshell!
    (IFS=;cat <<< $(jq --argjson vpcConfig "$vpcConfig" '.VPC=$vpcConfig' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved, keep config variables consistent with config file
    loadVpcConfig
    printVpcConfig
}

printVpcConfig() {
    printHeading "VPC CONFIGURATION"
    jq '.VPC' $OSCI_CONF_FILE && echo ""
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkVpcCliConfigureOpts() {
    echo -ne "[INFO]: Checking the vpc 'configure' command options...\n\n"
    if [[ -z $VPC_ID ||
          -z ${SUBNET_IDS[*]} ||
          -z ${SECURITY_GROUP_IDS[*]} ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --vpc-id ]
            [ --subnet-ids ]
            [ --security-group-ids ]

EOF
        exit 1
    fi
}

checkVpcCfgOpts() {
    echo -ne "[INFO]: Checking the vpc configuration options...\n\n"
    if [[ -z $VPC_ID ||
          -z ${SUBNET_IDS[*]} ||
          -z ${SECURITY_GROUP_IDS[*]} ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ VpcId ]
            [ SubnetIds ]
            [ SecurityGroupIds ]

EOF
        exit 1
    fi
}
