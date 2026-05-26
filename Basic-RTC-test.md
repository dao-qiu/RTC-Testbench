# Basic-RTC-test.md - Project Instructions for Evaluating Basic RTC-Testbench in Linux

## Project Overview
Set up a tutorial on how to use RTC-Testbench to measure real-time Ethernet behavior

## Hardware Platform
- **SoC:** AM62Px
- **CPU Cores:** 4x A53 (ARMv8)
- **Memory:** 32-bit DDR
- **Ethernet:** 2x CPSW3G ports

## Reference Drivers
- **CPSW Driver:** /home/a0500327/ti-processor-sdk-linux-rt-am62xx-evm-11.02.08.02/board-support/ti-linux-kernel-6.12.57+git-ti-rt/drivers/net/ethernet/ti/am65-cpsw-nuss.c

## Current Work / Active Investigation
1. Please give quick summary of how RTC-Testbench program can be used to measure real-time Ethernet behavior
2. Please give step-by-step setup guide on how to test RTC-Testbench on the Hardware Platform described in this Basic-RTC-test.md
3. Please give overview of each top level entry of the yaml files in /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests
4. Provided that I'm connecting AM62Px to a Linux host PC and my goal is to measure cycletime, end-to-end latency, jitter, and packet loss on AM62Px, please let me know whether AM62Px should be running reference binary or the mirror binary from RTC-Testbench
5. Given results of #3, and that I have eth1 port connected on the AM62Px with 172.168.1.22 and the host PC port is 172.168.1.1, and I want a minimal test to measure basic ethernet packet cycletime, end-to-end latency, jitter, and packet loss on AM62Px, check if there is anything to be changed in the mirror.yaml and reference.yaml provided in /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests
6. Create a copy of the yamls in /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests in another directory and modify so that I can test out XDP zero copy performance of AM62Px. Please let me know what XDP program files needed.
7. Should I be using a host PC as the link partner if I want a true reflection of the AM62Px performance? Concerns about potentially host PC not fully real-time such that any bottleneck in performance might be due to the host PC
8. How to plot results of RTC-testbench statistics on a histogram. Goal is to provide spectrum of latencies to jitter of Ethernet round trip time.
9. TODO: Test AM62x <--> AM62Px (instead of host PC <--> AM62Px) to prevent bottlenecks due to link partner

## Task 1: RTC-Testbench Overview

RTC-Testbench is a software tool for measuring **real-time Ethernet communication behavior** — specifically latency, jitter, and cycle time accuracy in deterministic network applications.

### What It Measures
| Metric | Description |
|---|---|
| **Cycle Time** | How consistently packets are sent/received at a fixed interval |
| **End-to-End Latency** | Time from packet transmission to reception |
| **Jitter** | Variation in latency across cycles |
| **Packet Loss** | Missed or late frames |

### How It Works

1. **Sender** generates Ethernet frames at a fixed cycle rate (e.g., 1ms), embedding a precise timestamp
2. **Receiver** captures incoming frames and compares the embedded timestamp against its own clock
3. **Statistics** are computed over many cycles to produce min/max/avg/histogram distributions

### Key Design Choices Relevant to This Setup

- **AF_XDP (XDP zero-copy):** Uses kernel-bypass socket interface for low-latency packet I/O — directly relevant since `eth1` is the XDP zero-copy port
- **RT-Linux (PREEMPT_RT):** Reduces scheduling jitter by making the kernel fully preemptible — already in use on this platform
- **Raw Layer 2 Ethernet:** Bypasses TCP/IP stack overhead for deterministic timing
- **CPU Affinity + IRQ Pinning:** Binds RTC tasks and NIC interrupts to dedicated cores to avoid interference

### Typical Test Flow

```
[Sender Node] ──Ethernet──> [AM62Px (eth1, XDP)] ──> [RTC-Testbench Receiver]
                                     |
                               Timestamps frames,
                               logs latency/jitter,
                               reports cycle statistics
```

## Task 2: Step-by-Step Setup Guide

### Prerequisites & Hardware Topology

```
[Remote Node (PC/Linux)]              [AM62Px Target]
        eth0 ──────────────────────────── eth1 (XDP zero-copy, port2)
```
A direct back-to-back Ethernet cable between the remote node and AM62Px `eth1`.

---

### Step 1: Verify RT Kernel on AM62Px

```bash
uname -a
# Should show: PREEMPT_RT in kernel string
```

---

### Step 2: Build / Install RTC-Testbench

RTC-Testbench uses **CMake** as its build system. The two main binaries produced are `reference` (sender/receiver) and `mirror` (reflector).

#### a) Install build dependencies (Debian/Ubuntu host)

> Note: `libxdp-dev` and a sufficiently new `libbpf-dev` are not available in standard repos
> for many Ubuntu/Debian versions. Install base deps first, then build both from source.

```bash
sudo apt install -y build-essential clang llvm cmake pkg-config \
  libyaml-dev libc6-dev rt-tests ethtool iproute2 \
  iperf3 linuxptp libssl-dev git bc
```

Then build and install `libbpf` from source (apt version may be too old; >= 1.2 required for `RX_TIMESTAMP`):

```bash
git clone https://github.com/libbpf/libbpf.git
cd libbpf/src
make
sudo make install
sudo ldconfig
cd ../..
```

After installing, `libbpf.pc` is placed in `/usr/lib64/pkgconfig/` which is not in the default
pkg-config search path. Add it manually:

```bash
export PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH
echo 'export PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH' >> ~/.bashrc
source ~/.bashrc
```

Verify `libbpf` version:
```bash
pkg-config --modversion libbpf
# Should report >= 1.2
```

Then build and install `libxdp` from source:

```bash
git clone https://github.com/xdp-project/xdp-tools.git
cd xdp-tools
git submodule update --init
./configure
make -j$(nproc)
sudo make install
sudo ldconfig
cd ..
```

> **Troubleshooting:** If the build fails with `fatal error: pcap/dlt.h: No such file or directory` in `xdpdump.c`, this is caused by a missing `libpcap` header required by the `xdpdump` tool.
>
> **Option 1** — Install libpcap and rebuild:
> ```bash
> sudo apt install libpcap-dev
> make -j$(nproc)
> sudo make install
> ```
>
> **Option 2** — Build only libxdp (recommended, since `xdp-dump` is not available in this setup):
> ```bash
> make -C lib/libxdp -j$(nproc)
> sudo make -C lib/libxdp install
> sudo ldconfig
> ```

Verify `libxdp` is found:
```bash
pkg-config --modversion libxdp
```

Verify static libraries (`.a` files) are present for both:
```bash
find /usr/lib* /usr/local/lib* -name "libbpf.a" -o -name "libxdp.a" 2>/dev/null
# Both libbpf.a and libxdp.a should be listed
```

#### b) Build natively on target (or on host for same arch)

Clone RTC-Testbench:
```bash
git clone https://github.com/Linutronix/RTC-Testbench.git
```

> Note: `BPF_F_XDP_DEV_BOUND_ONLY` is required and was introduced in Linux kernel 5.19.
> The host kernel headers must be >= 5.19, otherwise the build will fail with an undeclared identifier error.

Check host kernel version and whether the flag is present:
```bash
uname -r
grep "BPF_F_XDP_DEV_BOUND_ONLY" /usr/include/linux/bpf.h
```

If missing, install HWE kernel headers (Ubuntu 22.04):
```bash
sudo apt install linux-headers-generic-hwe-22.04 linux-libc-dev
reboot
```

After reboot, verify:
```bash
uname -r
# Should show 6.x kernel
grep "BPF_F_XDP_DEV_BOUND_ONLY" /usr/include/linux/bpf.h
# Should now find the definition
```

**Alternative (no reboot)** — pass the definition directly via CFLAGS:
```bash
cmake -DCMAKE_BUILD_TYPE=Release -DRX_TIMESTAMP=ON \
      -DCMAKE_C_FLAGS="-DBPF_F_XDP_DEV_BOUND_ONLY=0x40" \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" ..
PKG_CONFIG="pkg-config --static" make -j$(nproc)
```

Otherwise build with static libraries:
```bash
cd RTC-Testbench
mkdir build && cd build
PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      ..
make -j$(nproc)
```

Verify key libraries are statically linked:
```bash
ldd ../build/reference | grep -E "xdp|bpf|yaml|ssl"
# Expected: no output (empty) — statically linked libs are baked into the binary and won't appear
# If a lib is still dynamic, it will show as: libxdp.so.1 => /usr/lib/libxdp.so.1 (0x0000...)
```

If libs still appear dynamically linked, a stale CMake cache from a previous run may be interfering. Clean the build directory first, then use full paths to the static libraries:
```bash
cd ~/RTC-Testbench
rm -rf build && mkdir build && cd build

PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      -DCMAKE_EXE_LINKER_FLAGS="/usr/lib/aarch64-linux-gnu/libxdp.a /usr/lib/aarch64-linux-gnu/libbpf.a /usr/lib/aarch64-linux-gnu/libyaml.a -Wl,-Bdynamic" \
      ..
make -j$(nproc)

PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      -DCMAKE_C_FLAGS="-DBPF_F_XDP_DEV_BOUND_ONLY=0x40" \ 
      ..
make -j$(nproc)
```

If still dynamic after a clean build, check the actual linker command CMake generates:
```bash
make clean
make VERBOSE=1 2>&1 > /tmp/build.log
grep -i "reference" /tmp/build.log | tail -5
```
> If the output shows `-lxdp -lbpf -lyaml` appearing **after** the full `.a` paths, CMake is adding dynamic `-l` flags that override the static ones.

The root cause is that CMake appends `-lyaml -lbpf -lxdp` at the end of the link command (after object files), while `CMAKE_EXE_LINKER_FLAGS` entries appear before object files. The fix is to create a `static-only-libs` directory containing only `.a` files with no `.so` files, so the linker finds only static archives when resolving the trailing `-l` flags:

```bash
mkdir -p ~/static-only-libs
cp /usr/lib/aarch64-linux-gnu/libxdp.a ~/static-only-libs/
cp /usr/lib/aarch64-linux-gnu/libyaml.a ~/static-only-libs/
```

`libbpf.a` has transitive dependencies on `libz`, `libelf`, and `libzstd` which must also be merged into it. First check that `libzstd.a` is available:

```bash
find /usr/lib* /lib* -name "libzstd.a" 2>/dev/null
```

If not found, install it:
```bash
apt install libzstd-dev
```

Then merge all into a single self-contained archive.

> **Important:** Do NOT use `find` to locate `libelf.a` — Debian's system `libelf.a` at
> `/usr/lib/aarch64-linux-gnu/libelf.a` references internal elfutils symbols (`eu_search_tree_init`,
> `eu_search_tree_fini`) that are NOT defined in that static library (only available in the shared `.so`).
> You must build elfutils from source to get a self-contained static `libelf.a`.

**Step i — Build elfutils from source:**
```bash
apt install -y autoconf automake gettext libarchive-dev \
  libmicrohttpd-dev libsqlite3-dev libbz2-dev liblzma-dev

wget https://sourceware.org/elfutils/ftp/elfutils-latest.tar.bz2
tar xf elfutils-latest.tar.bz2
cd elfutils-*/

./configure --disable-shared --enable-static \
            --prefix=/tmp/elfutils-install \
            --disable-debuginfod --disable-libdebuginfod
make -j$(nproc)
make install
cd ..
```

