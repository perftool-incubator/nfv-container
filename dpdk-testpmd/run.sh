#!/bin/bash

# env vars:
#   RING_SIZE (default 2048)

REPO_DIR="$(dirname $0)/.."

source ${REPO_DIR}/common/lib.sh

echo
echo "Starting ${0}"
echo

echo "############### Logging ENV ###############"
env
echo "###########################################"

# find the SRIOV devices
# OCP creates environment variables which contain information about the devices
# example:
#   PCIDEVICE_OPENSHIFT_IO_MELLANOXA=0000:86:00.2
#   PCIDEVICE_OPENSHIFT_IO_MELLANOXB=0000:86:01.4
PCI_DEVICE_LIST=$(env | sed -n -r -e 's/PCIDEVICE.*=(.*)/\1/p' | tr ',\n' ' ')

if [ -z "${PCI_DEVICE_LIST}" ]; then
    echo "ERROR: Couldn't find any PCI devices!"
    exit 1
else
    DEVICE_COUNT=$(echo "${PCI_DEVICE_LIST}" | wc -w)
    if [ "${DEVICE_COUNT}" != 2 ]; then
	echo "ERROR: This script only supports 2 devices!"
	exit 1
    fi

    DEVICE_A=$(echo "${PCI_DEVICE_LIST}" | cut -f1 -d ' ')
    DEVICE_B=$(echo "${PCI_DEVICE_LIST}" | cut -f2 -d ' ')
fi

echo
echo "################# DEVICES #################"
echo "DEVICE_A=${DEVICE_A}"
echo "DEVICE_B=${DEVICE_B}"
echo "###########################################"

if [ -z "${DEVICE_A}" -o -z "${DEVICE_B}" ]; then
    echo
    echo "ERROR: Could not find DEVICE_A and/or DEVICE_B"
    exit 1
fi

function get_vf_driver() {
    ls /sys/bus/pci/devices/${1}/driver/module/drivers | sed -n -r 's/.*:(.+)/\1/p'
}

DEVICE_A_VF_DRIVER=$(get_vf_driver ${DEVICE_A})
DEVICE_B_VF_DRIVER=$(get_vf_driver ${DEVICE_B})

echo
echo "################ VF DRIVER ################"
echo "DEVICE_A_VF_DRIVER=${DEVICE_A_VF_DRIVER}"
echo "DEVICE_B_VF_DRIVER=${DEVICE_B_VF_DRIVER}"
echo "###########################################"

if [ -z "${DEVICE_A_VF_DRIVER}" -o -z "${DEVICE_B_VF_DRIVER}" ]; then
    echo
    echo "ERROR: Could not VF driver for DEVICE_A and/or DEVICE_B"
    exit 1
fi

if [ -z "${RING_SIZE}" ]; then
    RING_SIZE=2048
fi

if [ -z "${SOCKET_MEM}" ]; then
    SOCKET_MEM="1024,1024"
fi

if [ -z "${MEMORY_CHANNELS}" ]; then
    MEMORY_CHANNELS="4"
fi

CPUS_ALLOWED=$(get_cpus_allowed)
CPUS_ALLOWED_EXPANDED=$(expand_number_list "${CPUS_ALLOWED}")
CPUS_ALLOWED_SEPARATED=$(separate_comma_list "${CPUS_ALLOWED_EXPANDED}")
CPUS_ALLOWED_ARRAY=(${CPUS_ALLOWED_SEPARATED})

echo
echo "################# VALUES ##################"
echo "CPUS_ALLOWED=${CPUS_ALLOWED}"
echo "CPUS_ALLOWED_EXPANDED=${CPUS_ALLOWED_EXPANDED}"
echo "CPUS_ALLOWED_SEPARATED=${CPUS_ALLOWED_SEPARATED}"
echo "RING_SIZE=${RING_SIZE}"
echo "SOCKET_MEM=${SOCKET_MEM}"
echo "MEMORY_CHANNELS=${MEMORY_CHANNELS}"
echo "###########################################"

if [ ${#CPUS_ALLOWED_ARRAY[@]} -lt 3 ]; then
    echo
    echo "ERROR: This test needs at least 3 CPUs!"
    exit 1
fi

function bind_device_driver() {
    local DEVICE=${1}
    local OLD_DRIVER=${2}
    local NEW_DRIVER=${3}

    if [ "${OLD_DRIVER}" == "mlx5_core" -o "${NEW_DRIVER}" == "mlx5_core" ]; then
	echo "WARNING: Ignoring bind driver request for '${DEVICE}' due to mlx5_core"
	return
    fi

    dpdk-devbind -u ${DEVICE}
    dpdk-devbind -b ${NEW_DRIVER} ${DEVICE}
}

bind_device_driver "${DEVICE_A}" "${DEVICE_A_VF_DRIVER}" "vfio-pci"
bind_device_driver "${DEVICE_B}" "${DEVICE_B_VF_DRIVER}" "vfio-pci"

testpmd \
    -l ${CPUS_ALLOWED_ARRAY[0]},${CPUS_ALLOWED_ARRAY[1]},${CPUS_ALLOWED_ARRAY[2]} \
    --socket-mem ${SOCKET_MEM} \
    -n ${MEMORY_CHANNELS} \
    --proc-type auto \
    --file-prefix pg \
    -w ${DEVICE_A} \
    -w ${DEVICE_B} \
    -- \
    --nb-cores 2 \
    --nb-ports 2 \
    --portmask 3 \
    --auto-start \
    --rxq 1 \
    --txq 1 \
    --rxd ${RING_SIZE} \
    --txd ${RING_SIZE}

bind_device_driver "${DEVICE_A}" "vfio-pci" "${DEVICE_A_VF_DRIVER}"
bind_device_driver "${DEVICE_B}" "vfio-pci" "${DEVICE_B_VF_DRIVER}"