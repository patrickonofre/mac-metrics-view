# Technical Decisions

## TD-001: Use Swift and SwiftUI for the Native macOS App

Status: Accepted

Decision: Build Mac Metrics View as a native macOS application in Swift, using SwiftUI for the user interface and AppKit interop where needed for menu bar behavior.

Rationale:

- Swift is the first-class language for modern macOS development.
- SwiftUI gives us fast iteration for popovers, preferences, and small native views.
- AppKit remains the most reliable path for precise `NSStatusItem` behavior in the menu bar.
- A native app gives better access to macOS system APIs, lower overhead, and a more platform-correct experience than Electron or a cross-platform shell.

Implications:

- The V1 will be developed and verified on macOS with Xcode tooling.
- The initial architecture should separate metric collection from UI rendering.
- Some implementation points may use AppKit even when the app is mostly SwiftUI.

Alternatives Considered:

- Electron: rejected for V1 because it adds runtime overhead for a lightweight menu bar monitor.
- Tauri: possible in other contexts, but unnecessary for a macOS-only system utility.
- Objective-C/AppKit only: viable, but slower for modern UI iteration and less ergonomic for new development.

## TD-002: Use Local Interface Counters for Network Traffic

Status: Accepted

Decision: Implement V1 network traffic monitoring from local macOS network interface byte counters, aggregated across active non-loopback interfaces.

Rationale:

- Interface counters provide download/upload throughput without sending probe requests.
- Delta-based byte rates fit the existing CPU/RAM sampling pattern: snapshot, calculate, format, publish.
- Aggregating active non-loopback interfaces keeps the menu bar signal simple and avoids turning V1 into a network diagnostics tool.
- The approach supports offline and restricted-network environments because it does not depend on external services.

Implications:

- Network sampling should remain isolated from UI rendering, like CPU and RAM sampling.
- The first valid network display requires two snapshots so a byte-rate delta can be computed.
- V1 should show aggregate throughput, not per-interface detail, remote hosts, packet contents, or process-level network activity.
- Privacy requirements remain intact: network monitoring reads local counters only and does not make external network calls.

Alternatives Considered:

- External speed-test request: rejected because it creates network traffic, has privacy implications, and measures the test endpoint more than current app/system traffic.
- Per-process network inspection: useful later, but too broad and potentially expensive for V1.
- Primary-interface-only display: possible later, but aggregate active interfaces is more predictable when Wi-Fi, Ethernet, VPN, or hotspot interfaces coexist.

## TD-003: Stop Sampling Hidden Metrics

Status: Accepted

Decision: Tie each metric sampler lifecycle to its visibility setting. If CPU, RAM, or network is hidden, the corresponding sampler must stop and must not append new history samples until the metric is shown again.

Rationale:

- A hidden metric provides no user value while still consuming CPU, memory, battery, or native API calls.
- Visibility switches should be an actual performance control, not only a display preference.
- Independent sampler lifecycle keeps the implementation simple and matches the domain model: CPU, RAM, and network are separate signals.
- Persisted visibility settings let the app avoid starting unnecessary samplers during launch.

Implications:

- Metric visibility must be loaded before starting samplers.
- Showing a hidden metric requires a fresh sampling start and may briefly show a fallback value.
- Hiding a metric should remove its menu bar segment, popover detail, and trend immediately.
- If all metrics are hidden, the app still needs a minimal menu bar control for reopening the popover and quitting, but no metric samplers should run.

Alternatives Considered:

- Keep all samplers running and only hide UI segments: rejected because it wastes resources and violates the lightweight product goal.
- Use one shared timer that always reads all metrics: rejected for V1 because it makes hidden metrics harder to optimize.
- Prevent users from hiding every metric: rejected because a minimal control can preserve access without forcing unnecessary sampling.

## TD-004: Use Compact Menu Bar Metric Identifiers

Status: Accepted

Decision: Add a persisted `identifierStyle` display setting that controls whether menu bar metric segments use compact SF Symbols or explicit `CPU`, `RAM`, and `NET` labels. The default value is `.icons`. Legacy `showMetricLabels` preferences migrate to the equivalent style.

Rationale:

- The menu bar is space-constrained, so the default should favor compact, recognizable identifiers.
- Apple's Human Interface Guidelines recommend symbols for menu bar extras when they improve recognition, and SF Symbols inherit the platform's monochrome menu bar behavior.
- `cpu`, `memorychip`, and `network` clearly map to CPU, RAM, and network context without adding a third-party icon style.
- Users who prefer explicit names can switch to labels without changing which metrics are sampled.

Implications:

- Identifier display is a formatting preference only.
- Toggling between icons and labels must update the status item immediately.
- Toggling display style must not start, stop, restart, or force-read CPU, RAM, or network samplers.
- The setting should persist in `UserDefaults` with the metric visibility settings.

Alternatives Considered:

- Always show labels: rejected because it makes the default menu bar item wider than necessary.
- Never show labels: rejected because explicit labels are useful for users who prefer clarity over compactness.
- Third-party/custom icons: rejected because native SF Symbols fit macOS menu bar rendering better and avoid asset maintenance.
- Per-metric identifier switches: rejected for V1 because a single global display control is simpler and covers the main need.

