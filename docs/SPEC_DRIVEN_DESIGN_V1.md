# Spec-Driven Design: Mac Metrics View V1

## Purpose

This document turns the V1 PRD into an implementation contract. Build only what is required to deliver a native macOS menu bar CPU, RAM, and network traffic monitor that is visible near the system date/time area, supports user-controlled metric visibility and menu bar identifier display, updates visible metrics periodically, and opens a focused resource detail popover.

Planned feature extensions must be specified outside the V1 contract before production code is changed. The temperature feature plan lives in `docs/features/temperatura.md`, and the launch-at-login feature plan lives in `docs/features/inicializacao.md`.

## Product Contract

V1 answers one question:

> Is my Mac under CPU, RAM, or network pressure right now?

The app must be:

- Native: Swift, SwiftUI, and AppKit where needed.
- Menu bar-first: no default Dock icon, no main window on launch.
- Lightweight: the monitor must not create meaningful resource load.
- Local: no telemetry, no external network calls, no accounts.
- Focused: CPU, RAM, and network traffic only.
- User-controlled: CPU, RAM, and network can each be shown or hidden.
- Compact by default: metric identifiers use native icons unless the user switches to labels.

## V1 Scope

### In Scope

- Native macOS app target.
- Status item in the macOS menu bar.
- Current CPU usage percentage in the status item.
- Yellow elevated-CPU visual state when usage is 80% or higher.
- Red high-CPU visual state when usage is 90% or higher.
- Current RAM usage in GB in the status item.
- Yellow elevated-RAM visual state when memory usage is 80% or higher.
- Red high-RAM visual state when memory usage is 90% or higher.
- Periodic CPU sampling when CPU is visible, default around 1 second.
- Periodic RAM sampling when RAM is visible, default around 1 second.
- Current network download and upload throughput in the status item.
- Network throughput formatted as byte rates per second with adaptive units.
- Periodic network byte-counter sampling when network is visible, default around 1 second.
- Popover opened by clicking the status item.
- Popover with current CPU percentage, current RAM usage in GB, current network download/upload throughput, and short recent trends for visible metrics.
- Popover switches for showing or hiding CPU, RAM, and network metrics.
- Popover control for choosing menu bar metric icons or labels.
- Persistent visibility settings for CPU, RAM, and network.
- Persistent identifier display setting, defaulting to icons.
- Sampler lifecycle tied to visibility so hidden metrics do not keep collecting samples.
- Quit action.
- Light/dark mode support through system colors.
- Basic unit tests for CPU/RAM/network calculation, severity, history, and formatting.

### Out Of Scope

- Disk, battery, temperature, fan metrics.
- Login item/start at login.
- Notifications or threshold alerts.
- Sound, banners, blinking, or animated warning states for elevated/high CPU or RAM.
- Full process explorer.
- Long-term history.
- Cloud sync, telemetry, analytics.
- Complex preferences beyond metric visibility.
- App Store packaging.

## Technical Contract

### Stack

- Language: Swift.
- UI: SwiftUI.
- macOS integration: AppKit interop for `NSStatusItem`, `NSPopover`, app activation policy, and quit lifecycle if `MenuBarExtra` is too limited.
- Minimum target: macOS 14.
- Persistence: `UserDefaults` for metric visibility and identifier display settings only.

### Architecture

Keep V1 split into four small areas:

1. App lifecycle
   - Owns menu bar setup.
   - Owns app activation policy.
   - Owns popover show/hide.
   - Owns quit action.

2. CPU/RAM/network sampling
   - Reads CPU tick snapshots from native APIs.
   - Computes deltas between previous and current samples.
   - Emits normalized CPU values.
   - Reads memory totals and used memory from native APIs.
   - Emits RAM used in GB and memory usage percentage for severity.
   - Reads local network interface byte counters from native APIs.
   - Computes download and upload byte-rate deltas between previous and current samples.
   - Emits aggregate network throughput for active non-loopback interfaces.
   - Starts each sampler only when its metric is visible.
   - Stops each sampler when its metric is hidden.
   - Has no UI dependency.

3. State/model layer
   - Stores metric visibility settings.
   - Stores metric identifier display setting.
   - Stores latest CPU sample.
   - Stores latest RAM sample.
   - Stores latest network sample.
   - Stores short rolling history.
   - Publishes formatted values for visible metrics to UI.
   - Coordinates sampler start/stop when visibility changes.

