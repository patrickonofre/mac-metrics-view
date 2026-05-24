---
name: system-metrics-cpu
description: Collect, model, display, and validate macOS CPU and RAM usage metrics for Mac Metrics View. Use when an agent needs to implement CPU/RAM samplers, process CPU ranking, refresh intervals, metric formatting, severity colors, energy/performance checks, tests for resource calculations, or user-facing resource visualizations in the native macOS menu bar app.
---

# System Metrics CPU And RAM

## Overview

Use this skill when working on CPU or RAM data. Keep samplers reliable, lightweight, and separated from the UI so the menu bar can update without doing expensive work on every render.

## Metric Scope For V1

- Overall CPU usage percentage.
- RAM usage displayed in GB.
- RAM severity based on percent of total memory used.
- Optional split between user/system/idle when available.
- Top CPU-consuming processes in the popover, not necessarily in the menu bar label.
- Short rolling history for a tiny trend chart or recent min/max.

## Collection Guidance

1. Prefer native macOS APIs over shelling out to `top` or `ps` in production code.
2. Calculate overall CPU usage from deltas between samples, not from a single cumulative snapshot.
3. Use a default refresh interval of 1 second or slower.
4. Keep process scanning less frequent than overall CPU sampling if it becomes expensive.
5. Make data types explicit: timestamp, total percent, user percent, system percent, idle percent, per-process values.
6. Clamp and format values defensively. UI should not show negative values, NaN, or impossible percentages.

## Product Constraints

- The monitor must not become the source of noticeable CPU load.
- The menu bar values should answer "is my Mac busy or memory constrained right now?" at a glance.
- CPU usage should be exposed to the UI as visual severity: normal below 80%, elevated/yellow from 80% to below 90%, and high/red at 90% or higher.
- RAM usage should use the same visual severity thresholds, but the menu bar display must remain GB instead of percent.
- Detailed process information belongs in the popover, where there is room for names and values.
- Avoid collecting private or unnecessary data. No telemetry leaves the machine in V1.

## References

Read `references/cpu-sampling.md` before implementing or changing CPU sampling logic. Read `references/ram-sampling.md` before implementing or changing RAM sampling, formatting, or severity logic.
