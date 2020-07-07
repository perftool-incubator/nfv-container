#!/bin/bash

# env vars:
#   RING_SIZE (default 2048)
#   SOCKET_MEM (default autoconfigured)
#   MEMORY_CHANNELS (default 4)
#   PROMISC_DEVICES (default "n")
#   DISABLE_CPU_LOAD_BALANCE (default "n")
#   FORWARD_MODE (default "mac")
#   PEER_A_MAC (no default, required if FORWARD_MODE=="mac", error)
#   PEER_B_MAC (no default, required if FORWARD_MODE=="mac", error)
#   SRIOV_ID_A (no default, error)
#   SRIOV_ID_B (no default, error)
#   MTU (default 1518)

REPO_DIR="$(dirname $0)/.."

source ${REPO_DIR}/common/lib.sh

echo -e "\nStarting ${0}\n"

echo "############### Logging ENV ###############"
env
echo -e "###########################################\n"

echo "############### IP Address ################"
ip address
echo -e "###########################################\n"

if [ -z "${SRIOV_ID_A}" -o -z "${SRIOV_ID_B}" ]; then
    echo "ERROR: You must specify SRIOV_ID_A and SRIOV_ID_B environment variables"
    exit 1
fi

# find the SRIOV devices
# OCP creates environment variables which contain information about the devices
# example:
#   PCIDEVICE_OPENSHIFT_IO_MELLANOXA=0000:86:00.2
#   PCIDEVICE_OPENSHIFT_IO_MELLANOXB=0000:86:01.4

DEVICE_A=$(env | grep "PCIDEVICE_OPENSHIFT_IO_${SRIOV_ID_A}" | cut -f2 -d'=')
DEVICE_B=$(env | grep "PCIDEVICE_OPENSHIFT_IO_${SRIOV_ID_B}" | cut -f2 -d'=')

echo "################# DEVICES #################"
echo "DEVICE_A=${DEVICE_A}"
echo "DEVICE_B=${DEVICE_B}"
echo -e "###########################################\n"

if [ -z "${DEVICE_A}" -o -z "${DEVICE_B}" ]; then
    echo "ERROR: Could not find DEVICE_A and/or DEVICE_B"
    exit 1
fi

function get_vf_driver() {
    ls /sys/bus/pci/devices/${1}/driver/module/drivers | sed -n -r 's/.*:(.+)/\1/p'
}

DEVICE_A_VF_DRIVER=$(get_vf_driver ${DEVICE_A})
DEVICE_B_VF_DRIVER=$(get_vf_driver ${DEVICE_B})

echo "################ VF DRIVER ################"
echo "DEVICE_A_VF_DRIVER=${DEVICE_A_VF_DRIVER}"
echo "DEVICE_B_VF_DRIVER=${DEVICE_B_VF_DRIVER}"
echo -e "###########################################\n"

if [ -z "${DEVICE_A_VF_DRIVER}" -o -z "${DEVICE_B_VF_DRIVER}" ]; then
    echo "ERROR: Could not VF driver for DEVICE_A and/or DEVICE_B"
    exit 1
fi

CPUS_ALLOWED=$(get_cpus_allowed)
CPUS_ALLOWED_EXPANDED=$(expand_number_list "${CPUS_ALLOWED}")
CPUS_ALLOWED_SEPARATED=$(separate_comma_list "${CPUS_ALLOWED_EXPANDED}")
CPUS_ALLOWED_ARRAY=(${CPUS_ALLOWED_SEPARATED})

if [ -z "${RING_SIZE}" ]; then
    RING_SIZE=2048
fi

NODE_LIST="unknown"

if [ -z "${SOCKET_MEM}" ]; then
    # automatically determine what NUMA nodes need memory allocated
    if pushd /sys/devices/system/node > /dev/null; then
	SOCKET_MEM=""

	for node in $(ls -1d node*); do
	    NODE_NUM=$(echo ${node} | sed -e "s/node//")
	    if pushd $node > /dev/null; then
		NODE_CPU_PRESENT=0

		for cpu in ${CPUS_ALLOWED_SEPARATED}; do
		    if [ -d "cpu${cpu}" ]; then
			NODE_CPU_PRESENT=1
		    fi
		done

		if [ "${NODE_CPU_PRESENT}" == "1" ]; then
		    SOCKET_MEM+="1024,"
		    NODE_LIST="${NODE_NUM},"
		else
		    SOCKET_MEM+="0,"
		fi

		popd > /dev/null
	    fi
	done

	SOCKET_MEM=$(echo "${SOCKET_MEM}" | sed -e "s/,$//")
	NODE_LIST=$(echo "${NODE_LIST}" | sed -e "s/,$//")

	popd > /dev/null
    fi

    # if we didn't figure anything out just go with a safe default and
    # see if it works
    if [ -z "${SOCKET_MEM}" ]; then
	SOCKET_MEM="1024,1024"
    fi