4. UI
   - Status item label.
   - Popover content.
   - Visibility switches.
   - Identifier display control.
   - Trend display.
   - Quit button/menu action.

## Data Model

### `MetricVisibilitySettings`

Required fields:

- `showCPU: Bool`
- `showRAM: Bool`
- `showNetwork: Bool`

Rules:

- Defaults: CPU, RAM, and network are all visible on first launch.
- Settings must persist in `UserDefaults`.
- Settings must be read during app startup before samplers are started.
- Changing a setting must update the menu bar and popover immediately.
- Changing a setting from visible to hidden must stop the corresponding sampler and prevent new history samples for that metric.
- Changing a setting from hidden to visible must restart the corresponding sampler and show the metric fallback until a valid sample exists.
- If all metrics are hidden, keep a minimal status item visible so the user can reopen the popover, re-enable metrics, or quit.
- The minimal all-hidden status item must not trigger CPU, RAM, or network sampling.

### `MetricDisplaySettings`

Required fields:

- `identifierStyle: IdentifierStyle`

Required values:

- `.icons`
- `.labels`

Rules:

- Default: `identifierStyle` is `.icons` on first launch.
- Setting must persist in `UserDefaults`.
- Setting must be read during app startup before the first status item title is formatted.
- Changing the setting must update the menu bar immediately.
- Changing the setting must not start, stop, or restart CPU, RAM, or network samplers.
- The setting affects only visible metric segments.
- The setting does not affect popover switch labels or detail labels; those remain explicit for clarity.
- Legacy `showMetricLabels` preferences should migrate to `.labels` when true and `.icons` when false.

### `CPUSample`

Required fields:

- `timestamp: Date`
- `totalUsagePercent: Double`
- `userUsagePercent: Double?`
- `systemUsagePercent: Double?`
- `idlePercent: Double?`

Rules:

- `totalUsagePercent` must be clamped to `0...100`.
- Invalid raw values must not reach the UI.
- UI formatting should round to whole percentages for the menu bar.

### `CPUHistory`

Required behavior:

- Store recent samples in memory only.
- Keep enough data for a compact trend, for example 30-60 samples.
- Drop oldest samples when capacity is exceeded.

### `RAMSample`

Required fields:

- `timestamp: Date`
- `usedGB: Double`
- `totalGB: Double`
- `usedPercent: Double`

Rules:

- `usedGB` and `totalGB` must be non-negative.
- `usedPercent` must be clamped to `0...100`.
- Menu bar UI must display RAM in GB, not percent.
- RAM color severity uses `usedPercent`.

### `RAMHistory`

Required behavior:

- Store recent samples in memory only.
- Keep enough data for a compact trend, for example 30-60 samples.
- Drop oldest samples when capacity is exceeded.

### `NetworkCounterSnapshot`

Required fields:

- `timestamp: Date`
- `receivedBytes: UInt64`
- `sentBytes: UInt64`

Rules:

- Counters must represent aggregate bytes across active non-loopback network interfaces.
- Raw counters must not be displayed directly in the UI.
- If no eligible interface is available, the reader may return `nil`.

### `NetworkSample`

Required fields:

- `timestamp: Date`
- `downloadBytesPerSecond: Double`
- `uploadBytesPerSecond: Double`

Rules:

- Byte rates must be non-negative.
- Invalid raw values must not reach the UI.
- UI formatting should use adaptive units: B/s, KB/s, MB/s, then GB/s if needed.
- Menu bar UI must show download and upload separately.

### `NetworkHistory`

Required behavior:

- Store recent samples in memory only.
- Keep enough data for a compact trend, for example 30-60 samples.
- Drop oldest samples when capacity is exceeded.

## CPU Sampling Spec

### Sampling Behavior

- On app start, collect an initial CPU tick snapshot only if CPU is visible.
- On each timer tick, collect a new snapshot.
- Compute usage from the delta between snapshots.
- Update published state only after a valid delta exists.
- Default refresh interval: 1 second.
- If CPU is hidden, stop the CPU timer/loop and do not read CPU tick snapshots.
- If CPU is shown again, restart CPU sampling and wait for a valid delta before displaying a real percentage.

