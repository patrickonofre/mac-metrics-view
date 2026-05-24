---
name: menu-bar-product-prd
description: Define, refine, and review product scope for Mac Metrics View, a native macOS menu bar resource monitor. Use when an agent needs to create or update PRDs, roadmap slices, acceptance criteria, feature tradeoffs, user stories, non-goals, launch criteria, or product decisions for CPU, memory, disk, network, and other system-monitoring experiences.
---

# Menu Bar Product PRD

## Overview

Use this skill to keep the product small, native, and useful. Scope each version around glanceable menu bar signals plus a focused popover detail view.

## PRD Workflow

1. Start from the user problem, not the metric list.
2. Define the menu bar signal first. It is the product's primary surface.
3. Define the popover details second. Include only the data that explains the menu bar signal.
4. Capture non-goals aggressively so the app does not become a clone of Activity Monitor in V1.
5. Write acceptance criteria that can be verified by launching the app on macOS.
6. Keep privacy, performance, and battery impact as first-class requirements.

## Product Principles

- Native first: it should feel like it belongs near the macOS date/time area.
- Glanceable: the status item answers CPU and RAM pressure questions quickly.
- Quiet: no alerts or animations in V1 unless explicitly requested.
- Local: no external accounts, cloud sync, or telemetry in V1.
- Lightweight: the app must not create the performance anxiety it is meant to reduce.

## Reference App Notes

OneMenu is a useful reference for positioning: a native, lightweight macOS utility with system monitoring as one part of a broader menu bar workflow. Do not copy its product breadth for V1. Borrow the values: minimal UI, native feel, useful system stats, and a paid-quality level of polish.

## References

Read `references/prd-template.md` when creating or revising PRDs.
