#!/bin/bash
#
# Copyright (C) 2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Tx and Rx traffic flows for Intel X550 for Profinet SRIOV scenario.
#
# Hosts are 16 core x86 machines. Connection speed is 10G.
#

set -e

source ../lib/common.sh

#
# Parameters.
#
PF=$1

[ -z "${PF}" ] && PF="enp1s0f0"

#
# Configuration parameters.
#
PF1="${PF}np0"
VF1="${PF}v0"
VF2="${PF}v1"
VF3="${PF}v2"
VF4="${PF}v3"
HOSTNAME=$(hostname)

load_kernel_modules

#
# Setup interfaces.
#
ip link set dev "${PF1}" up

#
# Configure the card into DCB mode which has four or eight different traffic classes.
#
tc qdisc replace dev "${PF1}" handle 100 parent root mqprio num_tc 4 \
  map 0 1 2 3 0 1 2 3 0 1 2 3 0 1 2 3 \
  queues 1@0 1@1 1@2 1@3 \
  hw 1

#
# Create four virtual functions and wait for them.
#
echo 4 >"/sys/class/net/${PF1}/device/sriov_numvfs"

while ! [ -e "/sys/class/net/${VF1}" ]; do
  sleep 1
done

#
# Assign random but fixed MAC addresses.
#
if [ "${HOSTNAME}" = "cml1" ]; then
  ip link set dev "${VF1}" address de:35:ac:ad:e5:6e
  ip link set dev "${VF2}" address de:b7:1c:d1:f3:a2
  ip link set dev "${VF3}" address a2:47:31:43:36:4f
  ip link set dev "${VF4}" address 86:2f:ef:ea:98:87
else
  ip link set dev "${VF1}" address de:35:ac:ad:e5:6f
  ip link set dev "${VF2}" address de:b7:1c:d1:f3:a3
  ip link set dev "${VF3}" address a2:47:31:43:36:50
  ip link set dev "${VF4}" address 86:2f:ef:ea:98:88
fi

#
# Set VLANs.
#
ip link set "${PF1}" vf 0 vlan 100 qos 6
ip link set "${PF1}" vf 1 vlan 200 qos 5
ip link set "${PF1}" vf 2 vlan 300 qos 4
ip link set "${PF1}" vf 3 vlan 400 qos 3

#
# Setup interfaces.
#
ip link set dev "${VF1}" up
ip link set dev "${VF2}" up
ip link set dev "${VF3}" up
ip link set dev "${VF4}" up

#
# Prioritize NAPI and IRQ threads.
#
setup_threaded_napi "${PF1}"
setup_threaded_napi "${VF1}"
setup_threaded_napi "${VF2}"
setup_threaded_napi "${VF3}"
setup_threaded_napi "${VF4}"

setup_irqs "${PF1}"
setup_irqs "${VF1}"
setup_irqs "${VF2}"
setup_irqs "${VF3}"
setup_irqs "${VF4}"

exit 0