Verify `eu_search_tree_init` is now defined (T):
```bash
nm /tmp/elfutils-install/lib/libelf.a | grep eu_search_tree
# Should show T (defined), not U (undefined)
```

**Step ii — Merge into self-contained libbpf.a using explicit paths:**
```bash
rm -rf /tmp/bpf_merge && mkdir /tmp/bpf_merge
cd /tmp/bpf_merge
mkdir bpf z elf zstd

cd bpf  && ar x /usr/lib/aarch64-linux-gnu/libbpf.a  && cd ..
cd z    && ar x /usr/lib/aarch64-linux-gnu/libz.a     && cd ..
cd elf  && ar x /tmp/elfutils-install/lib/libelf.a    && cd ..
cd zstd && ar x /usr/lib/aarch64-linux-gnu/libzstd.a  && cd ..

ar rcs ~/static-only-libs/libbpf.a bpf/*.o z/*.o elf/*.o zstd/*.o
cd ~ && rm -rf /tmp/bpf_merge
```

Verify `eu_search_tree` symbols are now resolved in merged archive:
```bash
nm ~/static-only-libs/libbpf.a 2>/dev/null | grep eu_search_tree
# Should show T (defined)
```

Then rebuild using `--start-group`/`--end-group` to resolve circular dependency between `libxdp.a` and `libbpf.a`:
```bash
cd ~/RTC-Testbench
rm -rf build && mkdir build && cd build

cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_EXE_LINKER_FLAGS="-L$HOME/static-only-libs -Wl,--start-group -lxdp -lbpf -lyaml -Wl,--end-group" \
      ..
make -j$(nproc)
```

#### c) Build mirror binary on host PC (x86)

Building the host PC mirror follows the same dependency chain as the native build, but has additional pitfalls specific to x86 Ubuntu that must be resolved in order.

##### c.1) Register /usr/lib64 in ldconfig

After building libbpf from source (Step 2a), `libbpf.so.1` is installed to `/usr/lib64/` which is not in Ubuntu's default library search path. Register it permanently before building anything else, otherwise xdp-tools will link against the old system `libbpf.so.0` instead:

```bash
echo "/usr/lib64" | sudo tee /etc/ld.so.conf.d/libbpf.conf
sudo ldconfig
ldconfig -p | grep libbpf   # verify libbpf.so.1 is listed
```

##### c.2) Rebuild xdp-tools against libbpf.so.1

If xdp-tools was built before Step c.1 above, it will have linked against the old system `libbpf.so.0`. This causes a version mismatch when loading BPF programs at runtime — the `.xdp_run_config` section in the compiled XDP program requires a newer libbpf and will fail with:

```
libbpf: elf: skipping unrecognized data section(8) .xdp_run_config
libbpf: error: program handler doesn't match object
libxdp: Couldn't find xdp program in bpf object section xdp_sock
```

Verify which libbpf libxdp links against:
```bash
ldd /usr/local/lib/libxdp.so.1 | grep bpf
# Bad:  libbpf.so.0 => /lib/x86_64-linux-gnu/libbpf.so.0
# Good: libbpf.so.1 => /usr/lib64/libbpf.so.1
```

If showing `libbpf.so.0`, rebuild xdp-tools. `PKG_CONFIG_PATH` alone is not sufficient — `LIBRARY_PATH` must also be set so the linker finds `libbpf.so.1` in `/usr/lib64` before the system `libbpf.so.0` in `/lib/x86_64-linux-gnu`:

```bash
cd xdp-tools
make clean
PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH \
LIBRARY_PATH=/usr/lib64:$LIBRARY_PATH \
make -j$(nproc)
sudo make install
sudo ldconfig

# Verify libxdp now uses libbpf.so.1
ldd /usr/local/lib/libxdp.so.1 | grep bpf
```

##### c.3) Build RTC-Testbench for host PC

The host PC kernel headers may be missing `BPF_F_XDP_DEV_BOUND_ONLY` (introduced in kernel 5.19). Pass it via CFLAGS to avoid a build failure:

```bash
cd RTC-Testbench
rm -rf build && mkdir build && cd build

PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH \
PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      -DCMAKE_C_FLAGS="-DBPF_F_XDP_DEV_BOUND_ONLY=0x40" \
      ..

make -j$(nproc)
```

##### c.4) Verify binaries and XDP programs were produced

```bash
ls reference mirror xdp_kern_profinet_vid100.o
```

If `xdp_kern_profinet_vid100.o` is missing, `clang` was not installed when `make` ran. Install it and rebuild:
```bash
sudo apt install -y clang llvm
make -j$(nproc)
```

##### c.5) Verify runtime library linkage

```bash
ldd build/mirror | grep -E "xdp|bpf"
# Expected:
#   libxdp.so.1  => /usr/local/lib/libxdp.so.1
#   libbpf.so.1  => /usr/lib64/libbpf.so.1   (NOT libbpf.so.0)
```

---

#### d) Cross-compile for AM62Px (aarch64) from x86 host

Cross-compilation requires all dependencies (libyaml, libssl, libbpf, libxdp) to be built for
aarch64 using the same toolchain. Do **not** use Debian arm64 packages (`dpkg --add-architecture arm64`)
as they use `aarch64-linux-gnu` ABI which may not be compatible with the `aarch64-none-linux-gnu`
toolchain. Instead, build a local sysroot from source.

##### c.1) Define common variables
```bash
export TOOLCHAIN=/home/a0500327/arm-toolchain/arm-gnu-toolchain-11.3.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu
export SYSROOT=/home/a0500327/aarch64-sysroot
mkdir -p $SYSROOT
```

##### c.2) Build libyaml
```bash
git clone https://github.com/yaml/libyaml.git
cd libyaml
mkdir build && cd build
cmake -DCMAKE_C_COMPILER=${TOOLCHAIN}-gcc \
      -DCMAKE_INSTALL_PREFIX=$SYSROOT \
      ..
make -j$(nproc)
make install
cd ../..
```

##### c.3) Build OpenSSL >= 3.0
```bash
git clone --branch openssl-3.0 https://github.com/openssl/openssl.git
cd openssl
./Configure linux-aarch64 \
    --cross-compile-prefix=${TOOLCHAIN}- \
    --prefix=$SYSROOT \
    no-tests
make -j$(nproc)
make install
cd ..
```

##### c.4) Build libbpf
```bash
cd /home/a0500327/Documents/bpf-xdp-work/libbpf/src
make CC=${TOOLCHAIN}-gcc \
     DESTDIR=$SYSROOT \
     prefix=/usr \
     install
```

##### c.5) Build libxdp (xdp-tools)
```bash
export PKG_CONFIG_PATH=$SYSROOT/usr/lib/pkgconfig
export PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/pkgconfig

cd /home/a0500327/Documents/bpf-xdp-work/xdp-tools
make CC=${TOOLCHAIN}-gcc \
     CLANG=clang \
     ARCH=arm64 \
     PREFIX=$SYSROOT \
     DESTDIR=$SYSROOT \
     -j$(nproc)
make install
```

##### c.6) Cross-compile RTC-Testbench
```bash
cd RTC-Testbench
mkdir aarch64-build && cd aarch64-build

PKG_CONFIG_PATH=$SYSROOT/usr/lib/pkgconfig \
PKG_CONFIG_LIBDIR=$SYSROOT/usr/lib/pkgconfig \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_SYSTEM_NAME=Linux \
      -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
      -DCMAKE_C_COMPILER=${TOOLCHAIN}-gcc \
      -DCMAKE_SYSROOT=$SYSROOT \
      -DRX_TIMESTAMP=ON \
      ..
make -j$(nproc)
```

> `RX_TIMESTAMP=ON` is safe to enable: the target has libbpf v1.5 (confirmed via `bpftool --version`), which satisfies the >= 1.2 requirement.

#### e) Copy binaries and XDP programs to AM62Px target

```bash
# Copy binaries
scp build/reference build/mirror root@<target-ip>:/usr/local/bin/

# Create the eBPF install directory and copy the XDP kernel object file
ssh root@<target-ip> mkdir -p /usr/local/lib/rtc-testbench/ebpf
scp build/xdp_kern_opcua_vid200.o root@<target-ip>:/usr/local/lib/rtc-testbench/ebpf/
```

The `reference` binary loads the XDP program at runtime. It first looks for the file by the name given in `ApplicationXdpProgram`, and if not found falls back to `/usr/local/lib/rtc-testbench/ebpf/<name>`. The YAML configs in Step 6 use `xdp_kern_opcua_vid200.o`, so that file must be present on the target.

YAML config files are created manually on each node — see Step 6.

---

### Step 3: System Tuning on AM62Px

#### a) Isolate a CPU core for RTC tasks
Add to kernel boot args in `/boot/uEnv.txt` or device tree bootargs:
```
isolcpus=3 nohz_full=3 rcu_nocbs=3
```
> Reboot required after this change.

#### b) Set IRQ affinity for eth1
```bash
# Find IRQ number for eth1
cat /proc/interrupts | grep eth1

# Pin IRQ to isolated core (e.g., core 3)
echo 8 > /proc/irq/<IRQ_NUM>/smp_affinity   # bitmask: core 3 = 0x8
```

#### c) Set thread priority
```bash
# Run reference with real-time scheduling (SCHED_FIFO, priority 90)
# Do NOT use taskset here — per-thread CPU pinning is done via the YAML config
chrt -f 90 reference -c <config.yaml>
```

> Note: `cpufreq` scaling governor is not available on PREEMPT_RT — no action needed here.

---

### Step 4: Configure XDP on eth1

#### a) Ensure RX flows are configured
```bash
./configure-rx-flows.sh
# eth1 RX traffic → Flow 0 (already set per known conditions)
```

#### b) Enable promiscuous mode on eth1
```bash
ip link set eth1 promisc on
```

> **Required after every reboot.** Without this, the CPSW3G ALE discards frames with VID 100 before they reach the XDP hook, causing `reference Rx: 0`. See Known Issue: CPSW3G ALE discards VID 100 frames after reboot.

#### c) Verify XDP interface is ready
```bash
bpftool net show dev eth1
ip link show eth1
```

---

### Step 5: Assign Static IPs

On AM62Px:
```bash
ip addr add 192.168.1.2/24 dev eth1
ip link set eth1 up
```

On Remote Node:
```bash
ip addr add 192.168.1.1/24 dev eth0
ip link set eth0 up
```

---

### Step 6: Run RTC-Testbench

RTC-Testbench uses two binaries: `reference` (the measurement node) and `mirror` (the reflector). Each requires a YAML config file passed via `-c`. Existing examples are in the repo under `tests/<test-name>/`.

For a minimal non-PROFINET test, the **`GenericL2`** traffic class is used. It sends raw Layer 2 Ethernet frames with a custom EtherType — no PROFINET frame IDs, no protocol-specific framing. This is derived from `tests/opcua/` which is the simplest single-class non-PROFINET example in the repo.

