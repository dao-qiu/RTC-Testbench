#!/bin/bash
#
# Copyright (C) 2023 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Tx and Rx traffic flows for Intel i225 for Embedded World 2023.
#

set -e

source ../lib/common.sh
source ../lib/igc.sh

#
# Command line arguments.
#
INTERFACE=$1
CYCLETIME_NS=$2
BASETIME=$3

[ -z $INTERFACE ] && INTERFACE="enp88s0"                         # default: enp88s0
[ -z $CYCLETIME_NS ] && CYCLETIME_NS="1000000"                   # default: 1ms
[ -z $BASETIME ] && BASETIME=$(date '+%s000000000' -d '-30 sec') # default: now - 30s

load_kernel_modules

setup_threaded_napi "${INTERFACE}"

igc_start "${INTERFACE}"

#
# Split traffic between TSN streams, priority and everything else.
#
ENTRY1_NS=$(echo "$CYCLETIME_NS * 30 / 100" | bc) # TSN Streams
ENTRY2_NS=$(echo "$CYCLETIME_NS * 35 / 100" | bc) # Prio
ENTRY3_NS=$(echo "$CYCLETIME_NS * 35 / 100" | bc) # Everything else

#
# Tx Assignment with Qbv and full hardware offload.
#
# PCP 6 - Queue 0 - TSN Streams
# PCP 5 - Queue 1 - Prio
# PCP X - Queue 2 - Everything else
#
tc qdisc replace dev ${INTERFACE} handle 100 parent root taprio num_tc 3 \
  map 2 2 2 2 2 2 1 0 2 2 2 2 2 2 2 2 \
  queues 1@0 1@1 2@2 \
  base-time ${BASETIME} \
  sched-entry S 0x01 ${ENTRY1_NS} \
  sched-entry S 0x02 ${ENTRY2_NS} \
  sched-entry S 0x04 ${ENTRY3_NS} \
  flags 0x02

#
# Enable Tx launch time support for TSN Streams.
#
tc qdisc replace dev ${INTERFACE} parent 100:1 etf \
  clockid CLOCK_TAI \
  delta 500000 \
  offload

#
# Rx Queues Assignment.
#
# PCP 6 - Rx Q 0 - TSN Streams
# PCP 5 - Rx Q 1 - Prio
# PCP X - Rx Q 2 - Everything else
#
RXQUEUES=(2 0 1 2 2 2 2 2 1 1)
igc_rx_queues_assign "${INTERFACE}" RXQUEUES

igc_end "${INTERFACE}"

setup_irqs "${INTERFACE}"

exit 0
