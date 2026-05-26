#!/bin/bash
#
# Copyright (C) 2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Create virtual network interfaces move them into containers and bridge them together.
#

set -e

#
# Network for containers
#
ip link add veth0 type veth peer name veth0tb
ip link add veth1 type veth peer name veth1tb

#
# Setup MAC addresses.
#
HOSTNAME=$(hostname)
if [ "${HOSTNAME}" = "bpc1" ]; then
  ifconfig veth0tb hw ether 5e:a7:0c:3f:e4:a9
  ifconfig veth1tb hw ether d2:4c:c5:e2:f7:b7
else
  ifconfig veth0tb hw ether 5e:a7:0c:3f:e4:aa
  ifconfig veth1tb hw ether d2:4c:c5:e2:f7:b8
fi

#
# Setup veth up
#
ip link set veth0 up
ip link set veth1 up

#
# Disable VLAN Rx offload.
#
ethtool -K veth0 rx-vlan-offload off
ethtool -K veth1 rx-vlan-offload off
ethtool -K veth0tb rx-vlan-offload off
ethtool -K veth1tb rx-vlan-offload off
ethtool -K veth0 tx-vlan-offload off
ethtool -K veth1 tx-vlan-offload off
ethtool -K veth0tb tx-vlan-offload off
ethtool -K veth1tb tx-vlan-offload off

#
# Move vethXtb to container network namespaces
#
NETNS1=$(lsns -t net | tail -n1 | awk '{ print $4 }')
NETNS2=$(lsns -t net | tail -n2 | head -n 1 | awk '{ print $4 }')
ip link set veth0tb netns ${NETNS1}
ip link set veth1tb netns ${NETNS2}

#
# Bridge together: virtual and physical NICs
#
ip link add br0 type bridge
ip link set veth0 master br0
ip link set veth1 master br0
ip link set enp3s0 master br0
ip link set br0 up

#
# Ignore iptable rules setup by docker
#
sysctl net.bridge.bridge-nf-call-iptables=0

#
# Configure VLANs on br0
#
ifconfig enp3s0.100 down
ip link delete enp3s0.100
ip link set dev br0 type bridge vlan_filtering 1
bridge vlan add dev enp3s0 vid 100
bridge vlan add dev veth0 vid 100
bridge vlan add dev veth1 vid 100
bridge vlan add dev enp3s0 vid 200
bridge vlan add dev veth0 vid 200
bridge vlan add dev veth1 vid 200

#
# Setup MAC addresses.
#
if [ "${HOSTNAME}" = "bpc1" ]; then
  ifconfig br0 hw ether d6:96:12:ef:d6:77
else
  ifconfig br0 hw ether d6:96:12:ef:d6:78
fi

#
# Disable VLAN Rx offload.
#
ethtool -K br0 rx-vlan-offload off
ethtool -K br0 tx-vlan-offload off

#
# Setup XDP on physical NIC.
#
cp ../../build/xdp_kern_*.o .
xdp-loader load --prog-name xdp_sock_prog enp3s0 xdp_kern_profinet_veth_dispatch.o
IFINDEX_VETH0=$(cat /sys/class/net/veth0/ifindex)
IFINDEX_VETH1=$(cat /sys/class/net/veth1/ifindex)
bpftool map update name veth_map key 0 0 0 0 value ${IFINDEX_VETH0} 0 0 0
bpftool map update name veth_map key 1 0 0 0 value ${IFINDEX_VETH1} 0 0 0