### Calculation Behavior

Given previous and current CPU tick counters:

- Compute deltas for user, system, idle, nice if available.
- Compute total delta as the sum of all deltas.
- Compute busy delta as total delta minus idle delta.
- `totalUsagePercent = busyDelta / totalDelta * 100`.

Edge cases:

- If total delta is zero, keep previous valid sample or show an unavailable state.
- If counters go backward, discard the sample.
- If calculation produces NaN/infinity, discard the sample.
- Clamp final display values to `0...100`.

## RAM Sampling Spec

### Sampling Behavior

- On app start, collect an initial RAM sample only if RAM is visible.
- On each timer tick, collect a new RAM sample.
- Compute used memory in GB.
- Compute used memory percentage from used memory divided by total memory.
- Update published state only after a valid sample exists.
- Default refresh interval: 1 second.
- If RAM is hidden, stop the RAM timer/loop and do not read memory statistics.
- If RAM is shown again, restart RAM sampling and display `RAM -- GB` until a valid sample exists.

### Display And Severity Behavior

- Display RAM as used GB, for example icon plus `12.4 GB` by default or `RAM 12.4 GB` when labels are enabled.
- Use one decimal place by default.
- Do not show RAM percentage in the menu bar for V1.
- Use normal color below 80% used memory.
- Use yellow from 80% to below 90% used memory.
- Use red at 90% used memory or higher.

Edge cases:

- If total memory is zero or unavailable, show `RAM -- GB`.
- If used memory is negative, discard the sample.
- If calculation produces NaN/infinity, discard the sample.
- Clamp severity percentage to `0...100`.

## Network Sampling Spec

### Sampling Behavior

- On app start, collect an initial network counter snapshot only if network is visible.
- On each timer tick, collect a new counter snapshot.
- Compute elapsed time between snapshots.
- Compute download rate from received-byte delta divided by elapsed seconds.
- Compute upload rate from sent-byte delta divided by elapsed seconds.
- Update published state only after a valid delta exists.
- Default refresh interval: 1 second.
- If network is hidden, stop the network timer/loop and do not read network interface counters.
- If network is shown again, restart network sampling and display the network fallback until a valid delta exists.

### Interface Behavior

- Include active non-loopback interfaces.
- Exclude loopback interfaces.
- Prefer aggregate traffic across eligible interfaces for V1 instead of showing per-interface rows.
- Do not make external requests to detect connectivity or measure speed.
- Do not collect remote hostnames, process-level network activity, packet payloads, or connection destinations.

### Calculation Behavior

Given previous and current network byte counters:

- Compute `receivedDelta = current.receivedBytes - previous.receivedBytes`.
- Compute `sentDelta = current.sentBytes - previous.sentBytes`.
- Compute `elapsedSeconds = current.timestamp - previous.timestamp`.
- `downloadBytesPerSecond = receivedDelta / elapsedSeconds`.
- `uploadBytesPerSecond = sentDelta / elapsedSeconds`.

Edge cases:

- If elapsed time is zero or negative, discard the sample.
- If counters go backward, discard the sample.
- If calculation produces NaN/infinity, discard the sample.
- Clamp final display values to non-negative rates.

## UI Spec

### Menu Bar Item

Default display with icons:

```text
[cpu] 18%  [memorychip] 12.4 GB  [network] ↓ 1.2 MB/s ↑ 84 KB/s
```

Display with labels shown:

```text
CPU 18%  RAM 12.4 GB  NET ↓ 1.2 MB/s ↑ 84 KB/s
```

Example display with RAM hidden and icons:

```text
[cpu] 18%  [network] ↓ 1.2 MB/s ↑ 84 KB/s
```

Example display with RAM hidden and labels shown:

```text
CPU 18%  NET ↓ 1.2 MB/s ↑ 84 KB/s
```

Requirements:

