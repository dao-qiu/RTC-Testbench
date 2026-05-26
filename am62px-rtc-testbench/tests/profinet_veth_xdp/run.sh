#!/bin/bash
#
# Copyright (C) 2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Spawn a real time container with Testbench in it.
#

docker run --cap-add SYS_NICE \
  --cap-add CAP_IPC_LOCK \
  --cap-add SYS_RAWIO \
  --cap-add CAP_NET_RAW \
  --cap-add CAP_NET_ADMIN \
  --cap-add CAP_SYS_ADMIN \
  --device /dev/cpu_dma_latency \
  -it testbench bash
