#!/usr/bin/env python3
"""
Plot RTT histogram from RTC-Testbench output.
Usage: python3 plot_rtt.py <histogram.txt> [reference_vid100.log] [--duration SECONDS]
  - If log file is omitted, min/max/avg are derived from histogram.txt.
  - If log file is provided, TX/RX counts and min/max/avg are taken from the log.
  - --duration SECONDS  optional runtime duration to annotate on the plot (e.g. 60, 1800)
"""

import sys
import re
import argparse
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

# --- Argument parsing ---
parser = argparse.ArgumentParser(description='Plot RTC-Testbench RTT histogram.')
parser.add_argument('hist_file',           help='histogram.txt from RTC-Testbench')
parser.add_argument('log_file', nargs='?', help='reference_vid100.log (optional)')
parser.add_argument('--duration', type=str, default=None,
                    metavar='DURATION',
                    help='Runtime duration to annotate (e.g. 1049s, 17m, 1h, 1h30m, 1m30s)')
parser.add_argument('--title', type=str, default='TSNHigh RTT Distribution',
                    help='Plot title (default: "TSNHigh RTT Distribution")')
parser.add_argument('--output', type=str, default='rtt_histogram.png',
                    help='Output filename (default: rtt_histogram.png)')
args = parser.parse_args()

hist_file = args.hist_file
log_file  = args.log_file

# --- Parse duration string into total seconds ---
def parse_duration(s):
    """Accept formats: 60, 60s, 17m, 1h, 1h30m, 1m30s, 1h30m20s"""
    s = s.strip()
    if re.fullmatch(r'[\d.]+', s):
        return float(s)   # plain number → seconds
    total = 0.0
    for value, unit in re.findall(r'([\d.]+)([hms])', s):
        v = float(value)
        if   unit == 'h': total += v * 3600
        elif unit == 'm': total += v * 60
        elif unit == 's': total += v
    if total == 0.0:
        raise argparse.ArgumentTypeError(f"Unrecognised duration format: '{s}'. Use e.g. 60s, 17m, 1h, 1h30m20s")
    return total

duration = parse_duration(args.duration) if args.duration is not None else None

# --- Parse histogram.txt (TsnHigh = column 2) ---
rtts, counts = [], []
overflow = underflow = 0

with open(hist_file) as f:
    for line in f:
        line = line.strip()
        if re.match(r'^\d{8}:', line):
            parts = line.split()
            rtt   = int(parts[0].rstrip(':'))
            count = int(parts[1])
            if count > 0:
                rtts.append(rtt)
                counts.append(count)
        elif line.startswith("Overflow:"):
            overflow  = int(line.split()[1])
        elif line.startswith("Underflow:"):
            underflow = int(line.split()[2] if len(line.split()) > 2 else line.split()[1])

# --- Derive min/max/avg from histogram bins ---
tx = rx = None
rtt_min = rtts[0]  if rtts else None
rtt_max = rtts[-1] if rtts else None
total_binned = sum(counts)
rtt_avg = (sum(r * c for r, c in zip(rtts, counts)) / total_binned) if total_binned else None

# --- Override with log file values if provided ---
if log_file:
    with open(log_file) as f:
        for line in f:
            if "[INFO]" not in line:
                continue
            m_tx  = re.search(r'TsnHighSent=(\d+)',     line)
            m_rx  = re.search(r'TsnHighReceived=(\d+)', line)
            m_min = re.search(r'TsnHighRttMin=(\d+)',   line)
            m_max = re.search(r'TsnHighRttMax=(\d+)',   line)
            m_avg = re.search(r'TsnHighRttAvg=([\d.]+)', line)
            if m_tx and m_rx and m_min and m_max and m_avg:
                tx      = int(m_tx.group(1))
                rx      = int(m_rx.group(1))
                rtt_min = int(m_min.group(1))
                rtt_max = int(m_max.group(1))
                rtt_avg = float(m_avg.group(1))

# --- Plot ---
fig, ax = plt.subplots(figsize=(14, 6))
ax.bar(rtts, counts, width=1, color='steelblue', label='TsnHigh RTT')

ax.set_xlabel('RTT (µs)', fontsize=12)
ax.set_ylabel('Frame count', fontsize=12)
ax.set_title(args.title, fontsize=13)
ax.xaxis.set_major_locator(ticker.MultipleLocator(500))
ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, _: f'{int(x):,}'))
ax.grid(axis='y', linestyle='--', alpha=0.4)

# Overlay lines for min/max/avg
if rtt_min is not None:
    ax.axvline(rtt_min, color='green',  linestyle='--', linewidth=1.2, label=f'Min {rtt_min} µs')
    ax.axvline(rtt_max, color='red',    linestyle='--', linewidth=1.2, label=f'Max {rtt_max} µs')
    ax.axvline(rtt_avg, color='orange', linestyle='--', linewidth=1.2, label=f'Avg {rtt_avg:.1f} µs')

# Stats annotation box
stats_lines = []
if tx      is not None: stats_lines.append(f'TX packets : {tx:,}')
if rx      is not None: stats_lines.append(f'RX packets : {rx:,}')
if rtt_min is not None: stats_lines.append(f'RTT min    : {rtt_min} µs')
if rtt_max is not None: stats_lines.append(f'RTT max    : {rtt_max} µs')
if rtt_avg is not None: stats_lines.append(f'RTT avg    : {rtt_avg:.1f} µs')
if overflow:            stats_lines.append(f'Overflow   : {overflow:,} frames (>{rtts[-1] if rtts else "?"} µs)')
if underflow:           stats_lines.append(f'Underflow  : {underflow:,} frames')
if duration is not None:
    m, s = divmod(int(duration), 60)
    h, m = divmod(m, 60)
    dur_str = f'{h}h {m}m {s}s' if h else (f'{m}m {s}s' if m else f'{s}s')
    stats_lines.append(f'Duration   : {dur_str} ({duration:.0f}s)')

ax.text(0.98, 0.97, '\n'.join(stats_lines),
        transform=ax.transAxes, fontsize=9, verticalalignment='top',
        horizontalalignment='right', family='monospace',
        bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))

ax.legend(fontsize=9)
plt.tight_layout()

out = args.output
plt.savefig(out, dpi=150)
print(f"Saved {out}")
print('\n'.join(stats_lines))
