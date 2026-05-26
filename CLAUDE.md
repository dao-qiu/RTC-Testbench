# CLAUDE.md - Project Instructions for Claude Code

## Project Overview
Understand how to use RTC-Testbench to Real-Time Ethernet behavior

## Current Work / Active Investigation
There are several different projects that I will reference as the below when I want to load the particular project's context
1. Basic-RTC-test.md

Below are common notes between the projects
1. We are using TI CPSW3G Ethernet ports on AM625 SoC (sometimes AM62Px if specified by the user)
2. Cannot use perf tool, not available in filesystem as a utility tool
3. CPSW ethtool does not have any xdp statistics so ethtool cannot be used to check xdp statistics

## Known conditions
1. xdp-dump is not available in filesystem
2. xdpsock is available in filesystem 
3. xdpsock --stats is not an option, closest is --extra-stats and --app-stats
4. /proc/net/xdp is not available
5. bpftrace is not available in filesystem
6. Even though both CPSW Ethernet ports share a single RX queue by default, we have enabled two RX queues using the configure-rx-flows.sh script 
7. eth1 is the XDP zero copy port and correctly connected to physical port2 already
8. Flow / Queue 0 acts as a catch-all flow. eth1 RX traffic to be steered to flow 0, eth0 RX traffic to be steered to flow 1, remaining broadcast and multicast traffic will be sent to flow 0 regardless of which port it was received from. This describes what happens in current setup but not necessarily what should happen
9. bpftool does exist: bpftool --version, bpftool v7.5.0, using libbpf v1.5, features: libbfd
10. Setup is using RT-Linux (PREEMPT_RT)
11. cpufreq is not an available framework when RT-Linux (PREEMPT_RT) is used. Thus changing scaling governor to "performance" is not possible
12. /home/a0500327/arm-toolchain//arm-gnu-toolchain-11.3.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu- is used for CROSS_COMPILE parameter for building any applications with cross compile

## Logs to reference
(to be added later)
