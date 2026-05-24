# PRD: Mac Metrics View V1

## Summary

Mac Metrics View is a native macOS menu bar app for quickly understanding machine resource usage. V1 focuses on CPU, RAM, and network traffic: compact indicators visible near the macOS date/time area, user-controlled visibility for each metric, and a click-through popover for current resource detail. Planned feature extensions, including temperature and opening at login, are specified separately before implementation.

Reference product: OneMenu by CoffeeBreak Software. The relevant inspiration is its native macOS utility feel, lightweight menu bar presence, and organized system monitoring surface. Mac Metrics View V1 intentionally starts much narrower.

## Problem

Mac users often notice the machine getting slow, hot, noisy, memory-constrained, or network-bound before they know why. Activity Monitor is powerful, but opening a full app interrupts the workflow. The user needs a low-friction, always-visible signal that answers: "Is my Mac under CPU, RAM, or network pressure right now?"

## Goals

- Show current CPU usage directly in the macOS menu bar.
- Show current RAM usage directly in the macOS menu bar, formatted in GB.
- Show current network traffic directly in the macOS menu bar, formatted as download and upload throughput.
- Let users choose which metrics appear in the menu bar.
- Let users choose whether menu bar metrics use compact icons or explicit labels, defaulting to icons.
- Open a lightweight popover with more CPU, RAM, and network context.
- Feel native, quiet, and visually aligned with macOS.
- Run locally without telemetry or account setup.
- Keep the app's own CPU and memory footprint low, especially when metrics are hidden.

## Non-goals

- Full Activity Monitor replacement.
- Disk, battery, temperature, or fan monitoring in V1.
- Alerts, automations, history analytics, or cloud sync.
- Cross-platform support.
- Complex customization beyond metric visibility or paid licensing.

## Target Users

- Developers and power users who want a constant CPU signal while working.
- Mac users who want to know whether sluggishness is CPU-related without opening Activity Monitor.
- Users who prefer lightweight menu bar utilities over full dashboards.

## Core User Stories

- As a Mac user, I want to see CPU usage in the menu bar so I can know if my machine is under load.
- As a Mac user, I want to see RAM usage in GB so I can understand memory pressure without doing mental conversion from percentages.
- As a Mac user, I want to see network download and upload throughput so I can tell when connectivity or background transfer activity may be affecting my work.
- As a Mac user, I want to hide metrics I do not care about so the menu bar stays compact.
- As a Mac user, I want compact icons by default so the menu bar stays short, with the option to show labels when I prefer explicit names.
- As a battery-conscious user, I want hidden metrics to stop sampling so the app does not spend resources on values I am not viewing.
- As a developer, I want to click the indicators and see more detail so I can identify whether CPU, RAM, or network load is temporary or sustained.
- As a user, I want the app to feel native and quiet so it does not distract me.
- As a privacy-conscious user, I want all monitoring to happen locally.

## Functional Requirements

- The app launches as a macOS menu bar app.
- The app shows no Dock icon in the default V1 experience.
- The menu bar item displays current CPU usage as a percentage.
- When CPU usage is 80% or higher, the menu bar CPU indicator changes to yellow.
- When CPU usage is 90% or higher, the menu bar CPU indicator changes to red.
- The menu bar item displays current RAM usage in GB.
- RAM color severity is based on percentage of total memory used, while the displayed value remains in GB.
- When RAM usage is 80% or higher, the menu bar RAM indicator changes to yellow.
- When RAM usage is 90% or higher, the menu bar RAM indicator changes to red.
- The menu bar item displays current network traffic as download and upload throughput.
- Network traffic uses byte-rate formatting with adaptive units, for example an SF Symbol network identifier plus `↓ 1.2 MB/s ↑ 84 KB/s` by default or `NET ↓ 1.2 MB/s ↑ 84 KB/s` when labels are enabled.
- Network traffic is derived from local interface byte counters and does not make external network calls.
- Visible CPU, RAM, and network usage update periodically, defaulting to roughly once per second.
- Clicking the menu bar item opens a popover.
- The popover shows current CPU usage, current RAM usage, current network download/upload throughput, and short recent trends for visible metrics.
- The popover includes switches for showing or hiding CPU, RAM, and network metrics.
- The popover includes a display control for choosing metric icons or metric labels in the menu bar.
- Metric icons are used by default.
- Display style choice persists across app launches.
- Visibility choices persist across app launches.
- When a metric is hidden, its menu bar segment and popover detail are hidden.
- When a metric is hidden, its sampler stops and no new history samples are collected for that metric.
- When a hidden metric is shown again, its sampler restarts and displays a fallback value until a valid sample is available.
- If all metrics are hidden, the app keeps a minimal menu bar control visible so the user can reopen the popover, re-enable metrics, or quit.
- The popover includes a Quit action.
- The app handles metric collection failures gracefully and avoids showing invalid values.

## UX Requirements