fi

if [ -z "${MEMORY_CHANNELS}" ]; then
    MEMORY_CHANNELS="4"
fi

if [ -z "${DISABLE_CPU_LOAD_BALANCE}" ]; then
    DISABLE_CPU_LOAD_BALANCE="n"
fi

if [ -z "${PROMISC_DEVICES}" ]; then
    PROMISC_DEVICES="n"
fi

if [ -z "${MTU}" ]; then
    MTU="1518"
fi

if [ -z "${FORWARD_MODE}" ]; then
    FORWARD_MODE="mac"
fi

echo "################# VALUES ##################"
echo "CPUS_ALLOWED=${CPUS_ALLOWED}"
echo "CPUS_ALLOWED_EXPANDED=${CPUS_ALLOWED_EXPANDED}"
echo "CPUS_ALLOWED_SEPARATED=${CPUS_ALLOWED_SEPARATED}"
echo "NODE_LIST=${NODE_LIST}"
echo "RING_SIZE=${RING_SIZE}"
echo "SOCKET_MEM=${SOCKET_MEM}"
echo "MEMORY_CHANNELS=${MEMORY_CHANNELS}"
echo "DISABLE_CPU_LOAD_BALANCE=${DISABLE_CPU_LOAD_BALANCE}"
echo "PROMISC_DEVICES=${PROMISC_DEVICES}"
echo "FORWARD_MODE=${FORWARD_MODE}"
echo "PEER_A_MAC=${PEER_A_MAC}"
echo "PEER_B_MAC=${PEER_B_MAC}"
echo "MTU=${MTU}"
echo -e "###########################################\n"

case "${FORWARD_MODE}" in
    "mac"|"io")
	FORWARD_MODE="${FORWARD_MODE}"
	;;
    *)
	echo "ERROR: FORWARD_MODE must be either 'mac' or 'io'"
	exit 1
	;;
esac

if [ "${FOWARD_MODE}" == "mac" ]; then
    if [ -z "${PEER_A_MAC}" -o -z "${PEER_B_MAC}" ]; then
	echo "ERROR: You must define PEER_A_MAC and PEER_B_MAC environment variables"
	exit 1
    fi

    TESTPMD_FORWARD_MODE_ARGS=" --eth-peer=0,${PEER_A_MAC} \
                                --eth-peer=1,${PEER_B_MAC} \ "

fi

