#!/usr/bin/env bash




sudo ln -s /home/ec2-user/one-stop-cdc-ingestion-toolkit-1.0/bin/osci.sh /usr/bin/osci




OSCI_HOME="$(cd "`dirname $(readlink -nf "$0")`"/..; pwd -P)"

source "$OSCI_HOME/bin/util.sh"

REGION=""
APP_BUCKET=""
DATA_BUCKET=""
AIRFLOW_DAGS_HOME=""
ACCESS_KEY_ID=""
ACCESS_KEY=""

ROLE_ARN=""
CONSTANTS_FILE="$OSCI_HOME/bin/constants.sh"

install() {
    printHeading "INSTALL SERVERLESS DATALAKE"
    installAwsCli
    configAwsCli
    createIamRole
    replaceEnvVars
    createCliShortcuts
    # initialize serverless datalake
    $OSCI_HOME/bin/sdl.sh init
    printHeading "ALL DONE"
}

createIamRole() {
    # create sdl-iam-role if not exists
    aws iam get-role --region "$REGION" --role-name sdl-iam-role &> /dev/null
    if [ "$?" != "0" ]; then
        echo "Creating sdl-iam-role ..."
        aws cloudformation deploy \
            --region "$REGION" \
            --stack-name sdl-iam-role \
            --no-fail-on-empty-changeset \
            --capabilities CAPABILITY_NAMED_IAM \
            --template-file $OSCI_HOME/cfn/sdl-iam-role.template &> /dev/null
    fi

    ROLE_ARN=$(aws iam get-role --role-name sdl-iam-role --query Role.Arn --output text)
    echo -ne "\nFound sdl-iam-role arn: [ $ROLE_ARN ]\n"
}

replaceEnvVars() {
    # replace environment-related variables
    echo "Replace environment-related variables ..."
    sed -i "s|REGION=.*|REGION=$REGION|g" "$CONSTANTS_FILE"
    sed -i "s|ROLE_ARN=.*|ROLE_ARN=$ROLE_ARN|g" "$CONSTANTS_FILE"
    sed -i "s|APP_BUCKET=.*|APP_BUCKET=$APP_BUCKET|g" "$CONSTANTS_FILE"
    sed -i "s|DATA_BUCKET=.*|DATA_BUCKET=$DATA_BUCKET|g" "$CONSTANTS_FILE"
    sed -i "s|AIRFLOW_DAGS_HOME=.*|AIRFLOW_DAGS_HOME=$AIRFLOW_DAGS_HOME|g" "$CONSTANTS_FILE"

    find "$OSCI_HOME/sql/" -type f -name "*.sql" -print0 | xargs -0 sed -i "s|s3://[a-zA-Z0-9_-]*/|s3://$DATA_BUCKET/|g"
}

createCliShortcuts() {
    # create shortcuts for cli
    echo "Install shortcuts for cli ..."
    sudo yum list installed jq &> /dev/null
    if [ "$?" != "0" ]; then sudo yum -y install jq; fi
    sudo rm -f "/usr/bin/sdl"
    sudo ln -s "$OSCI_HOME/bin/sdl.sh" "/usr/bin/sdl"
    sudo rm -f "/usr/bin/sdl-job"
    sudo ln -s "$OSCI_HOME/bin/sdl-job.sh" "/usr/bin/sdl-job"
    sudo rm -f "/usr/bin/sdl-crawler"
    sudo ln -s "$OSCI_HOME/bin/sdl-crawler.sh" "/usr/bin/sdl-crawler"
    sudo rm -f "/usr/bin/sdl-feeder"
    sudo ln -s "$OSCI_HOME/bin/feeder.sh" "/usr/bin/sdl-feeder"
}

installAwsCli() {
    # aws cli is very stupid!
    # for v1, it is installed via rpm/yum, so with 'yum list installed awscli', we get get version
    # for v2, it is installed via zip package, it does NOT work with 'yum list installed awscli', only 'aws --version' works
    # but for v1, 'aws --version' does not work, it DO print version message, but does NOT return string value!
    # if let message=$(aws --version), it prints message on console, but $message is empty!
    # so, it is REQUIRED to append '2>&1', the following is right way to get version:
    # awscliVer=$(aws --version 2>&1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*' | head -n1)
    rm /tmp/awscli -rf
    echo "Remove awscli v1 if exists ..."
    sudo yum -y remove awscli

    echo "Remove awscli v2 if exists in case not latest version ..."
    sudo rm /usr/bin/aws
    sudo rm /usr/local/bin/aws
    sudo rm /usr/bin/aws_completer
    sudo rm /usr/local/bin/aws_completer
    sudo rm -rf /usr/local/aws-cli

    echo "Install latest awscli v2 ..."
    wget "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -P "/tmp/awscli/"
    unzip /tmp/awscli/awscli-exe-linux-x86_64.zip -d /tmp/awscli/ &> /dev/null
    sudo /tmp/awscli/aws/install
    sudo ln -s /usr/local/bin/aws /usr/bin/aws
}

configAwsCli() {
    mkdir -p ~/.aws
    cat <<-EOF > ~/.aws/config
[default]
region = $REGION
EOF
    cat <<-EOF > ~/.aws/credentials
[default]
aws_access_key_id = $ACCESS_KEY_ID
aws_secret_access_key = $ACCESS_KEY
EOF
}

parseArgs() {
    if [ $# -eq 0 ]; then
        printUsage
        exit 0
    fi

    optString="r:a:d:h:i:k"
    longOptString="region:,app-bucket:,data-bucket:,airflow-dags-home:,access-key-id:,access-key:"

    # IMPORTANT!! -o option can not be omitted, even there are no any short options!
    # otherwise, parsing will go wrong!
    OPTS=$(getopt -o "$optString" -l "$longOptString" -- "$@")
    exitCode=$?
    if [ $exitCode -ne 0 ]; then
        echo ""
        printUsage
        exit 1
    fi
    eval set -- "$OPTS"
    while true; do
        case "$1" in
            -r|--region)
                REGION="${2}"
                shift 2
                ;;
            -a|--app-bucket)
                APP_BUCKET="${2}"
                shift 2
                ;;
            -d|--data-bucket)
                DATA_BUCKET="${2}"
                shift 2
                ;;
            -h|--airflow-dags-home)
                AIRFLOW_DAGS_HOME="${2}"
                shift 2
                ;;
            -i|--access-key-id)
                ACCESS_KEY_ID="${2}"
                shift 2
                ;;
            -k|--access-key)
                ACCESS_KEY="${2}"
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
    echo "SYNOPSIS"
    echo ""
    echo "$0 [--OPTION1 VALUE1] [--OPTION2 VALUE2] ..."
    echo ""
    echo "OPTIONS:"
    echo ""
    echo "-r|--region                           the region of project to be deployed"
    echo "-a|--app-bucket                       the bucket for app to deploy"
    echo "-d|--data-bucket                      the bucket for datalake to store data"
    echo "-h|--airflow-dags-home                the dags home for MWAA (airflow)"
    echo "-i|--access-key-id                    the access key id, used by aws cli"
    echo "-i|--access-key                       the access key file, used by aws cli"
    echo ""
    echo "EXAMPLES:"
    echo ""
    echo "# install project"
    echo -ne "$0 --region us-east-1 --app-bucket sdl-app --data-bucket sdl-data --airflow-dags-home s3://<my-airflow-dags> --access-key-id <my-access-key-id> --access-key <my-access-key>"
    echo ""
    echo ""
}

# -----------------------------------------------    Script Entrance    ---------------------------------------------- #

parseArgs "$@"

install