- The menu bar label must remain compact enough for crowded menu bars.
- CPU, RAM, and network values should be visually separable in the menu bar.
- Hidden metrics should leave no placeholder gap in the menu bar.
- Metric values should be understandable with icons through stable ordering, context-specific SF Symbols, and network direction arrows.
- When labels are enabled, each visible metric segment should include its label: `CPU`, `RAM`, or `NET`.
- Default icons should use SF Symbols that read clearly in light mode and dark mode: `cpu`, `memorychip`, and `network`.
- The elevated/high CPU and RAM color states should be noticeable but not alarm-like; no notification, sound, or animation in V1.
- Network traffic should remain visually quiet in V1; do not add warning colors unless explicit network thresholds are introduced later.
- The popover should use native macOS spacing, typography, and controls.
- The interface should avoid loud colors, unnecessary animation, and marketing-style UI.
- The first version should prioritize clarity over dense diagnostics.

## Technical Requirements

- Language: Swift.
- UI: SwiftUI with AppKit interop for menu bar/status item behavior as needed.
- Platform: native macOS app.
- Minimum macOS target: macOS 14, unless changed during implementation.
- Architecture: isolate CPU, RAM, and network sampling from UI rendering.
- Persistence: use `UserDefaults` for metric visibility and metric identifier display choices.

## Privacy And Security

- No telemetry in V1.
- No external network calls in V1; network monitoring reads local interface counters only.
- No account, login, or cloud sync.
- Collect only local system metrics needed to show currently visible CPU, RAM, and network usage.
- Future input-control utilities must be explicit, time-limited, permission-gated, and must not log, store, or transmit keyboard or mouse events.

## Performance Requirements

- The app should have negligible CPU usage while idle.
- The default sampling interval should be no faster than needed for a glanceable CPU indicator.
- The UI should avoid layout jitter when CPU, RAM, or network values change.
- Changing metric identifier display should update the menu bar immediately without restarting samplers.
- Hidden metrics should not run their samplers, timers, native metric reads, formatters, or history appends.
- Process-level detail, if added in V1, should be sampled carefully to avoid extra load.

## Acceptance Criteria

- Launching the app adds a CPU indicator to the macOS menu bar near the system status area.
- Launching the app adds a RAM indicator in GB to the macOS menu bar near the CPU indicator.
- Launching the app adds a network traffic indicator with download and upload throughput near the CPU/RAM indicators.
- CPU, RAM, and network indicators update without requiring user interaction.
- Clicking the indicator opens a popover with CPU, RAM, and network detail.
- The popover lets the user toggle CPU, RAM, and network visibility independently.
- The popover lets the user choose menu bar metric icons or labels independently from metric visibility.
- Metric icons are used on first launch.
- With icons selected, visible metrics render with context-specific SF Symbols and without `CPU`, `RAM`, or `NET` text.
- With labels selected, visible metrics render with `CPU`, `RAM`, and `NET` text.
- Changing metric identifier display does not start, stop, or restart samplers.
- Turning a metric off removes it from the menu bar and popover detail.
- Turning a metric off stops metric collection for that metric.
- Turning a metric back on restarts metric collection and shows a fallback value until a valid sample is available.
- Visibility choices are restored after quitting and relaunching the app.
- Metric identifier display choice is restored after quitting and relaunching the app.
- If CPU, RAM, and network are all hidden, a minimal menu bar control remains available for reopening the popover.
- The popover contains a Quit action that exits the app and removes the menu bar item.
- The app does not show a Dock icon during normal operation.
- The app continues to behave correctly in light and dark mode.
- CPU values are formatted as valid percentages and never show NaN or negative values.
- CPU values below 80% use the normal menu bar text color, values from 80% to below 90% use yellow, and values at or above 90% use red.
- RAM values are formatted in GB and never show NaN, negative values, or percentages in the menu bar.
- RAM values below 80% of total memory use the normal menu bar text color, values from 80% to below 90% use yellow, and values at or above 90% use red.
- Network traffic values are formatted as byte rates per second and never show NaN, negative values, or raw counter totals in the menu bar.
- Network traffic shows separate download and upload rates.

## Open Questions

- Resolved: the default menu bar uses SF Symbol plus value, with a labels option for explicit text.
- Should RAM display use one decimal place (`12.4 GB`) or whole GB (`12 GB`)?
- Should network traffic use `↓ 1.2 MB/s ↑ 84 KB/s`, `↓ 1.2 ↑ 0.1 MB/s`, or a more compact direction-icon format?
- Should V1 include top CPU processes in the popover, or reserve that for a later minor release?
- Resolved for planning: opening at login is a later feature with an explicit user toggle, not part of V1.
- What app name should be user-facing: Mac Metrics View, Metrics View, or another name?

## Future Roadmap

- V1.1: optional temperature metric with Portuguese thermal states, visibility toggle, sampler lifecycle control, and Celsius display when reliably available.
- V1.2: optional `Abrir ao inicializar` preference using native macOS login item APIs.
- V1.3: top CPU processes and configurable refresh interval.
- V1.4: CPU history chart and sustained-load indication.
- V2: disk metrics and richer network detail.
- Later: richer preferences, exportable diagnostics, and optional notifications.