if [ ${#CPUS_ALLOWED_ARRAY[@]} -lt 3 ]; then
    echo "ERROR: This test needs at least 3 CPUs!"
    exit 1
else
    TESTPMD_CPU_LIST="${CPUS_ALLOWED_EXPANDED}"

    if [ ${#CPUS_ALLOWED_ARRAY[@]} -eq 3 ]; then
	TESTPMD_QUEUES=1
	TESTPMD_CORES=2
    elif [ ${#CPUS_ALLOWED_ARRAY[@]} -eq 5 ]; then
	TESTPMD_QUEUES=2
	TESTPMD_CORES=4
    elif [ ${#CPUS_ALLOWED_ARRAY[@]} -eq 7 ]; then
	TESTPMD_QUEUES=3
	TESTPMD_CORES=6
    elif [ ${#CPUS_ALLOWED_ARRAY[@]} -eq 9 ]; then
	TESTPMD_QUEUES=4
	TESTPMD_CORES=8
    else
	echo "ERROR: Unsupported CPU count,  ${#CPUS_ALLOWED_ARRAY[@]}, must be 3 or 5 or 7 or 9!"
	exit 1
    fi
fi

function bind_device_driver() {
    local DEVICE=${1}
    local OLD_DRIVER=${2}
    local NEW_DRIVER=${3}

    echo "############### BIND DRIVER ###############"
    echo "DEVICE=${DEVICE}"
    echo "OLD_DRIVER=${OLD_DRIVER}"
    echo "NEW_DRIVER=${NEW_DRIVER}"

    if [ "${OLD_DRIVER}" == "mlx5_core" -o "${NEW_DRIVER}" == "mlx5_core" ]; then
	echo "WARNING: Ignoring bind driver request for '${DEVICE}' due to mlx5_core"

	if [ "${PROMISC_DEVICES}" == "y" -a "${OLD_DRIVER}" == "mlx5_core" ]; then
	    NET_DEV=$(dpdk-devbind --status-dev net | grep "${DEVICE}" | sed -e "s|.*if=\(.*\)\sdrv.*|\1|")
	    echo "Turning on promisc mode for ${DEVICE} -> ${NET_DEV}"
	    ip link s ${NET_DEV} promisc on
	fi

	echo -e "###########################################\n"

	return
    fi

    dpdk-devbind -u ${DEVICE}
    dpdk-devbind -b ${NEW_DRIVER} ${DEVICE}

    echo -e "###########################################\n"
}

function device_status() {
    echo "############## DEVICE STATUS ##############"
    dpdk-devbind --status-dev net
    echo -e "###########################################\n"
}

device_status

bind_device_driver "${DEVICE_A}" "${DEVICE_A_VF_DRIVER}" "vfio-pci"
bind_device_driver "${DEVICE_B}" "${DEVICE_B_VF_DRIVER}" "vfio-pci"

device_status

if [ "${DISABLE_CPU_LOAD_BALANCE}" == "y" ]; then
    disable_cpu_load_balancing "${CPUS_ALLOWED_SEPARATED}"
fi

EXTRA_TESTPMD_ARGS=""
if [ ${MTU} -gt 2048 ]; then
    MBUF_SIZE=16384
    MBUFS=27242
    EXTRA_TESTPMD_ARGS+=" --mbuf-size=${MBUF_SIZE} --total-num-mbufs=${MBUFS}"
fi

TESTPMD_CMD="testpmd \
    -l ${TESTPMD_CPU_LIST} \
    --socket-mem ${SOCKET_MEM} \
    -n ${MEMORY_CHANNELS} \
    --proc-type auto \
    --file-prefix pg \
    -w ${DEVICE_A} \
    -w ${DEVICE_B} \
    -- \
    --forward-mode=${FORWARD_MODE} \
    ${TESTPMD_FORWARD_MODE_ARGS} \
    --nb-cores ${TESTPMD_CORES} \
    --nb-ports 2 \
    --portmask 3 \
    --auto-start \
    --rxq ${TESTPMD_QUEUES} \
    --txq ${TESTPMD_QUEUES} \
    --rxd ${RING_SIZE} \
    --txd ${RING_SIZE} \
    --max-pkt-len=${MTU} \
    ${EXTRA_TESTPMD_ARGS}"
TESTPMD_CMD=$(echo "${TESTPMD_CMD}" | sed -e "s/\s\+/ /g")

echo "################# TESTPMD #################"
echo -e "Command: ${TESTPMD_CMD}\n"

# start testpmd
tmux new-session -s testpmd -d "${TESTPMD_CMD}; touch /tmp/testpmd-stopped; sleep infinity"

function sigtermhandler() {
    echo "Caught SIGTERM"
    local PID=$(pgrep -f "coreutils.*sleep")
    if [ -n "${PID}" ]; then
	echo "Killing sleep with PID=${PID}"
	kill ${PID}
    else
	echo "Could not find PID for sleep"
    fi
}

trap sigtermhandler TERM

# block, waiting for a signal telling me to stop.  backgrounding and
# using wait allows for signal handling to occur
sleep infinity &
wait $!

# kill testpmd
pkill testpmd

# spin waiting for testpmd to exit
while [ ! -e "/tmp/testpmd-stopped" ]; do
    true
done
rm /tmp/testpmd-stopped

# capture the output from testpmd
echo -e "\nOutput from testpmd:\n"
tmux capture-pane -S - -E - -p -t testpmd

echo -e "###########################################\n"

# kill the sleep that is keeping tmux running
pkill -f sleep

if [ "${DISABLE_CPU_LOAD_BALANCE}" == "y" ]; then
    enable_cpu_load_balancing "${CPUS_ALLOWED_SEPARATED}"
fi

bind_device_driver "${DEVICE_A}" "vfio-pci" "${DEVICE_A_VF_DRIVER}"
bind_device_driver "${DEVICE_B}" "vfio-pci" "${DEVICE_B_VF_DRIVER}"

device_status
