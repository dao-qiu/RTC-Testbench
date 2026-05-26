#!/bin/bash
#
# Copyright (C) 2021-2024 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Rx and Tx traffic flows on Intel i226.
#
# Rx steering is based on PCP values. Tx steering is based on socket priorities
# which are mapped to traffic classes and to timeslots accordingly.
#

set -e

source ../../../lib/common.sh
source ../../../lib/igc.sh

#
# Command line arguments.
#
INTERFACE=$1
CYCLETIME_NS=$2
BASETIME=$3

[ -z $INTERFACE ] && INTERFACE="enp3s0"                          # default: enp3s0
[ -z $CYCLETIME_NS ] && CYCLETIME_NS="1000000"                   # default: 1ms
[ -z $BASETIME ] && BASETIME=$(date '+%s000000000' -d '-30 sec') # default: now + 60s

load_kernel_modules

setup_threaded_napi "${INTERFACE}"

igc_start "${INTERFACE}"

#
# Qbv configuration.
#
ENTRY1_NS=$(echo "$CYCLETIME_NS * 50 / 100" | bc) # TSN High / OPC/UA / AVTP
ENTRY2_NS=$(echo "$CYCLETIME_NS * 50 / 100" | bc) # Everything else

#
# Tx Assignment with Qbv and full hardware offload.
#
# PCP 6/5/4/3 - Queue 0 - Real time
# PCP 7/2/1/0 - Queue 1 - Non-real time
#
tc qdisc replace dev ${INTERFACE} handle 100 parent root taprio num_tc 4 \
  map 3 3 3 3 3 2 1 0 3 3 3 3 3 3 3 3 \
  queues 1@0 1@1 1@2 1@3 \
  base-time ${BASETIME} \
  sched-entry S 0x01 ${ENTRY1_NS} \
  sched-entry S 0xfe ${ENTRY2_NS} \
  flags 0x02

#
# Enable Tx launch time support for TC 0.
#
tc qdisc replace dev ${INTERFACE} parent 100:1 etf \
  clockid CLOCK_TAI \
  delta 500000 \
  offload

#
# Rx Queues Assignment.
#
# Rx Q 3 - AVTP / All other traffic
# Rx Q 2 - OPC/UA #2
# Rx Q 1 - OPC/UA #1
# Rx Q 0 - TSN High
#
RXQUEUES=(3 0 1 2 3 3 3 3 3 3)
igc_rx_queues_assign "${INTERFACE}" RXQUEUES

igc_end "${INTERFACE}"

setup_irqs "${INTERFACE}"

exit 0
