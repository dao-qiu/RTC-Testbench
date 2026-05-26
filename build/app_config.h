/* SPDX-License-Identifier: BSD-2-Clause */
/*
 * Copyright (C) 2020-2025 Linutronix GmbH
 * Author Kurt Kanzenbach <kurt@linutronix.de>
 */

#ifndef _APP_CONFIG_H_
#define _APP_CONFIG_H_

#define VERSION "5.4"
#define INSTALL_EBPF_DIR "/usr/local/lib/rtc-testbench/ebpf"

/* #undef WITH_MQTT */
#define HAVE_SO_BUSY_POLL 1
#define HAVE_SO_PREFER_BUSY_POLL 1
#define HAVE_SO_BUSY_POLL_BUDGET 1
/* #undef HAVE_XDP_TX_TIME */
#define RX_TIMESTAMP ON
/* #undef TX_TIMESTAMP */

#endif	/* _APP_CONFIG_H_ */
