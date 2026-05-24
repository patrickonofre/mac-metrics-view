# Spec-Driven Dev: Professional Popover UI Polish

## Purpose

This document defines one focused feature for later implementation: refine the Mac Metrics View popover UI from a functional prototype into a polished native macOS utility panel.

The feature is design-only at the product behavior level. It must not change metric sampling, persistence, thresholds, formatter behavior, or menu bar visibility rules except where visual presentation requires safer layout constraints.

## Screenshot Analysis

Observed UI issues from the current popover:

- The top toggle row is too wide for the popover; `Network` wraps into two lines and makes the first row feel broken.
- Switches dominate the header visually, competing with the metric readings instead of feeling like settings.
- The popover is tall and dashboard-like for a menu bar utility.
- Metric sections have inconsistent rhythm: CPU and RAM read as separate panels, while Network blends into the detail list below.
- Sparkline height and spacing consume more attention than the values they support.
- The details grid is useful but visually detached from the metric sections it explains.
- The quit command is correctly secondary, but the surrounding bottom area feels heavy because the content above is too stretched.
- The menu bar item is compact and useful, but elevated RAM color is very prominent; the popover should explain that state calmly.

## Feature Scope

### In Scope

- Redesign `PopoverView` layout for a professional native macOS utility feel.
- Make metric visibility and display controls compact, aligned, and impossible to wrap.
- Improve hierarchy for CPU, RAM, and Network sections.
- Keep current value, trend, and detail information readable at a glance.
- Reduce vertical bulk while preserving all current information.
- Add explicit visual treatment for elevated/high CPU or RAM in the popover if already available from existing state.
- Improve empty/all-hidden state so the user can easily restore metrics.
- Improve accessibility labels for controls, metric values, and decorative sparklines where needed.
- Preserve light/dark mode through semantic system colors.

### Out Of Scope

- New metrics.
- New sampler behavior.
- New formatter rules.
- New persistence keys.
- New preferences window.
- Menu bar interaction model changes.
- Alerts, notifications, or animated warning states.
- Long-term charts or process lists.

## Design Goal

The popover should answer three questions quickly:

1. What is happening now?
2. Is it normal, elevated, or high?
3. Which values are shown in the menu bar?

The result should feel closer to a first-party macOS utility popover than to a compact web dashboard.

## Proposed UX

### Popover Size

- Target width: 340-360 pt.
- Target height: content-driven with a practical maximum around 440-480 pt.
- Avoid a fixed tall 520 pt layout unless content truly needs it.
- Use scrolling only if content exceeds the maximum height.

### Top Controls

Replace the current wrapping horizontal toggle row with a compact settings area.

Required controls:

- CPU visibility switch.
- RAM visibility switch.
- Network visibility switch.
- Display segmented control for Icon/Label.

Requirements:

- No control label may wrap.
- Controls must remain reachable without scrolling.
- Switches should align consistently.
- The top area should read as settings, not as the primary content.
- If all metrics are hidden, the controls remain visible and the content area shows a recovery state.

Recommended layout:

- A compact two-column grid, or
- A vertical native settings list with label left and switch right.

### Metric Sections

Each visible metric should have one compact section with:

- Metric name.
- Current value.
- Optional severity indicator for CPU/RAM.
- Sparkline.
- Detail rows directly associated with that metric when applicable.

Recommended grouping:

- CPU section: current total, sparkline, User/System/Idle detail rows.
- RAM section: current used GB, sparkline, Total/Used detail rows.
- Network section: current download/upload, sparkline, Download/Upload detail rows.

Requirements:

- Current values must use monospaced digits.
- Detail labels must use secondary color.
- Detail values must align cleanly.
- Sparkline should be subtle and decorative.
- Network should not use warning colors in V1.

### Severity

CPU and RAM already have product thresholds:

- Normal below 80%.
- Elevated from 80% to below 90%.
- High at 90% or above.

Popover treatment:

- Normal: primary value text.
- Elevated: calm warning accent on value or small indicator.
- High: red accent on value or small indicator.
- Do not add notification-like styling, pulsing, sound, or animation.

### Empty State

When all metrics are hidden:

- Keep the visibility controls available.
- Show a compact empty state in the content area.
- Copy should be short and action-oriented.
- Do not start hidden metric samplers.

Suggested copy:

- Title: `No Metrics Visible`
- Body: `Turn on CPU, RAM, or Network to show live values.`

### Quit Action

- Keep `Quit Mac Metrics View` separated from the main metric content.
- Use secondary visual emphasis.
- Do not make it the most prominent control in the popover.

## Acceptance Criteria

- `Network` no longer wraps in the controls area.
- The popover presents all controls and visible metrics without feeling like a full dashboard.
- CPU, RAM, and Network each have consistent section structure.
- CPU detail rows stay visually tied to CPU, RAM rows to RAM, and network rows to Network.
- Values use monospaced digits.
- Sparkline visuals are quieter than the current metric value.
- The UI remains readable in light and dark mode.
- Turning metrics on/off preserves existing sampler lifecycle behavior.
- Changing Icon/Label preserves existing menu bar display behavior.
- All hidden metrics produce a clear recovery state without starting samplers.
- The Quit action remains available and visually secondary.
- No new product scope appears in the UI.

## Non-Functional Requirements

- UI updates every second must not cause visible layout jitter.
- No custom color should reduce contrast in light or dark mode.
- The redesigned popover should use native SwiftUI/AppKit controls where practical.
- Decorative trends must not become accessibility noise.
- The feature should be covered by focused snapshot/manual visual checks after implementation.
