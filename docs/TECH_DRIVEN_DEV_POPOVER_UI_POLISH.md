# Tech-Driven Dev: Professional Popover UI Polish

## Purpose

This document defines the technical implementation plan for one future feature: professional polish of the existing Mac Metrics View popover UI.

The implementation must stay local to UI composition and presentation behavior. It should not alter CPU, RAM, or network sampling logic.

## Current Implementation Notes

Relevant files:

- `MacMetricsView/UI/PopoverView.swift`
- `MacMetricsView/UI/SparklineView.swift`
- `MacMetricsView/App/StatusItemController.swift`

Current technical issues visible in the screenshot:

- `visibilityControls` is a single `HStack` with three `Toggle` views, each using `.frame(maxWidth: .infinity)`, which allows awkward distribution and label wrapping.
- `compactToggle("Network")` can wrap because the switch and label compete inside a narrow third column.
- `PopoverView` uses a fixed `360 x 520` frame even when the content does not need that much vertical space.
- One shared `details` grid appears after all metric sparklines, so details are not visually owned by their metrics.
- `metricHeader` uses title-style rounded semibold values, which makes the panel feel heavier than a utility popover.
- `SparklineView` is visually dominant relative to the compact value summaries.

## Implementation Strategy

Refactor the popover into small view components without changing state ownership.

Recommended components:

- `PopoverView`
- `MetricVisibilityControls`
- `MetricSection`
- `MetricDetailGrid`
- `EmptyMetricsState`

Keep the existing `CPUState` dependency. Do not introduce a view model unless implementation becomes meaningfully simpler.

## Layout Contract

### Popover Frame

In `StatusItemController.configurePopover()`:

- Keep popover width in the 340-360 pt range.
- Reduce target height from 520 pt to a tighter content-driven size where possible.
- If using `NSPopover.contentSize`, choose a maximum size that supports all three metrics without excessive empty space.

In `PopoverView`:

- Prefer `.frame(width:)` plus bounded height over a hard fixed height.
- Use `ScrollView` only around metric content, not around the top controls or quit action.

### Controls

Replace the current `HStack` toggle implementation.

Preferred implementation:

- Use compact rows that keep switches and the Icon/Label display control within the popover width.
- Each cell contains a label and native switch that cannot wrap.
- Apply `.lineLimit(1)` to labels.
- Use fixed minimum label widths only if necessary.

Alternative implementation:

- Use a vertical settings list with `HStack { Text(label); Spacer(); Toggle("", isOn:) }`.

Rules:

- Keep native `.switch` toggle style.
- Do not use custom toggle drawings.
- Do not let any toggle label wrap.
- Keep Icon/Label as a display setting, not a metric.

### Metric Sections

Move details into each metric section:

- CPU section includes CPU header, CPU sparkline, User/System/Idle rows.
- RAM section includes RAM header, RAM sparkline, Total/Used rows.
- Network section includes Network header, network sparkline, Download/Upload rows.

Use one reusable `MetricSection` with optional detail content.

Suggested section anatomy:

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack(alignment: .firstTextBaseline) {
        Text(title)
        Spacer()
        Text(value)
    }

    SparklineView(values: values, height: 22)

    MetricDetailGrid(rows: rows)
}
```

Technical requirements:

- Apply `.monospacedDigit()` to value text and detail values.
- Use `.callout.weight(.semibold)` or smaller for section titles.
- Use `.body.weight(.semibold)` or smaller for metric values so the utility stays compact.
- Use `.foregroundStyle(.secondary)` for detail labels.
- Use `Divider()` between sections rather than card backgrounds.

### Severity Styling

Use existing state-derived styles where possible:

- CPU: `state.menuBarTextStyle`
- RAM: `state.ramMenuBarTextStyle`

Add a small helper in `PopoverView` or a private extension to map existing severity style to SwiftUI color.

Rules:

- Normal values use `.primary`.
- Elevated values use a warning-like yellow that remains readable.
- High values use red.
- Network values stay `.primary`.
- Do not add animation for severity changes.

### Empty State

When `state.hasVisibleMetric == false`:

- Show `EmptyMetricsState`.
- Do not show empty metric sections.
- Keep top controls and quit button visible.

Suggested component:

```swift
private struct EmptyMetricsState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No Metrics Visible")
                .font(.headline)
            Text("Turn on CPU, RAM, or Network to show live values.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
```

## Accessibility

Implementation should include:

- `.accessibilityLabel` for each metric section value.
- `.accessibilityHidden(true)` for decorative sparklines unless a concise summary is added.
- Switch labels that remain explicit for VoiceOver.
- No reliance on color alone for severity if adding severity text is practical.

Example:

```swift
Text(value)
    .accessibilityLabel("\(title), \(value)")
```

## Testing And Verification

Automated tests are not required for layout-only refactoring unless helper formatting or severity mapping logic becomes non-trivial.

Manual verification is required:

- Launch the app.
- Confirm popover opens from the status item.
- Confirm CPU/RAM/Network switches do not wrap.
- Confirm each visibility switch still starts/stops the correct metric behavior.
- Confirm the Icon/Label control only affects menu bar identifier formatting.
- Confirm all-hidden state appears and allows recovery.
- Confirm light and dark mode readability.
- Confirm no visible layout jitter when values update.

## Implementation Boundaries

Do not modify:

- CPU sampler behavior.
- RAM sampler behavior.
- Network sampler behavior.
- Formatter output rules.
- UserDefaults keys.
- PRD metric scope.

Only modify state code if the UI needs an already-computed property that avoids duplicating existing severity logic.
