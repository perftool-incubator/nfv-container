#!/bin/bash

WORKSHOP_PL=${1:-"workshop.pl"}
NFV_CONTAINER_GIT_URL=${2:-"https://github.com/perftool-incubator/nfv-container.git"}

WORK_DIR=$(dirname $0)

if pushd ${WORK_DIR} > /dev/null; then
    cp requirements.json requirements.json.tmp
    sed -i -e "s|%NFV_CONTAINER%|${NFV_CONTAINER_GIT_URL}|" requirements.json.tmp

    exec ${WORKSHOP_PL} \
	--label nfv-container-dpdk-testpmd \
	--userenv userenv.json \
	--requirements requirements.json.tmp \
	--config config.json \
	--skip-update false \
	--log-level info \
	--force true
else
    echo "ERROR"
fi