## TD-005: Prefer Official Thermal State Before Numeric Temperature

Status: Accepted

Decision: For the planned temperature feature, use `ProcessInfo.processInfo.thermalState` as the primary source for thermal condition and treat numeric Celsius readings as optional. A lower-level SMC/IOKit reader may be added behind a protocol only if it fails gracefully, does not require elevated privileges, and preserves a fallback to the official thermal state.

Rationale:

- macOS exposes thermal pressure through a public API, but does not provide a simple public Celsius API for all Macs.
- Temperature sensors vary across Intel Macs, Apple Silicon Macs, and macOS releases.
- A menu bar utility should not require `sudo`, shell out to `powermetrics`, or block the main thread to show a glanceable thermal signal.
- Showing a reliable Portuguese state such as `Normal`, `Aquecido`, `Quente`, or `Crítico` is more honest than showing a fragile numeric value.

Implications:

- The first implementation can ship with thermal state even when Celsius is unavailable.
- The UI must support both numeric temperature and state-only fallback.
- Tests should validate formatting, severity, persistence, history, and sampler lifecycle before production code is added.
- The temperature sampler is **event-driven**: it observes `ProcessInfo.thermalStateDidChangeNotification` and samples once at start, instead of polling on a timer. Thermal state only changes by event, so polling (the earlier ~5 s target) is unnecessary wakeups.
- The popover trend plots a normalized thermal-state level (`TemperatureState.trendLevel`) so the state-only fallback still shows a real, always-present trend. `TemperatureHistory` therefore keeps every sample, not only Celsius ones. When a numeric source exists, `TemperatureSample.trendValue` prefers the Celsius reading.

Alternatives Considered:

- `powermetrics`: rejected for production because it commonly requires elevated privileges and is too heavy for a menu bar sampler.
- Always require SMC/IOKit Celsius: rejected because sensor availability and key names are not stable enough across supported Macs.
- Do not add temperature: rejected as a product direction because thermal pressure is a core reason users reach for lightweight Mac monitoring tools.

## TD-006: Use SMAppService for Launch at Login

Status: Proposed

Decision: For the planned "abrir ao inicializar" feature, use `SMAppService.mainApp` from Apple's `ServiceManagement` framework to register and unregister Mac Metrics View as a login item for the current user. Keep the API behind a small testable service rather than calling it directly from SwiftUI views.

Rationale:

- `SMAppService` is the modern native macOS API for login item registration.
- The app already targets macOS 14, so the modern API is available.
- Direct plist editing, `launchctl`, launch agents, and shell scripts are unnecessary and more fragile.
- Opening at login is a user preference, not a metric setting, so it should not affect sampler lifecycle or metric visibility.

Implications:

- The UI should expose a simple `Abrir ao inicializar` toggle.
- The system status should be the source of truth; `UserDefaults` may cache user intent but must not override macOS status.
- Registration failures must revert or refresh the UI so it does not claim the app will open at login when registration failed.
- Automated tests should use a fake login-item manager instead of touching real macOS login item state.

Alternatives Considered:

- `launchctl` or manual LaunchAgent plist: rejected because it is heavier, harder to test safely, and less appropriate for a bundled macOS app.
- Add the app silently at first launch: rejected because launch-at-login should be an explicit user choice.
- Store only a `UserDefaults` boolean: rejected because it can drift from the actual macOS login item state.

## TD-007: Define RAM "Used" as App Memory + Wired + Compressed

Status: Accepted

Decision: Compute displayed RAM usage from `vm_statistics64` as `(internal_page_count - purgeable_count) + wire_count + compressor_page_count`, multiplied by the page size. This approximates Activity Monitor's "Memory Used" (App Memory + Wired Memory + Compressed). Inactive and other file-cache pages are excluded because the system treats them as available.

Rationale:

- The product answers "is my Mac under memory pressure right now?", so the number should track what the system considers actually in use, not reclaimable cache.
- The previous formula (`active + inactive + wire + compressor`) included `inactive`, which is largely reclaimable file cache, and so read consistently higher than Activity Monitor — confusing for users comparing the two.
- `internal_page_count - purgeable_count` is the commonly used approximation of Apple's "App Memory" (anonymous, non-purgeable app pages).

Implications:

- The menu bar still displays GB (not percent); severity thresholds keep using `usedPercent`.
- The reader must guard against `purgeable_count > internal_page_count` to avoid unsigned underflow (clamped to 0).
- The value is still an approximation: it can differ from Activity Monitor by a small amount because Apple's exact accounting is not fully public. It should be close, not bit-exact.

Alternatives Considered:

- Keep `active + inactive + wire + compressor`: rejected because including reclaimable inactive cache overstates usage versus Activity Monitor.
- Align to `active + wire + compressor` (drop only inactive): rejected as a less accurate approximation of App Memory than the internal/purgeable form.
- Report memory pressure level instead of GB: rejected for V1 because the GB figure is the established, glanceable signal and matches the CPU/network pattern.
