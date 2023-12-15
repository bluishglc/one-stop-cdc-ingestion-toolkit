#!/usr/bin/env bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

configureS3() {
    printHeading "CONFIGURE S3"
    checkS3CliConfigureOpts
    createHomeBucketIfNotExists
    saveS3Config
}

# --------------------------------------------    Configure Functions    --------------------------------------------- #

createHomeBucketIfNotExists() {
    aws s3 ls s3://$HOME_BUCKET &> /dev/null
    if ! aws s3 ls s3://$HOME_BUCKET &> /dev/null; then
        echo -ne "[INFO]: Creating the s3 home bucket [ s3://$HOME_BUCKET ] ...\n\n"
        aws s3 mb s3://$HOME_BUCKET
    else
        echo -ne "[INFO]: The s3 home bucket [ s3://$HOME_BUCKET ] already exists.\n\n"
    fi
}

saveS3Config() {
    echo -ne "[INFO]: Saving the s3 configuration ...\n\n"
    s3Config=$(jo HomeBucket=$HOME_BUCKET)
    (IFS=;cat <<< $(jq --argjson s3Config "$s3Config" '.S3=$s3Config' $OSCI_CONF_FILE) > $OSCI_CONF_FILE)
    # always reload after saved, keep config variables consistent with config file
    loadS3Config
    printS3Config
}

loadS3Config() {
    HOME_BUCKET=$(jq -r '.S3.HomeBucket' $OSCI_CONF_FILE)
    checkS3CfgOpts
}

printS3Config() {
    printHeading "S3 CONFIGURATION"
    jq '.S3' $OSCI_CONF_FILE && echo ""
}

# --------------------------------------------    Checking Functions    ---------------------------------------------- #

checkS3CliConfigureOpts() {
    echo -ne "[INFO]: Checking the s3 'configure' command options...\n\n"
    if [[ -z $HOME_BUCKET ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in command line:

            [ --home-bucket ]

EOF
        exit 1
    fi
}

checkS3CfgOpts() {
    echo -ne "[INFO]: Checking the s3 configuration options...\n\n"
    if [[ -z $HOME_BUCKET ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: One or multiple following options are missing in configuration:

            [ HomeBucket ]

EOF
        exit 1
    fi
}



