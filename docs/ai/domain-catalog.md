# Domain catalog

Shared vocabulary for Mac Metrics View. Use these terms consistently in code, specs,
and PRs.

## Metrics

| Metric | Menu bar display | Source | Notes |
| --- | --- | --- | --- |
| **CPU** | Overall usage % | `MachCPUReader` (Mach host CPU ticks) | Computed from delta between two snapshots, not a single cumulative read. |
| **RAM** | Used memory in **GB** | `RAMSampler` | Severity is percent-of-total, but the menu bar shows GB, not %. |
| **Network** | Download + upload throughput | `DarwinNetworkReader` (interface byte counters) | Aggregated across active non-loopback interfaces; delta-based; needs two snapshots for the first rate. Local counters only — no probes. |
| **Temperature** | Popover detail (extension) | `TemperatureSampler` | Specified in `docs/features/temperatura.md`. |

## Severity (visual state)

Applies to CPU and RAM. Drives color, not the displayed unit.

| State | Threshold | Color intent |
| --- | --- | --- |
| Normal | `< 80%` | default / quiet |
| Elevated | `80%` to `< 90%` | yellow |
| High | `>= 90%` | red |

RAM uses these thresholds on percent-of-total memory, while still **displaying GB** in
the menu bar.

## Display controls

- **Visibility** (`MetricVisibilitySettings`) — each metric (CPU/RAM/network) can be
  shown or hidden in the menu bar. Hiding a metric **stops its sampler** (energy
  requirement), not just its rendering.
- **Identifier display** (`MetricDisplaySettings`) — menu bar metric identifiers render
  as compact **SF Symbols by default**, or as explicit `CPU` / `RAM` / `NET` labels.
- **Launch at login** (`LaunchAtLoginSettings`) — specified in
  `docs/features/inicializacao.md`.

## Core types (glossary)

- **Reader** — wraps a raw macOS API and returns a snapshot (`CPUSnapshot`,
  `NetworkCounterSnapshot`). The only code touching Mach/Darwin directly.
- **Snapshot** — a raw cumulative reading at a point in time; rates come from snapshot
  deltas.
- **Sampler** — timer-driven; turns snapshots into a `Sample` and notifies a delegate.
- **Sample** — a value type holding the computed values for one tick (`CPUSample`,
  `RAMSample`, `NetworkSample`, `TemperatureSample`).
- **History** — bounded rolling buffer of samples for a trend/sparkline (`CPUHistory`,
  `RAMHistory`, `NetworkHistory`, `TemperatureHistory`).
- **Formatter** — pure, defensive value→string conversion, fixed-width for the menu bar.
- **CPUState** — shared `@MainActor` state the UI observes (latest samples + settings).
- **StatusItemController** — owns the `NSStatusItem` title and the `NSPopover`.

## The product question

Everything in the menu bar exists to answer, at a glance:

> Is my Mac under CPU, RAM, or network pressure right now?

If a change doesn't help answer that quickly and quietly, it probably belongs in the
popover or out of scope.
