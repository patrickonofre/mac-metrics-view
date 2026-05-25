# Plan: Honest thermal-state metric + event-driven sampling

Status: ready

## Objective

Make the temperature metric honest and efficient, aligned with
[TD-005](../../TECH_DECISIONS.md) (thermal state is the primary signal; numeric
Celsius is optional and not wired yet, since there is no privilege-free source).

Two problems today:

- **(9)** The popover trend reads `temperatureHistory.samples.compactMap(\.celsius)`,
  but `celsius` is always `nil` (the reader uses `ProcessInfo.thermalState`). The
  history even filters out non-Celsius samples, so it is permanently empty and the
  sparkline never renders — a dead path that also makes the metric feel like a missing
  numeric reading.
- **(10)** Temperature is polled on a 5 s `Timer`, but macOS already pushes
  `ProcessInfo.thermalStateDidChangeNotification`. Polling a value that only changes by
  event wastes wakeups.

## Phases

1. **Event-driven sampling (10).** Replace the `TemperatureSampler` timer with an
   observer of `ProcessInfo.thermalStateDidChangeNotification`. Emit one sample at
   `start()` and one per notification. Inject `NotificationCenter` for testability.
2. **Honest state trend (9).** Give each sample a normalized `trendValue` derived from
   the thermal state level (and from Celsius when a numeric source exists in the
   future). Keep all samples in `TemperatureHistory` (drop the Celsius-only filter) and
   feed the sparkline from `trendValue`, so the trend reflects the real, always-present
   signal instead of an empty Celsius series.
3. **Tests + docs.** Add sampler/notification and trend tests; update the history test
   that asserted Celsius-less samples are dropped; record the decisions.

## Risks

- Changing `TemperatureHistory` semantics breaks `testTemperatureHistoryIgnoresSamplesWithoutCelsius`.
  Mitigation: replace it with a test asserting state-only samples are kept.
- Notification delivery thread: observe on `.main` and assume main-actor isolation
  (consistent with `MainRunLoopTimer`).
- Scope: do **not** add an SMC/IOKit Celsius reader (TD-005 caution). Celsius stays a
  supported-but-unwired field.

## Dependencies

- None. Self-contained in the temperature path (`Models/TemperatureSample.swift`,
  `Models/TemperatureHistory.swift`, `Services/TemperatureSampler.swift`,
  `UI/PopoverView.swift`) plus tests and `TECH_DECISIONS.md`.

## Out of scope

- Numeric Celsius via SMC/IOKit/`powermetrics`.
- Renaming the metric away from "Temperature/Temperatura".
- Alerts/notifications on thermal escalation.

## Validation

See `../validation/validation-thermal-state-trend-and-events.md` once executed.
