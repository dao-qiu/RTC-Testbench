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

# Start four instances of reference application
../../build/reference -c reference_vid100.yaml >ref1.log &
../../build/reference -c reference_vid200.yaml >ref2.log &
../../build/reference -c reference_vid300.yaml >ref3.log &
../../build/reference -c reference_vid400.yaml >ref4.log &

exit 0
