#!/usr/bin/env python3
import sys
import matplotlib.pyplot as plt

rtts, counts = [], []
with open(sys.argv[1] if len(sys.argv) > 1 else "histogram.txt") as f:
    for line in f:
        line = line.strip()
        if not line or not line[0].isdigit():
            continue
        parts = line.split()
        rtt = int(parts[0].rstrip(':'))
        count = int(parts[1])   # TsnHigh column — adjust index for other traffic classes
        if count > 0:
            rtts.append(rtt)
            counts.append(count)

plt.figure(figsize=(14, 5))
plt.bar(rtts, counts, width=1, color='steelblue')
plt.xlabel('RTT (µs)')
plt.ylabel('Frame count')
plt.title('TSNHigh RTT Distribution')
plt.tight_layout()
plt.savefig('histogram.png', dpi=150)
print(f"Saved histogram.png — {sum(counts)} samples across {len(rtts)} bins")