- Must remain compact.
- Visible metric segments must update periodically without user interaction.
- Must avoid visual jitter as values change.
- Must be readable in light and dark mode.
- Must include only visible metric segments.
- Must remove hidden metric segments without leaving placeholder text or spacing artifacts.
- Must use SF Symbol metric identifiers by default.
- Must use `cpu`, `memorychip`, and `network` symbols for CPU, RAM, and network icon mode.
- Must show text metric labels only when `identifierStyle` is `.labels`.
- Identifier display changes must not affect sampling lifecycle.
- Must use the normal system menu bar text color below 80% CPU usage.
- Must use yellow text from 80% to below 90% CPU usage.
- Must use red text at 90% CPU usage or higher.
- Must return to the normal color when CPU usage falls below 80%.
- Must display RAM in GB, not percent.
- Must use the normal system menu bar text color below 80% RAM usage.
- Must use yellow text from 80% to below 90% RAM usage.
- Must use red text at 90% RAM usage or higher.
- Must return RAM to the normal color when RAM usage falls below 80%.
- Must display network download and upload throughput as byte rates per second.
- Must use adaptive units for network traffic, for example `B/s`, `KB/s`, or `MB/s`.
- Must not apply warning colors to network traffic in V1 unless explicit thresholds are introduced.
- Must not show invalid values such as `NaN%`, `-1%`, or `101%`.
- Must not show invalid RAM values such as `NaN GB`, `-1 GB`, or percentages.
- Must not show invalid network values such as `NaN B/s`, negative rates, or raw byte counters.

Fallback display while waiting for first valid sample, with icons:

```text
[cpu] --%  [memorychip] -- GB  [network] ↓ -- B/s ↑ -- B/s
```

Fallback display while waiting for first valid sample, with labels shown:

```text
CPU --%  RAM -- GB  NET ↓ -- B/s ↑ -- B/s
```

Minimal display when all metrics are hidden:

```text
Metrics
```

The minimal all-hidden display is only a control surface. It must not collect CPU, RAM, or network samples.

### Popover

Popover content for V1:

- Switches for CPU, RAM, and network visibility.
- Control for menu bar metric icons or labels.
- Current CPU usage.
- Current RAM usage in GB.
- Current network download throughput.
- Current network upload throughput.
- Small recent trend visualization.
- Last updated time or subtle freshness indicator.
- Quit action.

Do not add explanatory marketing copy inside the app. The UI should be self-evident.

Hidden metrics must not show their detail rows or trends in the popover.

### Visibility Controls

Requirements:

- Use native SwiftUI toggles/switches for CPU, RAM, and network.
- The switch labels should be short: `CPU`, `RAM`, and `Network`.
- Toggling a metric off hides its menu bar segment immediately.
- Toggling a metric off hides its popover detail and trend immediately.
- Toggling a metric off stops its sampler before the next scheduled read whenever practical.
- Toggling a metric on restarts its sampler immediately.
- Toggling a metric on shows fallback text until the first valid sample is available.
- Visibility settings must persist across app launches.
- The app must allow all three metrics to be hidden while keeping the minimal `Metrics` status item available.

### Identifier Display Control

Requirements:

- Use a native SwiftUI segmented picker for menu bar metric identifiers.
- The control label should be short, for example `Display`.
- The choices should be compact enough for the popover header, for example `Icon` and `Label`.
- The default value must be `Icon`.
- Icon mode must render CPU, RAM, and network using `cpu`, `memorychip`, and `network` SF Symbols.
- Selecting labels updates visible menu bar segments immediately to include `CPU`, `RAM`, and `NET`.
- Turning icons on updates visible menu bar segments immediately to remove `CPU`, `RAM`, and `NET` and show the corresponding symbols.
- Changing identifier style must not start, stop, restart, or force-read any metric sampler.
- Identifier display setting must persist across app launches.

### Trend

Acceptable V1 implementations:

- Minimal SwiftUI line/sparkline from recent samples.
- Compact bars from recent samples.
- Text-only recent min/max if charting would delay V1.

Preferred: a small SwiftUI sparkline, implemented as a reusable view.

## Build Sequence

Build in this order:

1. Create native macOS Swift app target.
2. Make app menu bar-only.
3. Add status item with static `CPU --%` label.
4. Add click behavior that opens a popover.
5. Add Quit action.
6. Implement CPU tick snapshot reader.
7. Implement CPU delta calculation with tests.
8. Wire sampler to observable app state.
9. Update status item label from latest sample.
10. Add elevated/high CPU visual states: yellow at or above 80%, red at or above 90%.
11. Implement RAM sampler and RAM GB formatter.
12. Add elevated/high RAM visual states: yellow at or above 80%, red at or above 90%.
13. Implement network counter snapshot reader, network delta calculation, and network rate formatter.
14. Add metric visibility and identifier display settings with `UserDefaults` persistence.
15. Tie CPU, RAM, and network sampler lifecycle to visibility settings.
16. Add rolling history for CPU, RAM, and network.
17. Add popover CPU/RAM/network details, trends, visibility switches, and identifier display control.
18. Verify light/dark mode and idle resource usage.

