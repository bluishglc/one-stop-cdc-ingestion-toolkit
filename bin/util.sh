#!/usr/bin/env bash

printHeading() {
    title="$1"
    if [ "$TERM" = "dumb" -o "$TERM" = "unknown" ]; then
        paddingWidth=60
    else
        paddingWidth=$((($(tput cols)-${#title})/2-5))
    fi
    printf "\n%${paddingWidth}s"|tr ' ' '='
    printf "    $title    "
    printf "%${paddingWidth}s\n\n"|tr ' ' '='
}

contains() {
    xs="$1"
    x="$2"
    for i in "${xs[@]}"; do
        echo "$i"
        if [ "$i" == "$x" ]; then
            echo "true"
            break
        fi
    done
    echo "false"
}

# jq 1.6 is required for write bash array to json file
# however, yum installed is 1.5, so must install it manually!
installJq16() {
   sudo wget wget https://github.com/jqlang/jq/releases/download/jq-1.6/jq-linux64 -O /usr/bin/jq
   sudo chmod a+x /usr/bin/jq
}

exec() {
    eval "$1"
}