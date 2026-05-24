---
name: macos-app-design-expert
description: Design, critique, and refine expert-level native macOS app experiences for Mac Metrics View and similar SwiftUI/AppKit applications. Use when an agent needs to make UI/UX decisions, redesign screens, review visual polish, define interaction patterns, improve menu bar or popover ergonomics, align with macOS Human Interface Guidelines, choose typography/color/spacing, or verify native-feeling macOS behavior.
---

# macOS App Design Expert

## Purpose

Use this skill to make Mac Metrics View feel like a polished macOS utility: quiet, native, glanceable, spatially disciplined, and respectful of the user's menu bar attention.

This is a design skill, not a branding or marketing skill. Prefer product surfaces that look like they belong beside System Settings, Control Center, Activity Monitor, and first-party menu bar utilities.

## Core Principles

- Native restraint: use system controls, system materials, SF Symbols, semantic colors, and standard typography before custom styling.
- Glance first: the menu bar item should answer one question fast; the popover may explain the answer.
- Stable layout: metric values must not cause jitter as digits, units, or labels change.
- Quiet severity: color should signal state without feeling like an alert unless the product has explicit alert behavior.
- Local trust: avoid designs that imply telemetry, accounts, cloud sync, or background surveillance.
- Energy awareness: do not design UI that requires expensive sampling, constant animation, or dense live rendering to feel useful.
- Accessibility by default: support VoiceOver labels, keyboard navigation, contrast, Reduce Motion, light/dark mode, and dynamic text where practical.

## Design Workflow

1. Read `docs/PRD.md` and `docs/TECH_DECISIONS.md` before changing product-facing UI.
2. Identify the surface: menu bar item, popover, preferences, onboarding, error state, or empty state.
3. State the primary user question for that surface in one sentence.
4. Choose the smallest native interaction that answers it.
5. Design the menu bar representation before the popover details.
6. Keep controls familiar: switches for binary visibility, segmented controls for modes, buttons for commands, disclosure only for optional detail.
7. Check all value states: loading, unavailable, normal, elevated, high, hidden, all metrics hidden, and stale sample.
8. Verify light mode, dark mode, narrow menu bar space, and longer localized strings if UI text changes.

## Menu Bar Guidance

- Prefer compact text plus SF Symbols only when icons improve scanning.
- Use monospaced digits for changing numeric values.
- Keep metric order stable: CPU, RAM, Network unless the PRD changes it.
- Hide labels by default if the PRD says so; when labels are enabled, keep them short: `CPU`, `RAM`, `NET`.
- Avoid graphs, badges, dense separators, and multi-color decoration in the menu bar unless the value remains legible at menu bar height.
- Preserve a minimal affordance when all metrics are hidden so the user can reopen the popover.
- Prevent width thrash by reserving predictable widths for values whose character count changes frequently.

## Popover Guidance

- Treat the popover as a compact utility panel, not a dashboard page.
- Use a fixed or tightly bounded width; avoid layouts that stretch into wide-window thinking.
- Put visibility controls near the top when metric visibility is a core workflow.
- Group each visible metric with current value, short trend, and only the most useful detail rows.
- Use system spacing rhythm: compact vertical groups, clear dividers, and left-aligned labels.
- Keep destructive or app-exit commands visually secondary and separated from metric controls.
- Prefer progressive detail over dense tables for V1.

## Visual System Defaults

- Typography: system font; use `.headline`, `.callout`, `.caption`, and monospaced digits where values update.
- Color: semantic colors first (`.primary`, `.secondary`, `.tertiary`, `.accentColor`); custom severity colors only when thresholds are product requirements.
- Materials: use native popover/window backgrounds; avoid custom panels that fight macOS vibrancy.
- Shape: use native control shapes; avoid card stacks and rounded marketing panels inside utility popovers.
- Motion: no decorative animation. Use subtle transitions only if they clarify state and respect Reduce Motion.

## Review Checklist

- Does the first glance answer whether the Mac is under CPU, RAM, or network pressure?
- Can the user restore hidden metrics without guessing?
- Are changing values stable, readable, and aligned?
- Does the UI work in light and dark mode without custom contrast hacks?
- Are controls native enough that no help text is needed?
- Are there any visuals that imply product scope not present in V1?
- Would this feel calm if it updated every second for an entire workday?

## References

Read `references/macos-utility-design.md` when redesigning menu bar, popover, or preference surfaces. Read `references/accessibility-and-polish.md` when reviewing visual quality, accessibility, or release readiness.