Do not build preferences beyond metric visibility, login item, process lists, or extra metrics before step 18 passes.

## Testing Spec

### Unit Tests

Required tests:

- CPU calculation returns 0% when only idle ticks increase.
- CPU calculation returns 100% when no idle ticks increase.
- CPU calculation returns expected percentage for mixed busy/idle deltas.
- Calculation rejects zero total delta.
- Calculation rejects backward counters.
- Formatter clamps invalid display values.
- Formatter or view model returns normal color below 80%.
- Formatter or view model returns yellow color at exactly 80%.
- Formatter or view model returns yellow color above 80% and below 90%.
- Formatter or view model returns red color at exactly 90%.
- Formatter or view model returns red color above 90%.
- RAM formatter returns GB, not percent.
- RAM formatter uses one decimal place by default.
- RAM severity returns normal below 80%.
- RAM severity returns yellow at exactly 80%.
- RAM severity returns yellow above 80% and below 90%.
- RAM severity returns red at exactly 90%.
- RAM severity returns red above 90%.
- CPU and RAM histories keep max capacity and drop oldest samples.
- Network calculation returns expected download and upload byte rates for valid counter deltas.
- Network calculation rejects zero or negative elapsed time.
- Network calculation rejects backward counters.
- Network formatter uses B/s, KB/s, MB/s, and GB/s units as values scale.
- Network formatter never returns NaN, negative rates, or raw byte counters.
- Network history keeps max capacity and drops oldest samples.
- Visibility settings default to CPU/RAM/network enabled.
- Visibility settings persist to and restore from `UserDefaults`.
- Identifier display setting defaults to icons.
- Identifier display setting persists to and restores from `UserDefaults`.
- With icons selected, menu bar output omits `CPU`, `RAM`, and `NET` text and uses metric SF Symbols.
- With labels selected, formatted menu bar output includes `CPU`, `RAM`, and `NET` for visible metrics.
- Changing identifier display does not start, stop, or restart samplers.
- Hiding CPU removes CPU from formatted menu bar output.
- Hiding RAM removes RAM from formatted menu bar output.
- Hiding network removes network from formatted menu bar output.
- Hiding a metric stops its sampler.
- Showing a hidden metric restarts its sampler.
- Hidden metrics do not append new history samples.
- When all metrics are hidden, formatted menu bar output returns the minimal `Metrics` control label.

### Manual Verification

Required checklist:

- App launches without showing a Dock icon.
- Status item appears in the macOS menu bar.
- Status item starts as `CPU --%` or quickly becomes a valid percentage.
- Status item includes RAM in GB.
- Status item includes network download and upload throughput.
- CPU percentage, RAM GB, and network throughput update every ~1 second.
- Popover includes CPU, RAM, and network visibility switches.
- Popover includes a menu bar identifier display control.
- On first launch, metric icons are shown in the menu bar.
- Selecting labels adds `CPU`, `RAM`, and `NET` labels to visible menu bar segments.
- Selecting icons removes `CPU`, `RAM`, and `NET` labels from visible menu bar segments and shows SF Symbols.
- Changing identifier display does not restart currently running samplers.
- Turning CPU off removes CPU from the menu bar and popover detail.
- Turning RAM off removes RAM from the menu bar and popover detail.
- Turning network off removes network from the menu bar and popover detail.
- Turning a metric off stops its sampler and prevents new history samples for that metric.
- Turning a metric back on restarts its sampler and shows a fallback until a valid sample is available.
- Visibility choices persist after quitting and relaunching the app.
- Turning all metrics off leaves a minimal `Metrics` status item available.
- With all metrics off, CPU, RAM, and network samplers are stopped.
- Status item uses normal color below 80% CPU.
- Status item turns yellow from 80% to below 90% CPU.
- Status item turns red at 90% CPU or higher.
- Status item returns to normal color when CPU drops below 80%.
- RAM indicator uses normal color below 80% memory usage.
- RAM indicator turns yellow from 80% to below 90% memory usage.
- RAM indicator turns red at 90% memory usage or higher.
- RAM indicator returns to normal color when memory usage drops below 80%.
- Network indicator shows separate download and upload rates.
- Network indicator remains readable when traffic is idle, low, or high.
- Clicking status item opens popover.
- Clicking outside popover closes it.
- Quit action exits the app.
- App looks acceptable in light mode.
- App looks acceptable in dark mode.
- App does not create noticeable CPU load while idle.