> **Note:** RTC-Testbench always uses VLAN-tagged frames. The XDP program (`xdp_kern_opcua_vid200.o`) classifies frames matching EtherType `0xb62c` + VID 200 and redirects them to the XDP socket. Both nodes must use the same VID and EtherType.

#### Create `reference.yaml` on AM62Px

```yaml
---
Application:
  ApplicationClockId: CLOCK_TAI
  ApplicationBaseCycleTimeNS: 1ms
  ApplicationTxBaseOffsetNS: 800us
  ApplicationRxBaseOffsetNS: 300us
  ApplicationXdpProgram: xdp_kern_opcua_vid200.o
GenericL2:
  GenericL2Name: GenericL2
  GenericL2Enabled: true
  GenericL2XdpEnabled: true
  GenericL2XdpSkbMode: false
  GenericL2XdpZcMode: true        # XDP zero-copy — eth1 (CPSW3G) supports this
  GenericL2XdpWakeupMode: true
  GenericL2TxTimeEnabled: false
  GenericL2TxTimeOffsetNS: 0
  GenericL2TxTimeStampEnabled: false
  GenericL2Vid: 200
  GenericL2Pcp: 6
  GenericL2EtherType: 0xb62c
  GenericL2NumFramesPerCycle: 1
  GenericL2PayloadPattern: |
    GenericL2PayloadPattern
  GenericL2FrameLength: 128
  GenericL2RxQueue: 0             # eth1 RX traffic → Flow 0
  GenericL2TxQueue: 0
  GenericL2SocketPriority: 7
  GenericL2TxThreadPriority: 98
  GenericL2RxThreadPriority: 98
  GenericL2TxThreadCpu: 3         # isolated core
  GenericL2RxThreadCpu: 3         # isolated core
  GenericL2Interface: eth1
  GenericL2Destination: <remote-node-eth0-MAC>
Log:
  LogThreadPriority: 1
  LogThreadCpu: 0
  LogFile: /var/log/reference.log
  LogLevel: Info
Debug:
  DebugStopTraceOnOutlier: false
  DebugStopTraceOnError: false
  DebugMonitorMode: false
  DebugMonitorDestination: 44:44:44:44:44:44
```

#### Create `mirror.yaml` on Remote Node

```yaml
---
Application:
  ApplicationClockId: CLOCK_TAI
  ApplicationBaseCycleTimeNS: 1ms
  ApplicationTxBaseOffsetNS: 800us
  ApplicationRxBaseOffsetNS: 300us
  ApplicationXdpProgram: xdp_kern_opcua_vid200.o
GenericL2:
  GenericL2Name: GenericL2
  GenericL2Enabled: true
  GenericL2XdpEnabled: true
  GenericL2XdpSkbMode: true       # SKB mode — use if remote NIC does not support zero-copy
  GenericL2XdpZcMode: false
  GenericL2XdpWakeupMode: true
  GenericL2TxTimeEnabled: false
  GenericL2TxTimeOffsetNS: 0
  GenericL2TxTimeStampEnabled: false
  GenericL2Vid: 200
  GenericL2Pcp: 6
  GenericL2EtherType: 0xb62c
  GenericL2NumFramesPerCycle: 1
  GenericL2PayloadPattern: |
    GenericL2PayloadPattern
  GenericL2FrameLength: 128
  GenericL2RxQueue: 0
  GenericL2TxQueue: 0
  GenericL2SocketPriority: 7
  GenericL2TxThreadPriority: 98
  GenericL2RxThreadPriority: 98
  GenericL2TxThreadCpu: 0
  GenericL2RxThreadCpu: 0
  GenericL2Interface: eth0
  GenericL2Destination: <AM62Px-eth1-MAC>
Log:
  LogThreadPriority: 1
  LogThreadCpu: 1
  LogFile: /var/log/mirror.log
  LogLevel: Info
Debug:
  DebugStopTraceOnOutlier: false
  DebugStopTraceOnError: false
  DebugMonitorMode: false
  DebugMonitorDestination: 44:44:44:44:44:44
```

> The `mirror` node also needs `xdp_kern_opcua_vid200.o` at `/usr/local/lib/rtc-testbench/ebpf/`. Copy it the same way as Step 2d.

#### Run: start mirror first, then reference

On Remote Node:
```bash
chrt -f 90 mirror -c mirror.yaml
```

On AM62Px:
```bash
chrt -f 90 reference -c reference.yaml
```

> Do **not** use `taskset` here. `taskset -c 3` would restrict the entire process to CPU 3, but other threads (e.g., log thread on CPU 0) would then fail to be created with `EINVAL`. Per-thread CPU affinity is controlled by the YAML config (`RtcTxThreadCpu`, `RtcRxThreadCpu`, `LogThreadCpu`, etc.).

---

### Step 7: Monitor During Test

On AM62Px, in a separate terminal:

```bash
# XDP stats via xdpsock
xdpsock --extra-stats --app-stats

# BPF program verification
bpftool prog show
bpftool map show
```

---

### Step 8: Interpret Results

`results.csv` will contain per-cycle timestamps. Key metrics to review:

| Field | Good Value (1ms cycle) |
|---|---|
| Min latency | < 100 µs |
| Max latency | < 500 µs |
| Jitter (max-min) | < 200 µs |
| Packet loss | 0% |

Plot histogram from CSV:
```bash
# Quick latency histogram (if gnuplot available)
gnuplot -e "set terminal dumb; plot 'results.csv' using 1 with boxes"
```

---

## Task 3: YAML Top-Level Entry Overview

Both `reference.yaml` and `mirror.yaml` share the same top-level structure:

| Section | Purpose |
|---|---|
| `Application` | Global timing: clock source (`CLOCK_TAI`), base cycle time, TX/RX base offsets, XDP program file to load |
| `TSNHigh` | TSN High traffic class — PROFINET IRT high-priority cyclic frames, XDP-based, VID 100 |
| `TSNLow` | TSN Low traffic class — PROFINET RT lower-priority cyclic frames, XDP-based |
| `RTC` | Real-Time Cyclic — PROFINET RT cyclic process data, XDP-based |
| `RTA` | Real-Time Acyclic — PROFINET RT alarm/acyclic frames, XDP-based, has burst period |
| `DCP` | Device Control Protocol — PROFINET DCP discovery/configuration, non-XDP, multicast destination |
| `LLDP` | Link Layer Discovery Protocol — standard LLDP frames, non-XDP, multicast destination |
| `UDPHigh` | UDP high-priority traffic — standard UDP socket (no XDP), has IP source/destination + port |
| `UDPLow` | UDP low-priority traffic — same as UDPHigh but lower priority/different port |
| `Log` | Log thread priority, CPU affinity, output file path, log level |
| `Debug` | Trace-on-outlier/error flags, monitor mode destination |

### Application Entry — Field Details

**`ApplicationClockId: CLOCK_TAI`**

Clock used for all timing operations — both timestamping frames and scheduling thread wakeups via `clock_nanosleep()`. `CLOCK_TAI` (International Atomic Time) is used instead of `CLOCK_REALTIME` because it is monotonic with no leap second adjustments, making it suitable for deterministic timing.

---

**`ApplicationBaseCycleTimeNS: 1ms`**

The cycle period. The TX thread wakes up every `1ms` via `clock_nanosleep()` to send the next frame. Directly controls the frame send rate and is the basis for all latency/jitter measurements.

---

**`ApplicationBaseStartTimeNS`** (commented out = 0)

Absolute TAI timestamp for when all threads start. If set, both `reference` and `mirror` start at exactly the same point in time — useful for synchronized multi-node tests. If `0` (default), threads start immediately using `clock_gettime()` at launch time.

---

**`ApplicationBaseStartOffsetNS: 0`**

Fine-tuning offset added on top of `ApplicationBaseStartTimeNS`. Only relevant when `BaseStartTimeNS` is explicitly set.

---

**`ApplicationTxBaseOffsetNS: 800us` and `ApplicationRxBaseOffsetNS: 300us`**

Control where within each cycle the TX and RX threads wake up (`utils.c`, `get_thread_start_time()`):

```
wakeup_time = base_start_time + base_start_offset + tx/rx_base_offset
```

With `1ms` cycle, `TX=800us`, `RX=300us`:

```
|<─────────────────── 1ms cycle ──────────────────────>|
0us               300us              800us            1000us
│                   │                  │                 │
cycle start    RX wakes up        TX sends frame    next cycle
               polls for          with timestamp    starts
               reflected frame
```

- RX wakes at `300us` — polls for the frame reflected back from the previous cycle's TX
- TX wakes at `800us` — sends the next frame with embedded timestamp
- The 500us gap (`800us − 300us`) is the **application processing window** — time available between reading the received frame (at 300us) and sending the next frame (at 800us). The application uses this window to process the received data and prepare the next TX frame. It is not the network travel time (physical round-trip latency is independent and determined by hardware).

**Delivery window — maximum physical RTT for same-cycle delivery:**

```
Delivery window = (ApplicationBaseCycleTimeNS − ApplicationTxBaseOffsetNS)
                + ApplicationRxBaseOffsetNS
               = (1000µs − 800µs) + 300µs
               = 500µs
```

This is the maximum round-trip time for a frame to be picked up in cycle N+1 (the intended next cycle) without being late. Breaking it down:

| Term | Value | Meaning |
|---|---|---|
| `ApplicationBaseCycleTimeNS − ApplicationTxBaseOffsetNS` | 200µs | Time remaining in cycle N after TX fires |
| `ApplicationRxBaseOffsetNS` | 300µs | Time into cycle N+1 before RX polls |
| **Delivery window** | **500µs** | **Frame must return within this time** |

If physical RTT > 500µs the frame misses cycle N+1's RX window and is picked up in cycle N+2, adding one full cycle (~1000µs) to the measured RTT. To widen the delivery window, increase `ApplicationRxBaseOffsetNS`:

```
Required RxBaseOffset > physical_RTT_min − ApplicationBaseCycleTimeNS + ApplicationTxBaseOffsetNS
```

> **Note:** `ApplicationBaseStartTimeNS` is not part of this formula — it sets the absolute TAI time when threads start and has no effect on intra-cycle TX/RX timing.

---

**`ApplicationXdpProgram: xdp_kern_profinet_vid100.o`**

XDP BPF object file attached to the NIC at startup when any XDP-enabled traffic class is active. Classifies incoming frames by EtherType/VID and redirects matching frames to the AF_XDP socket. Not loaded when all traffic classes have `XdpEnabled: false`.

---

## Task 4: Which Binary Should AM62Px Run?

**AM62Px should run `reference`. The host PC should run `mirror`.**

- `reference` = measurement node: sends frames, receives them back, computes latency/jitter/cycletime/packet loss
- `mirror` = reflector: receives frames and bounces them back without measuring

Since the goal is to **measure on AM62Px**, AM62Px must be the `reference` node.

> Start order: **mirror first (host PC), then reference (AM62Px).**

---

## Task 5: Changes Made to mirror.yaml and reference.yaml

The existing files were originally written for an Intel Comet Lake PC with i225 NICs. The following changes were made for a minimal UDP test between AM62Px (`eth1`, `172.168.1.22`) and host PC (`172.168.1.1`).

### reference.yaml (runs on AM62Px)

