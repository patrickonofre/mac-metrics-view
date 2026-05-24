# Architecture

Mac Metrics View is a single macOS app target organized into four layers under
`MacMetricsView/`. The guiding rule: **system metric collection is isolated from UI
rendering** so metrics can be tested without launching the app.

```
MacMetricsView/
  App/        # lifecycle, status item, shared state, app entry point
  Models/     # value types: samples, rolling histories, settings
  Services/   # readers, samplers, formatters (no UI)
  UI/         # SwiftUI views (popover, sparkline)
```

## Data flow

```
Reader  ->  Sampler  ->  Sample (Model)  ->  CPUState  ->  StatusItemController / PopoverView
 (raw)    (timer +       (value type)       (shared       (menu bar title + popover)
          delta calc)                       observable)
```

1. **Readers** wrap raw macOS system APIs and return snapshots
   (`MachCPUReader` → `CPUSnapshot`, `DarwinNetworkReader` → `NetworkCounterSnapshot`).
   They are the only code that touches Mach / Darwin interfaces, which makes the rest
   testable with fake readers.
2. **Samplers** own a `Timer` (default 1s), read snapshots, compute deltas, build a
   `Sample`, and notify via a `@MainActor` delegate
   (`CPUSampler`, `RAMSampler`, `NetworkSampler`, `TemperatureSampler`). Delta-based
   rates require two snapshots before the first valid value.
3. **Models** are plain value types: point-in-time samples (`CPUSample`, `RAMSample`,
   `NetworkSample`, `TemperatureSample`), rolling histories for trend/sparkline
   (`CPUHistory`, `RAMHistory`, `NetworkHistory`, `TemperatureHistory`), and settings
   (`MetricVisibilitySettings`, `MetricDisplaySettings`, `LaunchAtLoginSettings`).
4. **`CPUState`** (in `App/`) is the shared `@MainActor` state object the UI reads. It
   holds latest samples, visibility, and display style, and exposes
   `onVisibilityChange` / `onDisplayChange` callbacks.
5. **`AppDelegate`** wires it together: sets accessory activation policy, owns the
   samplers and `StatusItemController`, implements every sampler delegate, and
   starts/stops samplers as visibility changes (a hidden metric stops its sampler — an
   energy requirement, not just a UI toggle).
6. **`StatusItemController`** builds the menu bar title from `CPUState` (per-metric
   segments, SF Symbol vs. label style) and hosts the `NSPopover`.
   **`PopoverView`** / **`SparklineView`** render detail in SwiftUI.

## Key conventions

- The status item uses `NSStatusBar.system.statusItem` + `NSPopover` (AppKit) rather
  than `MenuBarExtra`, because V1 needs a custom updating attributed title.
- Sampler delegate methods and shared state are `@MainActor`; timers schedule on the
  main run loop.
- Formatters (`CPUFormatter`, `RAMFormatter`, `NetworkFormatter`,
  `TemperatureFormatter`) are pure and fixed-width where the menu bar needs stable
  layout. They clamp defensively — no NaN, negative, or impossible values reach the UI.
- Severity is visual: CPU/RAM normal below 80%, elevated 80–<90%, high ≥90%. RAM still
  displays GB in the menu bar, not percent. See [`domain-catalog.md`](domain-catalog.md).

## Build & packaging

- `Package.swift` embeds `MacMetricsView/SwiftPMInfo.plist` into the executable via
  linker flags so AppKit gets a bundle identifier under `swift run`.
- The Xcode project (`MacMetricsView.xcodeproj`) is the path for producing a real
  `.app` bundle; release builds and the beta zip come from there (see `README.md`).

## Adding a new metric (pattern)

1. Add a `Reader` (raw API) and a `*Sample` model.
2. Add a `Sampler` with a delegate and delta logic; add a `*History` if it needs a trend.
3. Add a pure `*Formatter` with defensive clamping.
4. Surface it through `CPUState`, register the sampler/delegate in `AppDelegate`, and
   gate it on visibility.
5. Render it in `StatusItemController` (menu bar) and/or `PopoverView` (detail).
6. Unit-test reader-fake → sampler → formatter → history before touching UI.

This mirrors the existing CPU/RAM/network/temperature implementations.
