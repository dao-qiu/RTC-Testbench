#!/usr/bin/env python3
"""
Plot RTT time series from RTC-Testbench reference log.
Extracts per-second RTT avg/min/max and total TX/RX from INFO lines.
Usage: python3 plot_rtt_timeseries.py [reference_vid100.log]
"""

import sys
import re
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

log_file = sys.argv[1] if len(sys.argv) > 1 else "reference_vid100.log"

# --- Parse INFO lines ---
timestamps, tx_vals, rx_vals, avg_vals, min_vals, max_vals = [], [], [], [], [], []

with open(log_file) as f:
    for line in f:
        if "[INFO]" not in line:
            continue
        ts  = re.search(r'^\[([0-9.]+)\]',            line)
        m_tx  = re.search(r'TsnHighSent=(\d+)',        line)
        m_rx  = re.search(r'TsnHighReceived=(\d+)',    line)
        m_min = re.search(r'TsnHighRttMin=(\d+)',      line)
        m_max = re.search(r'TsnHighRttMax=(\d+)',      line)
        m_avg = re.search(r'TsnHighRttAvg=([\d.]+)',   line)
        if not all([ts, m_tx, m_rx, m_min, m_max, m_avg]):
            continue
        rx = int(m_rx.group(1))
        if rx == 0:
            continue   # skip warmup lines before first frame received
        timestamps.append(float(ts.group(1)))
        tx_vals.append(int(m_tx.group(1)))
        rx_vals.append(rx)
        min_vals.append(int(m_min.group(1)))
        max_vals.append(int(m_max.group(1)))
        avg_vals.append(float(m_avg.group(1)))

if not timestamps:
    print("No valid data found in log file.")
    sys.exit(1)

# Normalise time axis to seconds from first received frame
t0 = timestamps[0]
elapsed = [t - t0 for t in timestamps]

# Final cumulative stats from last line
tx_total  = tx_vals[-1]
rx_total  = rx_vals[-1]
rtt_min   = min_vals[-1]
rtt_max   = max_vals[-1]
rtt_avg   = avg_vals[-1]
duration  = elapsed[-1]

# --- Plot ---
fig, ax = plt.subplots(figsize=(14, 6))

ax.fill_between(elapsed, min_vals, max_vals, alpha=0.15, color='steelblue', label='RTT min–max band')
ax.plot(elapsed, avg_vals, color='steelblue', linewidth=1.2, label='RTT avg (running)')
ax.axhline(rtt_min, color='green',  linestyle='--', linewidth=1.0, label=f'Overall min {rtt_min} µs')
ax.axhline(rtt_max, color='red',    linestyle='--', linewidth=1.0, label=f'Overall max {rtt_max} µs')
ax.axhline(rtt_avg, color='orange', linestyle='--', linewidth=1.0, label=f'Overall avg {rtt_avg:.1f} µs')

ax.set_xlabel('Elapsed time (s)', fontsize=12)
ax.set_ylabel('RTT (µs)', fontsize=12)
ax.set_title('TSNHigh RTT over Time — AM62Px XDP ZC vs Host PC', fontsize=13)
ax.xaxis.set_major_locator(ticker.MultipleLocator(60))
ax.grid(linestyle='--', alpha=0.4)
ax.legend(fontsize=9, loc='upper left')

stats_text = (
    f"TX packets : {tx_total:,}\n"
    f"RX packets : {rx_total:,}\n"
    f"RTT min    : {rtt_min} µs\n"
    f"RTT max    : {rtt_max} µs\n"
    f"RTT avg    : {rtt_avg:.1f} µs\n"
    f"Duration   : {duration:.0f} s"
)
ax.text(0.98, 0.97, stats_text,
        transform=ax.transAxes, fontsize=9, verticalalignment='top',
        horizontalalignment='right', family='monospace',
        bbox=dict(boxstyle='round', facecolor='white', alpha=0.85))

plt.tight_layout()
out = "rtt_timeseries.png"
plt.savefig(out, dpi=150)
print(f"Saved {out}")
print(stats_text)
