// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)
/*
 * Copyright (C) 2021,2022 Linutronix GmbH
 * Author Kurt Kanzenbach <kurt@linutronix.de>
 */

#include <linux/bpf.h>
#include <linux/types.h>

#include <bpf/bpf_endian.h>
#include <bpf/bpf_helpers.h>

#include <xdp/xdp_helpers.h>

#include "net_def.h"
#include "xdp_metadata.c"

struct {
	__uint(type, BPF_MAP_TYPE_XSKMAP);
	__uint(key_size, sizeof(int));
	__uint(value_size, sizeof(int));
	__uint(max_entries, 128);
} xsks_map SEC(".maps");

struct {
	__uint(priority, 10);
	__uint(XDP_PASS, 1);
} XDP_RUN_CONFIG(xdp_sock_prog);

SEC("xdp_sock")
int xdp_sock_prog(struct xdp_md *ctx)
{
	void *data_end = (void *)(long)ctx->data_end;
	void *data = (void *)(long)ctx->data;
	struct vlan_ethernet_header *veth;
	int idx = ctx->rx_queue_index;
	struct profinet_rt_header *rt;
	__be16 frame_id;
	void *p = data;

	bpf_printk("xdp_kern_profinet_vid100: Processing packet\n");

	veth = p;
	if ((void *)(veth + 1) > data_end){
		bpf_printk("Packet too short for Ethernet header, passing to kernel stack\n");
		return XDP_PASS;
	}
	p += sizeof(*veth);

	/* Check for VLAN frames */
	if (veth->vlan_proto != bpf_htons(ETH_P_8021Q)){
		 /* If not VLAN frame, pass to kernel stack */
		 bpf_printk("Not a VLAN frame, passing to kernel stack\n");
		 return XDP_PASS;
	}
	/* Check for valid Profinet frames */
	if (veth->vlan_encapsulated_proto != bpf_htons(ETH_P_PROFINET_RT)){
		 /* If not Profinet frame, pass to kernel stack */
		 bpf_printk("Not a Profinet frame, passing to kernel stack\n");
		 return XDP_PASS;
	}

	/* Check for VID 100 */
	// if ((bpf_ntohs(veth->vlantci) & VLAN_ID_MASK) != 100){
	// 	 /* If not VID 100, pass to kernel stack */
	// 	 //WARNING: adding bpf_printk will cause bpf program to fail to load
	// 	//  bpf_printk("Not a VID 100 frame, passing to kernel stack\n");
	// 	 return XDP_PASS;
	// }

	/* Check frameId range */
	rt = p;
	if ((void *)(rt + 1) > data_end) {
		 //WARNING: adding bpf_printk will cause bpf program to fail to load
		// bpf_printk("Packet too short for Profinet RT header, passing to kernel stack\n");
		 return XDP_PASS;
	}
	p += sizeof(*rt);

	frame_id = bpf_htons(rt->frame_id);
	switch (frame_id) {
	case TSN_HIGH_FRAMEID:
	case TSN_HIGH_SEC_FRAMEID:
	case TSN_LOW_FRAMEID:
	case TSN_LOW_SEC_FRAMEID:
	case RTC_FRAMEID:
	case RTC_SEC_FRAMEID:
	case RTA_FRAMEID:
	case RTA_SEC_FRAMEID:
		 /* If frameId matches expected values, redirect to user space */
		 bpf_printk("Frame ID matches expected values, redirecting to user space\n");
		goto redirect;
	default:
		 /* If frameId does not match expected values, pass to kernel stack */
		 bpf_printk("Frame ID does not match expected values, passing to kernel stack\n");
		return XDP_PASS;
	}

redirect:
	/* If socket bound to rx_queue then redirect to user space */
	if (bpf_map_lookup_elem(&xsks_map, &idx)) {
		bpf_printk("Redirecting frame with ID to user space on queue\n");
		populate_rx_timestamp(ctx);
		return bpf_redirect_map(&xsks_map, idx, 0);
	}

	bpf_printk("No socket bound to queue, passing to kernel stack\n");
	return XDP_PASS;
}

char _license[] SEC("license") = "Dual BSD/GPL";
