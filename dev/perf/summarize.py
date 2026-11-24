#!/usr/bin/env python3
"""Median [min-max] over repeated dev/run_perf.sh runs.   summarize.py before.txt after.txt"""
import re, sys, statistics as st

def parse(path):
    runs, cur, mode = [], None, ""
    for line in open(path):
        if line.startswith("######## run"):
            cur = {}; runs.append(cur)
        elif line.startswith("--- "):
            mode = line[4:].strip().split()[0]
        elif "[bench]" in line and "frame ms" in line and cur is not None:
            m = re.search(r"\[bench\] (\S+) \| frames=(\d+) \| frame ms avg ([\d.]+) p50 ([\d.]+) p95 ([\d.]+) p99 ([\d.]+) max ([\d.]+) \| frames >20ms: (\d+), >33ms: (\d+)", line)
            if m:
                cur[(mode, m.group(1))] = dict(zip(["frames", "avg", "p50", "p95", "p99", "max", "gt20", "gt33"], map(float, m.groups()[1:])))
        elif "micro" in line and "us/call" in line and cur is not None:
            m = re.search(r"micro (.+?)\s+([\d.]+) us/call", line)
            if m:
                cur[("micro", m.group(1).strip())] = {"us": float(m.group(2))}
    return runs

def agg(runs, key, field):
    vals = [r[key][field] for r in runs if key in r]
    if not vals:
        return None
    return st.median(vals), min(vals), max(vals)

def fmt(a, d=2):
    return "-" if a is None else ("%.*f [%.*f-%.*f]" % (d, a[0], d, a[1], d, a[2]))

b, a = parse(sys.argv[1]), parse(sys.argv[2])
keys = sorted({k for r in b + a for k in r})
print("| scenario | mode | metric | before (Update 1) | after |")
print("|---|---|---|---|---|")
names = {"avg": "frame avg ms", "p95": "frame p95 ms", "p99": "frame p99 ms", "max": "max hitch ms", "gt33": "frames >33 ms (of N)"}
for k in keys:
    if k[0] == "micro":
        print("| %s | script | µs per call | %s | %s |" % (k[1], fmt(agg(b, k, "us"), 1), fmt(agg(a, k, "us"), 1)))
        continue
    for f in ["avg", "p95", "max", "gt33"]:
        fb, fa = agg(b, k, f), agg(a, k, f)
        if fb is None and fa is None:
            continue
        nb = agg(b, k, "frames"); na = agg(a, k, "frames")
        extra = ""
        if f == "gt33":
            extra = " of ~%d / ~%d" % (nb[0] if nb else 0, na[0] if na else 0)
        print("| %s | %s | %s | %s | %s%s |" % (k[1], k[0], names[f], fmt(fb, 1 if f == "gt33" else 2), fmt(fa, 1 if f == "gt33" else 2), extra))
