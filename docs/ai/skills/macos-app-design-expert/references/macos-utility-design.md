# macOS Utility Design Reference

## Positioning

Mac Metrics View is a lightweight utility. Its design should feel closer to a first-party menu bar extra than to a web dashboard.

Good reference qualities:

- Compact, confident hierarchy.
- Clear values before explanations.
- Native switches, buttons, dividers, and type.
- Calm severity treatment.
- Minimal decoration.

Avoid:

- Hero sections, marketing copy, nested cards, large illustrations, and empty visual flourish.
- Dense analytics dashboards that make a short-lived popover feel like a full app.
- Custom controls that make simple settings feel unfamiliar.
- Bright gradients, glassy novelty surfaces, or brand-heavy color systems.

## Surface Patterns

### Menu Bar Item

Use the menu bar item as a signal, not a report.

Recommended V1 forms:

- Labels hidden: `18%  12.4 GB  ↓ 1.2 MB/s ↑ 84 KB/s`
- Labels shown: `CPU 18%  RAM 12.4 GB  NET ↓ 1.2 MB/s ↑ 84 KB/s`
- All metrics hidden: a small app icon or compact text affordance that opens the popover.

Design requirements:

- Use stable ordering.
- Use monospaced digits.
- Keep separators subtle.
- Avoid red/yellow for network unless thresholds are explicitly defined.
- Ensure severity color never obscures value readability.

### Popover

The popover should answer:

1. What is happening now?
2. Is it temporary or sustained?
3. What can I change about what appears in the menu bar?

Suggested hierarchy:

1. Visibility controls.
2. Optional label toggle.
3. Current metric groups.
4. Detail rows.
5. Quit or secondary app command.

Metric group anatomy:

- Header: metric name and current value.
- Trend: tiny sparkline or recent min/max, not a full chart.
- Detail rows: only values that explain the headline.

### Preferences

If preferences become a separate surface, keep them native and sparse:

- General: show labels, visible metrics, launch at login if added.
- Sampling: refresh interval only if the product exposes it.
- Privacy: local-only statement only where it clarifies trust.

Do not add a preference window just to host three switches if the popover can do the job.

## Layout Rules

- Prefer aligned label/value grids for metric details.
- Keep metric values right-aligned or trailing-aligned when comparing rows.
- Use `Spacer()` carefully; avoid comically stretched utility controls.
- Use fixed widths only where they prevent jitter or preserve compactness.
- Keep scroll views reserved for content that can actually exceed the popover height.

## State Design

Design each metric for:

- Waiting for first sample: show `--` or an unobtrusive placeholder.
- Valid sample: show formatted value.
- Collection failure: show unavailable state without alarming copy.
- Hidden: remove metric detail entirely.
- Stale value: avoid presenting it as live; consider secondary timestamp or muted value.

## Copy

- Use short labels: `CPU`, `RAM`, `Network`, `Download`, `Upload`, `Updated`.
- Avoid explanatory paragraphs in the product UI.
- Use command verbs only where the action is clear: `Quit Mac Metrics View`.
- Avoid "dashboard", "insights", or "analytics" language for V1.