## Acceptance Criteria

V1 is done when:

- A user can launch the app and see CPU usage in the menu bar.
- A user can launch the app and see RAM usage in GB in the menu bar.
- A user can launch the app and see network download and upload throughput in the menu bar.
- A user can hide or show CPU, RAM, and network independently from the popover.
- A user can choose metric icons or labels independently from metric visibility.
- Metric icons are shown by default.
- Identifier display choice persists between launches.
- Changing identifier display does not change sampler lifecycle.
- Hidden metrics are removed from the menu bar and popover details.
- Hidden metrics stop collecting samples until shown again.
- Visibility choices persist between launches.
- If all metrics are hidden, the app still exposes a minimal menu bar control.
- The values update automatically and remain valid.
- The menu bar indicator turns yellow when CPU reaches 80% or higher.
- The menu bar indicator turns red when CPU reaches 90% or higher.
- The menu bar indicator returns to the normal color below 80%.
- The RAM indicator turns yellow when memory usage reaches 80% or higher.
- The RAM indicator turns red when memory usage reaches 90% or higher.
- The RAM indicator returns to the normal color below 80%.
- A user can click the menu bar item to see CPU, RAM, and network detail.
- A user can quit from the app UI.
- The app runs without a Dock icon by default.
- CPU, RAM, and network sampling, severity, history, and formatting have focused tests.
- No out-of-scope metrics or product surfaces were added.
- No notification, sound, blinking, or animated alert is added for high CPU, high RAM, or high network traffic.

## Implementation Guardrails

- Do not shell out to `top`, `ps`, or Activity Monitor in production code.
- Do not make external network requests to measure or verify network traffic.
- Do not add dependencies unless they remove clear implementation risk.
- Do not introduce a database or persistent store in V1.
- Do not build a dashboard window.
- Do not continue sampling hidden metrics.
- Do not append history for hidden metrics.
- Do not add temperature production code until the TDD checklist in `docs/features/temperatura.md` has been reviewed and implementation work is explicitly requested.
- Do not add launch-at-login production code until the TDD checklist in `docs/features/inicializacao.md` has been reviewed and implementation work is explicitly requested.
- Do not couple identifier display to sampler lifecycle.
- Do not turn the 80% yellow or 90% red states into an alerting system in V1.
- Do not optimize for future metrics by over-abstracting the CPU, RAM, or network paths.
- Keep naming plain and domain-specific: `CPUSampler`, `CPUSample`, `CPUHistory`, `RAMSampler`, `RAMSample`, `RAMHistory`, `NetworkSampler`, `NetworkSample`, `NetworkHistory`, `StatusItemController`.

## Open Decisions Before Coding

Resolve these at the start of implementation:

- Use `NSStatusItem` directly or SwiftUI `MenuBarExtra`.
- Use text-only labels or SF Symbol plus text.
- Use one combined status item or separate CPU/RAM/network status items.
- Use text arrows or SF Symbols for network download/upload direction.
- Use sparkline or text-only trend for V1.
- Use `Metrics` text or an icon for the all-hidden status item.

Recommended defaults:

- Use `NSStatusItem` directly for predictable label updates and popover control.
- Use compact SF Symbol plus value segments by default.
- Use attributed status item text if CPU, RAM, and network need independent styling in one menu bar item; otherwise use separate adjacent status items.
- Use aggregate active non-loopback interface counters for V1.
- Use text arrows for network direction in V1 because they are compact and readable in a menu bar.
- Use a simple SwiftUI sparkline if it can be implemented without slowing down the build.
- Use native SwiftUI toggles in the popover for metric visibility.
- Use a native SwiftUI segmented picker in the popover for metric icons or labels, defaulting to icons.
- Use `Metrics` as the all-hidden status item text for clarity.
