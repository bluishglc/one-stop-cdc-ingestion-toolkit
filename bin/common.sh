#!/bin/bash

# -----------------------------------------------    Main  Functions    ---------------------------------------------- #

checkMskClusterAuthType() {
    if [[ ! "${MSK_CLUSTER_AUTH_TYPES[*]}" =~ "$MSK_CLUSTER_AUTH_TYPE" ]]; then
        cat << EOF | sed 's/^ *//'
            [ERROR]: Unknown msk cluster authentication type [ $MSK_CLUSTER_AUTH_TYPE ], only following types are supported:

            [ IAM ]
            [ NONE ]

EOF
        exit 1
    fi
}