#!/bin/bash

REPO_DIR=$(dirname $0)

echo "################# Startup #################"

if pushd ${REPO_DIR} > /dev/null; then
    echo "Making sure nfv-container GIT repo is updated..."
    git pull
    echo

    echo "Requested type is ${1}"
    case "${1}" in
	"dpdk-testpmd")
	    echo -e "###########################################\n"
	    exec ${1}/run.sh
	    ;;
	*)
	    echo "ERROR: Unknown type [${1}]"
	    echo -e "###########################################\n"
	    exit 1
	    ;;
    esac

    popd > /dev/null
else
    echo "ERROR: Could not pushd to ${REPO_DIR}"
    echo -e "###########################################\n"
    exit 1
fi
