#!/bin/bash
#
# Copyright (C) 2023-2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#

set -e

cd "$(dirname "$0")"

# Configure flow
./flow.sh
sleep 30

# Start PTP
../../scripts/ptp.sh enp1s0f0np0
sleep 30

# Start four instances of mirror application
../../build/mirror -c mirror_vid100.yaml >mirror1.log &
../../build/mirror -c mirror_vid200.yaml >mirror2.log &
../../build/mirror -c mirror_vid300.yaml >mirror3.log &
../../build/mirror -c mirror_vid400.yaml >mirror4.log &

exit 0
