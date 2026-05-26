# -*- mode: shell-script; sh-shell: bash -*-
#
# Copyright (C) 2020-2025 Linutronix GmbH
# Author Kurt Kanzenbach <kurt@linutronix.de>
#
# SPDX-License-Identifier: BSD-2-Clause
#
# Test setup library.
#

#
# stmmac_start($interface)
#
stmmac_start() {
  local interface=$1

  #
  # Disable VLAN Rx offload for eBPF XDP programs.
  #
  ethtool -K "${interface}" rx-vlan-offload off || true
}

#
# stmmac_end($interface)
#
stmmac_end() {
  local interface=$1
}

#
# stmmac_rx_queues_assign($interface, @rx_queues)
#
# Rx queues assignment based on PCP values and EtherType.
#
stmmac_rx_queues_assign() {
  local interface=$1
  local -n rx_queues=$2
  local len

  len=${#rx_queues[@]}

  if [ "$len" -ne 10 ]; then
    echo "stmmac_rx_queues_assign: rx_queues array len has to be 10!"
    return
  fi

  #
  # Steering based on PCP value.
  #
  tc qdisc add dev "${interface}" ingress
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 7 hw_tc "${rx_queues[0]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 6 hw_tc "${rx_queues[1]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 5 hw_tc "${rx_queues[2]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 4 hw_tc "${rx_queues[3]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 3 hw_tc "${rx_queues[4]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 2 hw_tc "${rx_queues[5]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 1 hw_tc "${rx_queues[6]}"
  tc filter add dev "${interface}" parent ffff: protocol 802.1Q flower vlan_prio 0 hw_tc "${rx_queues[7]}"

  #
  # PTP and LLDP are transmitted untagged. Steer them via EtherType.
  #
  tc filter add dev "${interface}" parent ffff: protocol 0x88f7 flower hw_tc "${rx_queues[8]}"
  tc filter add dev "${interface}" parent ffff: protocol 0x88cc flower hw_tc "${rx_queues[9]}"
}