| Field | Was | Now | Reason |
|---|---|---|---|
| `UdpHighSource` | `172.168.1.63` | `172.168.1.22` | Corrected to AM62Px's actual IP |
| `UdpLowEnabled` | `true` | `false` | Disabled for minimal test (UDPHigh only) |
| `UdpLowSource` | `172.168.1.63` | `172.168.1.22` | Corrected in case UDPLow is re-enabled |

All PROFINET/XDP classes (`TSNHigh`, `TSNLow`, `RTC`, `RTA`, `DCP`, `LLDP`) were already disabled. Interface `eth1` and `UdpHighDestination: 172.168.1.1` were already correct.

### mirror.yaml (runs on host PC)

| Field | Was | Now | Reason |
|---|---|---|---|
| `TsnHighEnabled` | `true` | `false` | Disabled — PROFINET XDP not needed for minimal test |
| `TsnLowEnabled` | `true` | `false` | Disabled |
| `RtcEnabled` | `true` | `false` | Disabled |
| `RtaEnabled` | `true` | `false` | Disabled |
| `DcpEnabled` | `true` | `false` | Disabled |
| `LldpEnabled` | `true` | `false` | Disabled |
| `UdpHighDestination` | `192.168.1.1` | `172.168.1.22` | Corrected to AM62Px's IP |
| `UdpHighSource` | `192.168.1.2` | `172.168.1.1` | Corrected to host PC's IP |
| `UdpHighTxThreadCpu` | `6` | `0` | Core 6 may not exist on all host PCs |
| `UdpHighRxThreadCpu` | `6` | `0` | Same |
| `UdpLowEnabled` | `true` | `false` | Disabled for minimal test |
| `UdpLowDestination` | `192.168.1.1` | `172.168.1.22` | Corrected in case re-enabled |
| `UdpLowSource` | `192.168.1.2` | `172.168.1.1` | Corrected in case re-enabled |
| `UdpLowTxThreadCpu` | `7` | `1` | Safe default for host PC |
| `UdpLowRxThreadCpu` | `7` | `1` | Safe default for host PC |
| `LogThreadCpu` | `7` | `2` | Core 7 may not exist on all host PCs |

> `enp3s0` confirmed as correct interface name on host PC.

### Additional fix: TSNHigh required as chain head

**Symptom:** Running `mirror` with only `UDPHigh` enabled produces:
```
Failed to determine PN traffic classes order!
```

**Root cause** (`src/thread.c`, `link_pn_threads()`): RTC-Testbench models all traffic classes as a linked chain in fixed PROFINET priority order:

```
TSNHigh → TSNLow → RTC → RTA → DCP → LLDP → UDPHigh → UDPLow
```

The code requires the **first active class** in the chain to be `TsnHigh`, `Rtc`, or `GenericL2`. `UDPHigh`/`UDPLow` sit at the tail and were designed as supplementary background traffic — not valid standalone head classes. With all PROFINET classes disabled, there is no valid chain head and `link_pn_threads()` returns `-EINVAL`.

**Fix applied:** `TSNHigh` enabled on both `reference.yaml` and `mirror.yaml` with `TsnHighXdpEnabled: false` (raw socket, no XDP program required). This provides the required chain head without needing `xdp_kern_profinet_vid100.o`.

| Field | Was | Now | Reason |
|---|---|---|---|
| `TsnHighEnabled` (both files) | `false` | `true` | Required chain head for UDP-only operation |
| `TsnHighXdpEnabled` (both files) | `true` | `false` | Avoids needing XDP program on host PC |

### Finding: non-XDP TsnHigh path does not work on CPSW3G for VLAN traffic

**Symptom:** `TsnHigh Rx: 0` on reference even after MAC addresses are correct. `tcpdump -i enp3s0 -n` on host PC shows frames arriving from AM62Px but with `ethertype Unknown (0x8892)` — no VLAN tag visible. No return traffic from mirror.

**Root cause — three layers:**

**1. BPF filter design assumes hardware VLAN stripping**

The AF_PACKET socket's BPF filter (`net.c`, `create_tsn_high_socket`) is designed for NICs that perform hardware RX VLAN stripping (originally written for Intel i225):

```
ldh [12]         → check EtherType == 0x8892  (expects VLAN already stripped from frame data)
ld vlan_tci      → read VID from sk_buff->vlan_tci  (populated only when NIC strips VLAN)
jne #0xC064      → check VID=100, PCP=6
```

If the host NIC does NOT strip VLAN tags, `ld vlan_tci` returns 0 and the filter drops every frame. Confirmed: `ethtool -k enp3s0 | grep rx-vlan-offload` = **off**.

**2. CPSW3G strips VLAN tags on TX**

The frame IS built correctly in software with `eth->vlan_proto = 0x8100` (VLAN tag). However, CPSW3G is a **VLAN-aware switch**, not a simple NIC. Its switch fabric processes VLAN tags on egress based on the VLAN table and port configuration, and can **strip VLAN tags before the frame goes out the physical port**. Confirmed: `ethtool -k eth1 | grep tx-vlan-offload` = **off[fixed]** (hardware does not support TX VLAN offload, so this is not the kernel stripping it — it is the CPSW switch fabric doing it).

**3. Combined effect**

| Step | What happens |
|---|---|
| AM62Px TX | Frame built with 0x8100 VLAN tag; CPSW3G switch strips VLAN on egress |
| Wire | Frame has no VLAN tag (`ethertype 0x8892` directly) |
| Host PC RX filter | `ldh [12]` = 0x8892 ✓, but `ld vlan_tci` = 0 (no VLAN present) → filter drops frame |
| Result | Mirror Rx: 0, no return traffic |

**Why XDP works**

The XDP path (`TsnHighXdpEnabled: true`) attaches the BPF program (`xdp_kern_profinet_vid100.o`) to the DMA RX path. On TX, XDP ZC bypasses the switch VLAN processing — Profishark captures confirm the VLAN tag is preserved on the wire in ZC TX mode. VLAN classification is done inside the XDP program on the raw frame data, completely avoiding both the BPF filter VLAN stripping dependency and the CPSW switch VLAN manipulation on TX.

