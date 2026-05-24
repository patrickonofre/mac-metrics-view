# Coding standards

Swift 5.9, SwiftUI + AppKit interop, macOS 14+. Follow the official
[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
These are the project-specific rules on top of that.

## Structure & layering

- Respect the four layers (`App` / `Models` / `Services` / `UI`). **Services must not
  import SwiftUI/AppKit UI types** beyond what they genuinely need; metric logic stays
  UI-free so it is unit-testable. See [`architecture.md`](architecture.md).
- Readers are the only place that touches raw Mach/Darwin APIs. Everything else depends
  on a reader *protocol* (e.g. `CPUReading`) so tests can inject fakes.
- Keep `AppDelegate` and `StatusItemController` thin — coordination, not logic.

## Types

- Model samples and snapshots as **value types** (`struct`). Histories are value types
  with bounded capacity.
- Make fields explicit and typed (timestamp + each percent/byte/GB value). No untyped
  dictionaries for metric data.
- Prefer `let`; keep mutability local and intentional.

## Concurrency

- Sampler delegates and shared state (`CPUState`) are `@MainActor`. UI updates happen
  on the main actor.
- Timers are scheduled on the main run loop. Default sample interval is **1s or slower**
  — never tighten it without a recorded reason; energy use is a product constraint.
- Avoid blocking the main thread with heavy work (process scans, large allocations).

## Values & formatting

- Formatters are **pure functions**, clamp defensively, and never emit `NaN`, negative,
  or impossible percentages to the UI.
- Use fixed-width formatting where the menu bar needs stable layout (so the title
  doesn't jitter as numbers change).
- Compute rates from **deltas between two snapshots**, never from a single cumulative
  reading. Handle the "no previous snapshot yet" case explicitly.

## UI

- SwiftUI for views; AppKit (`NSStatusItem`, `NSPopover`, accessory policy) only where
  SwiftUI can't express the needed menu bar behavior.
- Status item must stay legible in light and dark mode. Use SF Symbols / text / a tiny
  sparkline only while it remains glanceable.
- Detail and preferences live in the popover; avoid extra windows unless a workflow
  clearly needs one.

## Privacy & safety

- Local-only. No telemetry, no external network calls, no analytics, no crash
  reporting. Network metrics read local interface counters only.
- Don't shell out to `top`/`ps` in production code — use native APIs.

## Hygiene

- No speculative abstraction. Add a Swift Package module only when separation earns its
  keep; the project is an Xcode app target first.
- Comment only non-obvious *why* (a Mach quirk, a clamping reason, a two-snapshot
  requirement). Don't narrate what the code already says.
- Match the existing file naming: one primary type per file, file named after the type.
