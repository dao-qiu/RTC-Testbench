#!/bin/bash
#
# Copyright (C) 2023-2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Setup the Tx and Rx traffic flows for Intel i225/i226 for Embedded World 2025.
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
# Split traffic between TSN streams, real time cyclic and everything else.
#
ENTRY1_NS=$(echo "$CYCLETIME_NS * 12.5 / 100" | bc) # TSN High
ENTRY2_NS=$(echo "$CYCLETIME_NS * 12.5 / 100" | bc) # TSN Low
ENTRY3_NS=$(echo "$CYCLETIME_NS * 25 / 100" | bc)   # RTC
ENTRY4_NS=$(echo "$CYCLETIME_NS * 50 / 100" | bc)   # Everything else

#
# Tx Assignment with Qbv and full hardware offload.
#
# PCP 7 - Queue 0 - TSN High
# PCP 6 - Queue 1 - TSN Low
# PCP 5 - Queue 2 - RTC
# PCP X - Queue 3 - Everything else
#
tc qdisc replace dev ${INTERFACE} handle 100 parent root taprio num_tc 4 \
  map 3 3 3 3 3 2 1 0 3 3 3 3 3 3 3 3 \
  queues 1@0 1@1 1@2 1@3 \
  base-time ${BASETIME} \
  sched-entry S 0x01 ${ENTRY1_NS} \
  sched-entry S 0x02 ${ENTRY2_NS} \
  sched-entry S 0x04 ${ENTRY3_NS} \
  sched-entry S 0xf8 ${ENTRY4_NS} \
  flags 0x02

#
# Rx Queues Assignment.
#
# PCP 7 - Rx Q 0 - TSN High
# PCP 6 - Rx Q 1 - TSN Low
# PCP 5 - Rx Q 2 - RTC
# PCP X - Rx Q 3 - Everything else
#
RXQUEUES=(0 1 2 3 3 3 3 3 3 3)
igc_rx_queues_assign "${INTERFACE}" RXQUEUES

igc_end "${INTERFACE}"

setup_irqs "${INTERFACE}"

exit 0
