#!/bin/bash

WORKSHOP_PL=${1:-"workshop.pl"}

WORK_DIR=$(dirname $0)

if pushd ${WORK_DIR} > /dev/null; then
    ${WORKSHOP_PL} \
	--label nfv-container-dpdk-testpmd \
	--userenv userenv.json \
	--requirements requirements.json \
	--config config.json \
	--skip-update true \
	--log-level info \
	--force true
else
    echo "ERROR"
fi