> **Correction:** The RX path does NOT run before the CPSW switch fabric. The actual ingress packet order is: Physical port → CPSW MAC (`rx_good_frames` counted here) → **CPSW ALE** (VLAN lookup, forwarding decision, potential discard) → CPPI5 DMA → UMEM → XDP eBPF program. The ALE runs before XDP. If the ALE discards a frame (e.g. VID 100 not in the VLAN table), XDP never runs. See Known Issue: [CPSW3G ALE discards VID 100 frames after reboot](#cpsw3g-ale-discards-vid-100-frames-after-reboot-reference-rx--0).

**Conclusion:** On CPSW3G platforms, the non-XDP TsnHigh path cannot be used for VLAN-based traffic. XDP must be enabled (`TsnHighXdpEnabled: true`) for TsnHigh to function on AM62Px.

---

### Suggested next step: enable XDP SKB mode for TsnHigh

XDP has three modes — all three require loading a BPF program:

| Mode | BPF program loaded? | Where it runs | NIC driver support needed? |
|---|---|---|---|
| SKB (generic) | Yes | After SKB allocation, generic kernel path | No — works on any NIC |
| Native | Yes | Inside NIC driver, before SKB allocation | Yes |
| Zero-copy | Yes | Inside NIC driver, direct DMA to userspace | Yes + HW support |

`xdp_kern_profinet_vid100.o` must be deployed to **both nodes** for all modes.

#### Step 1 — Deploy XDP program to both nodes

The `.o` file is compiled to BPF bytecode during the RTC-Testbench build and is architecture-independent — the same file works on both AM62Px and x86 host PC.

```bash
# On host PC (from RTC-Testbench build directory)
sudo mkdir -p /usr/local/lib/rtc-testbench/ebpf
sudo cp build/xdp_kern_profinet_vid100.o /usr/local/lib/rtc-testbench/ebpf/

# On AM62Px
mkdir -p /usr/local/lib/rtc-testbench/ebpf
cp xdp_kern_profinet_vid100.o /usr/local/lib/rtc-testbench/ebpf/
```

### Finding: RX_TIMESTAMP=ON forces native XDP mode — SKB mode blocked on AM62Px

**Symptom:** Running reference on AM62Px with `TsnHighXdpSkbMode: true` produces:
```
libbpf: Kernel error message: Can't attach device-bound programs in generic mode
libxdp: Error attaching XDP program to ifindex 3: Invalid argument
xdp_program__attach() failed
Failed to create Tsn Xdp socket!
```

**Root cause** (`xdp.c`, `xdp_set_prog_bind_flags()`): When built with `RX_TIMESTAMP=ON`, the code sets two things at load time:

```c
#ifdef RX_TIMESTAMP
    bpf_program__set_flags(bpf_prog, BPF_F_XDP_DEV_BOUND_ONLY);  // binds program to device, blocks SKB mode
    setenv("LIBXDP_SKIP_DISPATCHER", "1", 1);                     // bypasses multi-prog dispatcher
#endif
```

`BPF_F_XDP_DEV_BOUND_ONLY` and SKB/generic XDP mode are **mutually exclusive by kernel design**. The flag also explains the `.xdp_run_config` and `xdp_metadata` section warnings — the dispatcher is skipped so those sections are unused.

**Effect on each node:**

| Node | Built with | `BPF_F_XDP_DEV_BOUND_ONLY` set? | SKB mode allowed? | Required mode |
|---|---|---|---|---|
| AM62Px (`reference`) | `RX_TIMESTAMP=ON` | Yes | No | **Native** (`XdpSkbMode: false`) |
| Host PC (`mirror`) | `RX_TIMESTAMP=ON` | Yes | No | Rebuild with `RX_TIMESTAMP=OFF` |
| Host PC (`mirror`) | `RX_TIMESTAMP=OFF` | No | Yes | **SKB** (`XdpSkbMode: true`) |

CPSW3G on AM62Px supports native XDP, so native mode works. The host PC mirror does not need RX timestamps (it only reflects frames), so it can safely be built with `RX_TIMESTAMP=OFF`.

**Fix — AM62Px reference.yaml:** already updated — `TsnHighXdpSkbMode: false` (native mode).

**Fix — Host PC mirror binary:** rebuild with `RX_TIMESTAMP=OFF`:

```bash
cd /home/a0500327/Documents/rtc-testbench/RTC-Testbench
rm -rf build && mkdir build && cd build

PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH \
PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=OFF \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      -DCMAKE_C_FLAGS="-DBPF_F_XDP_DEV_BOUND_ONLY=0x40" \
      ..
make -j$(nproc)
```

---

#### Step 2 — Update YAML configs

| File | Field | Value | Reason |
|---|---|---|---|
| Both | `TsnHighXdpEnabled` | `true` | Enable XDP |
| `reference.yaml` (AM62Px) | `TsnHighXdpSkbMode` | `false` | Native mode — required with `RX_TIMESTAMP=ON` |
| `reference.yaml` (AM62Px) | `TsnHighXdpZcMode` | `false` | No ZC for now |
| `reference.yaml` (AM62Px) | `TsnHighTxThreadCpu` / `RxThreadCpu` | `3` | Isolated core |
| `reference.yaml` (AM62Px) | `LogThreadCpu` | `0` | Free isolated core for TsnHigh |
| `mirror.yaml` (host PC) | `TsnHighXdpSkbMode` | `true` | SKB mode — allowed with `RX_TIMESTAMP=OFF` |
| `mirror.yaml` (host PC) | `TsnHighXdpZcMode` | `false` | No ZC on host PC |

#### Step 3 — Run

On host PC (mirror first):
```bash
sudo chrt -f 90 env LD_LIBRARY_PATH=/usr/lib64 ./mirror -c \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/mirror.yaml
```

On AM62Px (reference second):
```bash
chrt -f 90 ./reference -c \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/reference.yaml
```

#### Step 4 — Verify XDP is loaded on AM62Px

```bash
bpftool net show dev eth1    # should show xdp program attached
bpftool prog show            # confirm XDP prog is loaded
```

> Remember: AM62Px `eth1` MAC changes on every reboot. Update `TsnHighDestination` in `mirror.yaml` before each run (`ip link show eth1`).

---

### Finding: LIBXDP_SKIP_DISPATCHER required when RX_TIMESTAMP=OFF

**Symptom:** After rebuilding mirror with `RX_TIMESTAMP=OFF`, the same dispatcher error persists:
```
libbpf: elf: skipping unrecognized data section(7) .xdp_run_config
libbpf: error: program handler doesn't match object
libxdp: Couldn't find xdp program in bpf object section xdp_sock
xdp_program__open_file() failed
```

**Root cause:** With `RX_TIMESTAMP=OFF`, the code no longer calls `setenv("LIBXDP_SKIP_DISPATCHER", "1", 1)`. libxdp then tries to use the multi-prog dispatcher (triggered by the `.xdp_run_config` section in the compiled BPF object). In multi-prog mode, libxdp's internal lookup for `"xdp_sock"` fails because it expects a different program resolution path when the dispatcher is active.

**Fix:** Set `LIBXDP_SKIP_DISPATCHER=1` manually at runtime:

```bash
sudo chrt -f 90 env LD_LIBRARY_PATH=/usr/lib64 LIBXDP_SKIP_DISPATCHER=1 ./mirror -c \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/mirror.yaml
```

This bypasses the multi-prog dispatcher and uses direct section name lookup — the same behaviour that `RX_TIMESTAMP=ON` achieves internally. With `RX_TIMESTAMP=OFF`, `BPF_F_XDP_DEV_BOUND_ONLY` is not set, so SKB mode is still allowed alongside this env var.

| | AM62Px `reference` (`RX_TIMESTAMP=ON`) | Host PC `mirror` (`RX_TIMESTAMP=OFF` + env var) |
|---|---|---|
| `BPF_F_XDP_DEV_BOUND_ONLY` set | Yes (by code) | No |
| `LIBXDP_SKIP_DISPATCHER` set | Yes (by code) | Yes (manually via env) |
| XDP mode | Native | SKB |

**Alternative — build mirror with native XDP mode:** If `enp3s0` on the host PC supports native XDP, rebuild mirror with `RX_TIMESTAMP=ON` and use native mode on both nodes. No `LIBXDP_SKIP_DISPATCHER` workaround needed. See steps below.

### Alternative: host PC mirror with native XDP mode

#### Step 1 — Check if enp3s0 supports native XDP

```bash
ethtool -i enp3s0
# look at 'driver:' field
```

Drivers with native XDP support: `igb`, `igc`, `ixgbe`, `i40e`, `mlx5_core`.
Drivers without: `r8169` (Realtek), `e1000e`. If unsupported, attachment fails with `Error attaching XDP program` — fall back to the `LIBXDP_SKIP_DISPATCHER=1` SKB workaround above.

#### Step 2 — Rebuild mirror with RX_TIMESTAMP=ON

```bash
cd /home/a0500327/Documents/rtc-testbench/RTC-Testbench
rm -rf build && mkdir build && cd build

PKG_CONFIG_PATH=/usr/lib64/pkgconfig:$PKG_CONFIG_PATH \
PKG_CONFIG="pkg-config --static" \
cmake -DCMAKE_BUILD_TYPE=Release \
      -DRX_TIMESTAMP=ON \
      -DCMAKE_FIND_LIBRARY_SUFFIXES=".a;.so" \
      -DCMAKE_C_FLAGS="-DBPF_F_XDP_DEV_BOUND_ONLY=0x40" \
      ..
make -j$(nproc)
```

#### Step 3 — mirror.yaml: set native mode

`mirror.yaml` already updated: `TsnHighXdpSkbMode: false`.

Both `reference.yaml` (AM62Px) and `mirror.yaml` (host PC) now use native mode with `RX_TIMESTAMP=ON`.

#### Step 4 — Run without LIBXDP_SKIP_DISPATCHER

On host PC:
```bash
sudo chrt -f 90 env LD_LIBRARY_PATH=/usr/lib64 ./mirror -c \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/mirror.yaml
```

On AM62Px:
```bash
chrt -f 90 ./reference -c \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/reference.yaml
```

> If `Error attaching XDP program` appears on the host PC, `enp3s0` does not support native XDP. Revert `mirror.yaml` to `TsnHighXdpSkbMode: true`, rebuild mirror with `RX_TIMESTAMP=OFF`, and use `LIBXDP_SKIP_DISPATCHER=1` as described above.

---

### Additional fix: libbpf.so.1 not found on host PC

**Symptom:**
```
./mirror: error while loading shared libraries: libbpf.so.1: cannot open shared object file: No such file or directory
```

**Root cause:** `libbpf` was built from source and installed to `/usr/lib64/` which is not in Ubuntu's default dynamic linker search path.

**Fix:** Register the path permanently:
```bash
echo "/usr/lib64" | sudo tee /etc/ld.so.conf.d/libbpf.conf
sudo ldconfig
ldconfig -p | grep libbpf   # verify
```

### Before every run: post-reboot checklist

> **AM62Px `eth1` generates a random MAC address on each reboot.** Always re-check and update both YAML files after rebooting AM62Px. Also apply the promiscuous mode fix and TX checksum workaround.

**Step 1 — Get current MACs:**

On AM62Px:
```bash
ip link show eth1
# Copy the 'link/ether' value — this is the AM62Px eth1 MAC
```

On host PC:
```bash
ip link show enp3s0
# Copy the 'link/ether' value — this is the host PC enp3s0 MAC
```

**Step 2 — Update YAML files:**

| File | Field | Value to set |
|---|---|---|
| `reference.yaml` (on AM62Px) | `TsnHighDestination` | host PC `enp3s0` MAC |
| `mirror.yaml` (on host PC) | `TsnHighDestination` | AM62Px `eth1` MAC |

```bash
# On AM62Px — replace with current host PC MAC
sed -i 's/TsnHighDestination:.*/TsnHighDestination: <host-pc-enp3s0-MAC>/' \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/reference.yaml

# On host PC — replace with current AM62Px eth1 MAC
sed -i 's/TsnHighDestination:.*/TsnHighDestination: <AM62Px-eth1-MAC>/' \
  /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/mirror.yaml
```

**Step 3 — Apply required per-reboot fixes on AM62Px:**

```bash
# Fix 1: bypass CPSW ALE VLAN filtering (required or reference Rx stays 0)
ip link set eth1 promisc on

# Fix 2: clear stale psdata[2] to prevent TX payload corruption
ethtool -K eth1 tx-checksum-ip-generic off
```

### Run the minimal test

On host PC:
```bash
sudo chrt -f 90 env LD_LIBRARY_PATH=/usr/lib64 ./mirror -c /home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests/mirror.yaml
```

> `sudo` is required to set real-time thread priorities and write to `/var/log/`. `LD_LIBRARY_PATH=/usr/lib64` is needed until `ldconfig` fix above is applied.

On AM62Px:
```bash
chrt -f 90 ./reference -c /root/rtc-testbench/mytests/reference.yaml
```

To run for a fixed duration (reference shuts down cleanly, histogram written on exit):
```bash
# Run for 60 seconds then stop
timeout 60s chrt -f 90 ./reference -c /root/rtc-testbench/mytests/reference.yaml

# With SIGKILL fallback if process doesn't exit within 5s of SIGTERM
timeout --kill-after=5s 60s chrt -f 90 ./reference -c /root/rtc-testbench/mytests/reference.yaml
```

> Time formats: `60s`, `5m`, `1h`, `1m30s`. `timeout` sends `SIGTERM` at the deadline, which triggers the clean shutdown path — histogram is written and stats are flushed.

---

## Required manual steps before running

Run these on AM62Px after every reboot, before starting reference or mirror.

1. **Apply TX payload corruption workaround** — prevents stale `psdata[2]` from corrupting XDP ZC TX frames on both CPSW ports:
   ```bash
   ethtool -K eth0 tx-checksum-ip-generic off
   ethtool -K eth1 tx-checksum-ip-generic off
   ```

2. **Configure RX flows** — sets eth1 RX traffic to Flow/Queue 0:
   ```bash
   ./configure-rx-flows.sh
   ```

3. **Update YAML files with current MAC addresses** — AM62Px `eth1` MAC changes on every reboot:

   On AM62Px, get current eth1 MAC:
   ```bash
   ip link show eth1
   ```

   Update `reference.yaml` on AM62Px:
   ```bash
   sed -i 's/TsnHighDestination:.*/TsnHighDestination: <host-pc-enp3s0-MAC>/' <reference.yaml>
   ```

   Update `mirror.yaml` on host PC:
   ```bash
   sed -i 's/TsnHighDestination:.*/TsnHighDestination: <AM62Px-eth1-MAC>/' <mirror.yaml>
   ```

4. **Enable promiscuous mode** — bypasses CPSW ALE VLAN filtering (required or `reference Rx` stays 0):
   ```bash
   ip link set eth1 promisc on
   ```

---

## Task 6: XDP Zero-Copy Test YAMLs

New configs created in `/home/a0500327/Documents/rtc-testbench/am62px-rtc-testbench/mytests-xdp-zc/`.

### Key differences from mytests (UDP test)

| | mytests (UDP) | mytests-xdp-zc (XDP ZC) |
|---|---|---|
| Active traffic class | `UDPHigh` | `TSNHigh` |
| Transport | Standard UDP socket | Raw Layer 2 VLAN (VID 100) via XDP |
| AM62Px XDP mode | N/A | `XdpZcMode: true`, `XdpSkbMode: false` |
| Host PC XDP mode | N/A | `XdpSkbMode: true` (ZC only if NIC supports it) |
| AM62Px TX/RX CPU | 1 | 3 (isolated core, `isolcpus=3`) |
| XDP program needed | Not required | `xdp_kern_profinet_vid100.o` |
| Log file | `reference_vid100.log` | `reference_xdp_zc.log` |

### XDP program file required

**`xdp_kern_profinet_vid100.o`** — classifies VLAN-tagged frames with VID 100 and redirects them to the XDP socket.

- Built automatically from the RTC-Testbench source during `make -j$(nproc)`
- Must be deployed to **both nodes** before running:

```bash
# On AM62Px
mkdir -p /usr/local/lib/rtc-testbench/ebpf
cp <build-dir>/xdp_kern_profinet_vid100.o /usr/local/lib/rtc-testbench/ebpf/

# On host PC
mkdir -p /usr/local/lib/rtc-testbench/ebpf
cp <build-dir>/xdp_kern_profinet_vid100.o /usr/local/lib/rtc-testbench/ebpf/
```

### Run the XDP ZC test

On host PC (mirror first):
```bash
chrt -f 90 mirror -c /path/to/mytests-xdp-zc/mirror.yaml
```

On AM62Px (reference second):
```bash
chrt -f 90 reference -c /path/to/mytests-xdp-zc/reference.yaml
```

### Verify XDP is active during test

On AM62Px in a separate terminal:
```bash
bpftool net show dev eth1    # should show xdp program attached
bpftool prog show            # confirm XDP prog is loaded
xdpsock --extra-stats --app-stats
```

---

## Task 7: Host PC as Link Partner — Validity Concerns

### Why the concern is valid

RTC-Testbench measures **round-trip latency**: `reference` embeds a TX timestamp in each frame, `mirror` reflects it back, and `reference` computes:

```
measured latency = AM62Px TX path + wire + mirror processing + wire + AM62Px RX path
```

The host PC `mirror` runs on a standard non-RT Linux kernel (no PREEMPT_RT, no CPU isolation, no IRQ pinning). Its `mirror` processing time is subject to:

- CFS scheduler preemption — mirror threads compete with background processes even at SCHED_FIFO priority 98, because without PREEMPT_RT the kernel itself has non-preemptible sections
- NIC interrupt latency — standard NIC driver without IRQ affinity has variable wakeup delay
- UDP path — goes through full network stack (socket → IP → driver), adding variable latency

Any variability in mirror processing shows up directly as **jitter** in the reference measurements, making AM62Px appear worse than it actually is. This is particularly significant for the UDP test, where the host PC mirror processes entirely in userspace through the full network stack.

### Options ranked by measurement quality

#### Option 1 — Loopback on AM62Px (best for pure AM62Px characterization)

Connect `eth0` ↔ `eth1` on the AM62Px with a physical Ethernet cable. Run both `reference` (on `eth1`) and `mirror` (on `eth0`) on the same board. The remote node is eliminated entirely.

```
AM62Px
  eth1 (XDP ZC, Flow 0) ──cable── eth0 (Flow 1)
  reference ────────────────────── mirror
```

What this measures: AM62Px TX path + cable propagation (~5 ns/m) + AM62Px RX path — no remote node variable at all. This is the cleanest way to characterize the CPSW3G + XDP stack on AM62Px.

**YAML changes needed for loopback reference (on eth1):**
- `GenericL2Interface: eth1`, `GenericL2RxQueue: 0`, TX/RX CPU: 3 (isolated)
- `GenericL2Destination`: set to eth0 MAC address

**YAML changes needed for loopback mirror (on eth0):**
- `GenericL2Interface: eth0`, `GenericL2RxQueue: 1` (Flow 1 = eth0 RX per known conditions)
- `GenericL2Destination`: set to eth1 MAC address
- TX/RX CPU: 1 or 2 (separate from reference's isolated core 3)

Both binaries run on the same AM62Px simultaneously, each pinned to separate cores.

#### Option 2 — Another PREEMPT_RT board as mirror (best for end-to-end system test)

Use a second RT-capable board (another AM62Px, BeagleBone, or any board running PREEMPT_RT) as the mirror node. Both sides have deterministic scheduling, giving results that represent the true system-level performance.

#### Option 3 — Host PC with RT tuning (acceptable with caveats)

Install PREEMPT_RT on the host PC, add `isolcpus`, pin the enp3s0 IRQ to the isolated core. This significantly reduces mirror jitter but requires kernel replacement on the host.

#### Option 4 — Current setup: host PC, no RT (baseline / sanity check only)

Acceptable for verifying the test runs end-to-end and that AM62Px is sending/receiving frames. **Do not use these numbers to characterize AM62Px absolute latency or jitter** — the host PC mirror noise floor is unknown and dominates the measurement, especially for the UDP test.

### Summary

| Setup | Measures | Suitable for |
|---|---|---|
| Loopback eth0↔eth1 on AM62Px | AM62Px stack only | AM62Px characterization |
| Second RT board as mirror | Full system, both nodes RT | System-level validation |
| Host PC + PREEMPT_RT | Full system, both nodes RT | System-level validation |
| Host PC, no RT (current) | Round-trip including host jitter | Sanity check / bring-up only |

> For the current bring-up test (Task 5), the host PC setup is fine to verify connectivity and confirm the tool runs. For any latency/jitter numbers that matter, use the loopback or a second RT board.

---

## Task 8: Plotting RTT Histogram

RTC-Testbench has a built-in histogram that bins per-cycle RTT values into 1µs buckets and writes the distribution to a file on shutdown. This gives a full spectrum of latency/jitter rather than just min/avg/max.

> **Sampling rate:** The histogram captures one RTT sample per received frame — every frame that successfully returns from mirror is binned. With `ApplicationBaseCycleTimeNS: 1ms` this is 1000 samples/second. There is no decimation or averaging; the distribution directly reflects per-cycle RTT for the full duration of the test run.

### Step 1 — Enable histogram in `reference.yaml`

Add a `Stats` section at the end of the YAML (before or after `Debug`):

```yaml
Stats:
  StatsHistogramEnabled: true
  StatsHistogramMinimumNS: 1ms    # lower bound of histogram range
  StatsHistogramMaximumNS: 10ms   # upper bound of histogram range
  StatsHistogramFile: /var/log/histogram.txt
```

> Adjust `StatsHistogramMinimumNS` / `StatsHistogramMaximumNS` to bracket the expected RTT range. With a non-RT host PC mirror, RTT can reach 15ms — set `StatsHistogramMaximumNS: 20ms` in that case. Samples outside the range are counted as Overflow/Underflow but not binned.

### Step 2 — Run the test, then stop reference

Run as normal. Stop reference with `Ctrl+C` — `histogram_write()` is called on clean shutdown. The histogram file is only written on exit, not during the run.

```bash
chrt -f 90 ./reference -c reference.yaml
# ... let it run, then Ctrl+C
# histogram written to /var/log/histogram.txt
```

### Step 3 — Transfer histogram file to host PC

```bash
scp root@<AM62Px-IP>:/var/log/histogram.txt .
```

### Step 4 — Plot with plot_rtt.py

`plot_rtt.py` is the recommended plotting script. It produces a bar chart of the RTT distribution with min/max/avg overlay lines and a stats annotation box.

**Install dependency if needed:**
```bash
pip3 install matplotlib
```

**Script location:** `am62px-rtc-testbench/testlogs/plot_rtt.py`

#### Usage modes

| Command | Data sources | Stats shown |
|---|---|---|
| `python3 plot_rtt.py histogram.txt` | histogram only | Min, max, avg (from bins), overflow, underflow |
| `python3 plot_rtt.py histogram.txt reference_vid100.log` | histogram + log | Above + total TX, total RX (from log) |
| Any of the above `--duration <value>` | as above + user-supplied | Above + runtime duration |
| Any of the above `--title <string>` | — | Custom plot title (default: `TSNHigh RTT Distribution`) |
| Any of the above `--output <filename>` | — | Custom output filename (default: `rtt_histogram.png`) |

#### Duration format

`--duration` accepts flexible units — values can be combined:

| Example | Meaning |
|---|---|
| `--duration 1049` | 1049 seconds |
| `--duration 1049s` | 1049 seconds |
| `--duration 17m` | 17 minutes |
| `--duration 1h` | 1 hour |
| `--duration 1h30m` | 1 hour 30 minutes |
| `--duration 1m30s` | 1 minute 30 seconds |
| `--duration 1h30m20s` | 1 hour 30 minutes 20 seconds |

#### Examples

```bash
# Histogram only — min/max/avg derived from histogram bins
python3 plot_rtt.py histogram.txt

# Histogram + log — TX/RX counts and min/max/avg taken from log
python3 plot_rtt.py histogram.txt reference_vid100.log

# Histogram only with runtime duration annotated
python3 plot_rtt.py histogram.txt --duration 17m29s

# All sources
python3 plot_rtt.py histogram.txt reference_vid100.log --duration 1h

# Custom title and output filename
python3 plot_rtt.py histogram.txt reference_vid100.log --title "AM62Px Loopback XDP ZC" --output loopback.png

# All options combined
python3 plot_rtt.py histogram.txt reference_vid100.log --duration 17m29s \
  --title "TSNHigh RTT Distribution - AM62Px (Reference) <--> AM62x (Mirror)" --output am62px_host_pc.png
```

Output saved to the filename specified by `--output` (default: `rtt_histogram.png`) in the current directory.

#### What the plot shows

- **Bar chart** — RTT frequency distribution (1µs bins, TsnHigh traffic class)
- **Green dashed line** — RTT minimum
- **Red dashed line** — RTT maximum
- **Orange dashed line** — RTT average
- **Stats box** (top-right) — TX packets, RX packets, RTT min/max/avg, overflow/underflow counts, duration (if provided)

> **Note on min/max/avg source:** When `reference_vid100.log` is provided, min/max/avg are taken from the log (exact per-frame tracking). Without the log, they are derived from the histogram bins (accurate to 1µs resolution, but excludes any overflow/underflow samples outside the configured histogram range).

### What to look for

| Distribution shape | Interpretation |
|---|---|
| Narrow spike, low µs | Good determinism — consistent latency |
| Wide spread / long tail | Jitter — scheduling noise or non-RT mirror |
| Bimodal peaks | Two distinct paths (e.g. frames arriving in different cycles) |
| Large Overflow count | `StatsHistogramMaximumNS` too small — increase it |

---

## Interpreting RTC-Testbench Results

### Stats output format

The reference binary prints one line per active traffic class every second:

```
TsnHigh : Tx:    107060 Rx:    107058 RttMin[us]:      1459 RttAvg[us]:1496.061621 RttMax[us]:      2507 Err:  107056 Outlier:     697
```

| Field | Description |
|---|---|
| `Tx` | Cumulative frames sent by reference |
| `Rx` | Cumulative frames received back from mirror |
| `RttMin[us]` | Minimum round-trip time in microseconds since start. `18446744073709551615` = `UINT64_MAX` means no valid measurement yet (Rx = 0) |
| `RttAvg[us]` | Rolling average RTT |
| `RttMax[us]` | Maximum RTT since start |
| `Err` | Sum of `frame_id_errors + out_of_order_errors + payload_errors` (`print.c`) |
| `Outlier` | Frames where RTT exceeded `2 × ApplicationBaseCycleTimeNS` (e.g. 2000 µs for a 1ms cycle), or one-way delay exceeded `1 × ApplicationBaseCycleTimeNS`. Threshold is hardcoded — not configurable. High outlier count with a non-RT mirror is expected when average RTT already exceeds 2ms. `ApplicationBaseCycleTimeNS` is the cycle period set in the `Application` section of `reference.yaml` (e.g. `ApplicationBaseCycleTimeNS: 1ms`). |

> **Note:** `RttMin/Avg/Max` is a **true round-trip time** — reference TX → wire → mirror → wire → reference RX, measured entirely on the reference node's own clock (`reference_rx_time − reference_tx_time` from the reference's own backlog). No clock synchronisation with the mirror is needed.
>
> The log file (`/var/log/reference_vid100.log`) also contains `TsnHighOnewayMin`, `TsnHighOnewayAvg`, `TsnHighOnewayMax` in each `[INFO]` line, for example:
> ```
> TsnHighRttMin=494 [us] | TsnHighRttMax=6492 [us] | TsnHighRttAvg=1620.202531 [us] |
> TsnHighOnewayMin=-1220 [us] | TsnHighOnewayMax=552 [us] | TsnHighOnewayAvg=-209.294784 [us] |
> ```
> `TsnHighOnewayMin/Avg/Max` IS a one-way measurement: `reference_rx_time − mirror_tx_time`. The mirror embeds its own CLOCK_TAI + 500µs into the reflected frame via `set_mirror_tx_timestamp()`, and the reference subtracts that from its receive time. This one-way measurement **requires synchronised clocks** between reference and mirror (e.g. via PTP) to be meaningful as a latency value. Without clock sync the absolute value is unreliable — negative values (e.g. `TsnHighOnewayMin=-1220 [us]`) are physically impossible and indicate clock offset between nodes. The variance (jitter) of the oneway values remains valid for relative comparison even without sync.

---

### Understanding the Err counter

`Err` is the sum of three independent error flags checked per received frame (`profinet.c`):

| Error type | Check | Log message |
|---|---|---|
| `out_of_order` | `sequence_counter != rx_sequence_counter` | `SequenceCounter mismatch` |
| `payload_mismatch` | `memcmp(payload, expected_pattern, len)` | `Payload Pattern mismatch` |
| `frame_id_mismatch` | `frame_id != thread_context->frame_id` | `FrameId mismatch` |

To identify which type dominates, grep the log file:

```bash
grep -c "SequenceCounter mismatch" /var/log/reference_vid100.log
grep -c "Payload Pattern mismatch" /var/log/reference_vid100.log
grep -c "FrameId mismatch" /var/log/reference_vid100.log

# Or show the first few errors
grep -m 5 "mismatch" /var/log/reference_vid100.log
```

---

### Common error scenarios

#### Nearly 100% Err rate

If `Err ≈ Rx`, all received frames have at least one error. Possible causes:

| Error type | Root cause |
|---|---|
| `SequenceCounter mismatch` | RTT > cycle time (e.g. 1459µs RTT with 1ms cycle) — frames arrive 2 cycles late. Reference `rx_sequence_counter` can get out of sync if the timing window causes frames to be received in an unexpected order |
| `Payload Pattern mismatch` | CPSW3G stripping VLAN before XDP UMEM on RX → `vlan_tag_missing=true` on mirror → `insert_vlan_tag` shifts frame content 4 bytes → payload at wrong offset on reference RX |
| `FrameId mismatch` | Mirror modified or corrupted the frame ID (should be `0x0100` for TSNHigh non-secure) |

#### High RTT values (> cycle time)

With a non-RT host PC as the mirror, RTT of 1459–2507µs at a 1ms cycle time is **expected**. The host PC's CFS scheduler and lack of PREEMPT_RT means the mirror processing time is variable and can exceed 1ms. This is not a bug — it is the measurement noise introduced by the non-RT mirror (see Task 7).

For accurate latency/jitter numbers, use a loopback setup or a second RT board as the mirror.

#### Outlier counter

Counts frames where RTT or one-way delay exceeded `rtt_expected_rt_limit` (derived from cycle time). A small outlier count (~0.65%) is normal with a non-RT mirror. High outlier rates (>5%) with an RT mirror indicates genuine timing issues in the DUT.

---

### Diagnostic checklist

| Symptom | First check | Likely cause |
|---|---|---|
| `Rx: 0`, `RttMin = UINT64_MAX` | `ethtool -S eth1 \| grep rx_good_frames` incrementing? XDP trace events firing? | If `rx_good_frames` up but no XDP events: CPSW ALE discarding frames — run `ip link set eth1 promisc on`. Otherwise: stale MAC or XDP not loaded |
| `Rx` incrementing, `Err ≈ Rx` | Check log for which mismatch type | Sequence counter, payload, or frame ID issue |
| `Rx` incrementing, `Err = 0` | Check RTT vs cycle time | Working correctly |
| `Outlier` high | Is mirror RT? | Non-RT mirror jitter, use loopback or RT mirror |
| `Tx` incrementing, `Rx = 0`, frames not on host tcpdump | `ip -s link show eth1` TX counter | AF_XDP TX not working — enable ZC mode on AM62Px |
| `Tx` incrementing, `Rx = 0`, frames on host tcpdump | Mirror XDP redirecting? `ip -s link show enp3s0` | xsks_map not populated or wrong queue |

## Known Issues

### CPSW3G does not support two simultaneous ZC AF_XDP sockets — loopback mirror must use copy mode

**Setup:** AM62Px loopback test — `reference` on eth1 (ZC mode) and `mirror` on eth0 (ZC mode) running simultaneously on the same board.

**Symptom:** Reference starts after mirror is already running and fails. Two distinct error forms are seen depending on state:

**Form 1 — XDP program attachment blocked** (stale XDP from previous run on eth1, or mirror misconfigured on eth1):
```
libbpf: elf: skipping unrecognized data section(9) .xdp_run_config
libbpf: elf: skipping unrecognized data section(7) xdp_metadata
libbpf: Kernel error message: XDP program already attached
libxdp: Error attaching XDP program to ifindex 3: Device or resource busy
libxdp: XDP already loaded on device
xdp_program__attach() failed
Failed to create Tsn Xdp socket!
Failed to create and start TSN High Threads!
```
Fix for Form 1: detach the stale XDP program — `ip link set dev eth1 xdp off` — then retry.

**Form 2 — AF_XDP ZC socket creation blocked** (after detaching stale XDP, or when mirror on eth0 is in ZC mode):
```
libbpf: elf: skipping unrecognized data section(9) .xdp_run_config
libbpf: elf: skipping unrecognized data section(7) xdp_metadata
xsk_socket__create() failed: Device or resource busy
Failed to create Tsn Xdp socket!
Failed to create and start TSN High Threads!
```
No stale reference process exists (`pgrep reference` returns nothing). Mirror is confirmed running on eth0. This is the CPPI5 ZC DMA conflict described below.

**Root cause:** CPSW3G uses a shared CPPI5 DMA engine for both eth0 and eth1. AF_XDP zero-copy (ZC) mode requires exclusive DMA mapping of the UMEM buffer directly into the NIC's DMA address space. When mirror on eth0 has already claimed the ZC DMA resources, a second ZC socket on eth1 cannot be created — the DMA engine is already committed to the first socket's UMEM mapping.

**Fix:** Run mirror in **copy mode** (`TsnHighXdpZcMode: false`) for the loopback test. Mirror only needs to receive and reflect frames; it does not face the same ZC TX requirement that reference does.

In `mirror.yaml` (loopback, running on eth0):
```yaml
TsnHighXdpZcMode: false    # copy mode — allows reference on eth1 to use ZC
TsnHighXdpSkbMode: false   # keep native mode
```

Reference on eth1 keeps `TsnHighXdpZcMode: true` unchanged.

> **Note:** The known issue "CPSW3G AF_XDP TX only works in ZC mode" applies to the **reference** TX path on eth1. Mirror TX on eth0 in copy mode works correctly for the loopback reflector role since it is not subject to the same CPPI5 ZC TX path constraint.

**Verify before starting reference:**
```bash
bpftool net show dev eth0   # mirror XDP attached here
bpftool net show dev eth1   # should be empty before reference starts
```

---

### AM62x eth0 requires TsnHighRxQueue: 1 — n-tuple filter maps eth0 to queue 1

**Setup:** AM62x running `reference` with `TsnHighInterface: eth0`, `TsnHighXdpZcMode: true`. `configure-rx-flows.sh` run on AM62x.

**Symptom:** `reference Rx: 0` despite frames physically arriving at AM62x eth0 (confirmed by `ethtool -S eth0 rx_good_frames` incrementing and `ip -s link show eth0` showing high drop rate). `bpf_printk` trace shows:
```
Frame ID matches expected values, redirecting to user space
No socket bound to queue, passing to kernel stack
```

**Root cause:** `configure-rx-flows.sh` uses `ethtool -N eth0 flow-type ether dst $eth0_mac_addr action 1` — it steers eth0 unicast traffic to **queue 1** (not queue 0). The XDP program reaches `bpf_map_lookup_elem(&xsks_map, &ctx->rx_queue_index)` with `ctx->rx_queue_index = 1`, but the reference socket is registered at xsks_map[0] (default `TsnHighRxQueue: 0`), so the lookup returns NULL → XDP_PASS → frame dropped.

Confirmed via:
```bash
ethtool -n eth0
# Action: Direct to queue 1  ← eth0 traffic goes to queue 1, not queue 0
```

**Fix:** set `TsnHighRxQueue: 1` and `TsnHighTxQueue: 1` in `reference.yaml` when using eth0 on AM62x:
```yaml
TsnHighRxQueue: 1
TsnHighTxQueue: 1
```

**Note:** eth1 on AM62x maps to queue 0 (`action 0` in `configure-rx-flows.sh`), so `TsnHighRxQueue: 0` is correct when using eth1. Prefer eth1 for testing to stay consistent with the AM62Px setup.

---

### TSNHigh payload corruption on AM62Px XDP ZC TX

**Setup:** AM62Px running `reference` with `TsnHighXdpEnabled: true`, `TsnHighXdpZcMode: true` (native XDP zero-copy), host PC running `mirror` with `TsnHighXdpEnabled: true`, `TsnHighXdpZcMode: true`.

**Symptom:** `Err ≈ Rx` (nearly 100% payload mismatch) on reference stats:
```
TsnHigh : Tx: 107060 Rx: 107058 RttMin[us]: 1459 RttAvg[us]: 1496 RttMax[us]: 2507 Err: 107056 Outlier: 697
```
Log confirms `Payload Pattern mismatch` for every frame from frame[0]. Mirror log shows the same count of payload mismatches — confirming the corruption originates on the **reference TX side**, not the mirror.

**Confirmed by tcpdump** (mirror not running, XDP not loaded on enp3s0):
```
sudo tcpdump -i enp3s0 -XX -c 3 ether src 82:13:7d:f2:94:7e
```

Three consecutive frames showing bytes 50-51 vary each frame:
```
Frame 1 (cycle d59a): ...6164 7b2f 7474 6572 6e0a...   → "ad{/ttern\n"
Frame 2 (cycle d59b): ...6164 37ff 7474 6572 6e0a...   → "ad7.ttern\n"
Frame 3 (cycle d59c): ...6164 f86b 7474 6572 6e0a...   → "ad.kttern\n"
```

Expected at bytes 50-51: `50 61` (`Pa` of `Pattern`). Actual: varies per frame.

**Frame structure annotation (128 bytes, VLAN confirmed present):**
```
Byte  0-11:  dst + src MAC                         ✓
Byte 12-15:  8100 0064 → VLAN tag, VID=100         ✓  CPSW ZC preserves VLAN
Byte 16-17:  8892 → PROFINET inner EtherType       ✓
Byte 18-19:  0100 → frame_id TSN_HIGH_FRAMEID      ✓
Byte 20-27:  frame_counter + cycle_counter         ✓
Byte 28-35:  tx_timestamp (changes per frame)      ✓
Byte 36-57:  payload "TsnHighPayloadPattern\n"     ✗ bytes 50-51 corrupted
```

**Key observations:**
- VLAN tag is intact — CPSW3G ZC TX correctly preserves VID 100
- Only bytes 50-51 are corrupted regardless of traffic class (see GenericL2 finding below)
- The corrupted bytes change deterministically each frame for TSNHigh, correlating with tx_timestamp
- `bridge vlan add dev eth1 vid 100` does not fix this — VLAN forwarding is not the issue

**GenericL2 also affected (EtherType hypothesis disproved):**

Testing with `GenericL2` (EtherType `0xb62c`, VID 200) shows the **same corruption at the same absolute frame offset 50-51**:

```
Frame 1 (cycle 5991): ...6164 7a8f 7474 6572 6e0a...   → "adz.ttern\n"
Frame 2 (cycle 5992): ...6164 7a8f 7474 6572 6e0a...   → "adz.ttern\n"
Frame 3 (cycle 5993): ...6164 7a8f 7474 6572 6e0a...   → "adz.ttern\n"
```

Corrupted bytes are `7a 8f` — **constant** across frames (vs varying for TSNHigh). The GenericL2 payload starts at frame byte 34 (not 36), so bytes 50-51 are at payload index 16-17, still the `Pa` of `Pattern`. Absolute frame offset is the same: **50-51**.

**Root cause — stale `psdata[2]` in CPPI5 TX descriptor (driver bug in `am65_cpsw_xsk_xmit_zc`):**

The CPSW3G TX path uses CPPI5 descriptors from a descriptor pool (`k3_cppi_desc_pool_alloc` / `k3_cppi_desc_pool_free`). These descriptors are recycled without being zeroed (`gen_pool_alloc` does not zero memory).

Each CPPI5 descriptor contains a **PS (Protocol Specific) data** region separate from the packet buffer. `psdata[2]` encodes a hardware checksum offload instruction:

```c
// From am65-cpsw-nuss.c, normal SKB TX path:
psdata[2] = ((cs_offset + 1) << 24) | ((cs_start + 1) << 16) | (skb->len - cs_start);
// e.g. for TCP over IPv4: cs_start=34, cs_offset=50 → psdata[2] = 0x33230000 | length
```

When a descriptor previously used for a TCP/IP skb (with HW checksum offload) is recycled and reused for XSK ZC TX:

- **Normal SKB TX path** (`am65_cpsw_nuss_start_xmit`, line 2054): explicitly clears `psdata[2] = 0` before use
- **XSK ZC TX path** (`am65_cpsw_xsk_xmit_zc`, lines 1268-1283): calls `cppi5_hdesc_init` which only sets `pkt_info0` and `next_desc = 0` — **`psdata[2]` is never cleared**

The stale `psdata[2]` value instructs the CPSW switch to:
1. Read the instruction from the descriptor: "compute checksum starting at byte 34, insert 2-byte result at byte 50"
2. Read the packet from the UMEM (separate DMA)
3. Compute a 16-bit one's complement checksum over packet bytes 34–49
4. **Write the 2-byte result back into the UMEM at bytes 50–51** before transmission

The descriptor and the packet buffer are in separate memory — `psdata[2]` is never overwritten by the payload. It is an instruction, and the UMEM is its target. Clearing `psdata[2] = 0` disables the instruction so no write-back occurs.

**Why the corruption value differs by traffic class:**

| Traffic class | Bytes 34-49 content | Checksum input varies? | Result |
|---|---|---|---|
| TSNHigh | tx_timestamp bytes 34-35 + "TsnHighPayload" | Yes — tx_timestamp changes each frame | Varies per frame |
| GenericL2 | "GenericL2Payload" (constant payload, tx_timestamp ends at byte 33) | No — all bytes 34-49 are constant | Constant `7a 8f` |

**Driver bug location:** `am65_cpsw_xsk_xmit_zc` in `drivers/net/ethernet/ti/am65-cpsw-nuss.c` does not call `cppi5_hdesc_get_psdata(host_desc)[2] = 0` after `cppi5_hdesc_init`, unlike the SKB TX path.

**Workaround (without modifying driver):** Disable TX checksum offload on eth1 to prevent `psdata[2]` from ever being set to a non-zero value by the SKB TX path:

```bash
ethtool -K eth1 tx-checksum-ip-generic off
ethtool -K eth1 tx-checksum-ipv4 off 2>/dev/null
```

After disabling, subsequent skb TX descriptors will have `psdata[2] = 0`. All descriptors in the pool will be cycled through with clean values after normal network traffic, eliminating the stale checksum instruction.

**RTT measurements remain valid** despite 100% Err — `stat_frame_received` is called regardless of payload mismatch and the RTT stats (`RttMin/Avg/Max`) are computed from the `tx_timestamp` independently of error flags.

**Status:** Driver bug in `am65_cpsw_xsk_xmit_zc` — missing `psdata[2] = 0` initialization for XSK ZC TX descriptors.

---

### CPSW3G ALE discards VID 100 frames after reboot — reference Rx = 0

**Setup:** AM62Px rebooted. `configure-rx-flows.sh` re-run (or not run). Reference started with `TsnHighXdpEnabled: true`, `TsnHighXdpZcMode: true`. Mirror confirmed sending reflected frames (Profishark shows correct 802.1Q VID 100 frames on wire in both directions). `ethtool -S eth1 rx_good_frames` incrementing.

**Symptom:** `TsnHigh Rx: 0` on reference. `ip -s link show eth1` RX stays at 0. No XDP trace events fire (`xdp_redirect`, `xdp_redirect_err`, `xdp_exception` all silent) despite expected ~1000 frames/sec.

**Diagnosis — packet path:**

```
Physical port 2 (wire)
       │
       ▼
CPSW MAC  ← rx_good_frames increments here
       │
       ▼
CPSW ALE  ← frames discarded HERE if VID 100 not in VLAN table
       │
       ▼  (only if ALE forwards to CPU)
CPPI5 DMA → UMEM → XDP eBPF program
```

**Evidence:**

| Check | Result | Interpretation |
|---|---|---|
| Profishark (wire capture) | 802.1Q VID 100 frames present in both directions | Frames correct on wire |
| `ethtool -S eth1 rx_good_frames` | Incrementing | CPSW MAC receives frames |
| XDP trace events (`xdp_redirect` etc.) | **Nothing fires** | XDP eBPF program never executes |
| `bpf_printk` in XDP program | **Very few prints** vs expected ~1000/sec | ALE forwards only occasional frames to CPU |

"Nothing fires" from XDP trace events combined with `rx_good_frames` incrementing confirms the ALE is discarding most frames before they reach the XDP hook. The few frames that do get through (evidenced by occasional `bpf_printk` output) are likely ALE learning/flood exceptions.

**Root cause:** After a reboot, the CPSW ALE initialises with VID 100 absent from its VLAN table. When VID 100 is not in the ALE VLAN table for port 2, the ALE discards ingress frames with that VID rather than forwarding them to the CPU DMA path. `rx_good_frames` is a MAC-level counter that fires before the ALE, so it increments regardless.

**Why it worked before the reboot:** Under investigation. The ALE must have been in a state where VID 100 frames were forwarded to the CPU (either VLAN-unaware mode, or VID 100 present in the ALE table from a prior session). The exact trigger that puts the ALE into the discarding state after a fresh reboot is not yet identified — `configure-rx-flows.sh` and its `ifconfig eth1 down/up` cycle are suspects.

**Fix — promiscuous mode:**

```bash
ip link set eth1 promisc on
```

In promiscuous mode, the CPSW3G ALE forwards all frames to the CPU regardless of the VLAN table, bypassing the VID 100 discard. This should be added to the startup sequence (e.g. `configure-rx-flows.sh`) after `ifconfig eth1 up`.

**Confirmed result after applying promiscuous mode:**
```
TsnHigh : Tx:  21012 Rx:  21010 RttMin[us]:  1456 RttAvg[us]: 1492 RttMax[us]:  1513 Err:     0 Outlier:      0
TsnHigh : Tx: 1936061 Rx: 1936059 RttMin[us]:  499 RttAvg[us]: 1613 RttMax[us]: 15492 Err:     0 Outlier: 236161
TsnHigh : Tx: 1946067 Rx: 1946064 RttMin[us]:  499 RttAvg[us]: 1614 RttMax[us]: 15492 Err:  3368 Outlier: 238713
```

- `Rx` incrementing — ALE no longer discarding frames ✓
- `Err: 0` initially — descriptor pool clean after reboot, psdata[2] not yet stale
- `Err: 3368` after ~20 min — psdata[2] corruption begins as TCP/IP traffic gradually dirties descriptors in the pool (see psdata[2] Known Issue)
- High `Outlier` count — expected with non-RT host PC mirror (see Task 7)

**Attempted fixes that did NOT work:**

| Command | Result |
|---|---|
| `bridge vlan add dev eth1 vid 100 master` | `Operation not supported` — eth1 not in a Linux bridge |
| `bridge vlan add dev eth1 vid 100 self` | `Operation not supported` — CPSW standalone mode does not support this |

**Why promisc mode bypasses ALE VLAN filtering:** When `IFF_PROMISC` is set, the am65-cpsw-nuss driver sets the ALE port into a mode that forwards all unicast/multicast/broadcast frames to the CPU regardless of VLAN table state.

**Status:** Root cause confirmed — ALE VLAN filtering discards VID 100 frames after reboot. **Fix: `ip link set eth1 promisc on`** before starting reference. Why the ALE initialises into VLAN-filtering mode after a reboot (but not in all prior sessions) is not yet fully understood — the `ifconfig eth1 down/up` cycle in `configure-rx-flows.sh` is the primary suspect for triggering this state.

---

### XDP modes used in mytests/ and mytests-genericl2/

| Node | Binary | `RX_TIMESTAMP` | XDP mode | Why |
|---|---|---|---|---|
| AM62Px `reference` | cross-compiled aarch64 | `ON` | Native ZC (`XdpSkbMode: false`, `XdpZcMode: true`) | ZC required: CPSW3G AF_XDP TX only works in ZC mode; `BPF_F_XDP_DEV_BOUND_ONLY` (set by `RX_TIMESTAMP=ON`) blocks SKB mode |
| Host PC `mirror` | x86 native | `ON` | Native ZC (`XdpSkbMode: false`, `XdpZcMode: true`) | igc (i225) supports native XDP and ZC; `RX_TIMESTAMP=ON` sets `BPF_F_XDP_DEV_BOUND_ONLY` blocking SKB mode; ZC confirmed working |

Both nodes confirmed working with ZC + ZC: reference Rx increments, mirror Rx increments.

SKB mode (`XdpSkbMode: true`) does **not** work on either node when built with `RX_TIMESTAMP=ON` because `BPF_F_XDP_DEV_BOUND_ONLY` (set in `xdp_set_prog_bind_flags`) is incompatible with generic/SKB XDP attachment.

---

## Known conditions