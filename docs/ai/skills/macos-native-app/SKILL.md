---
name: macos-native-app
description: Build native macOS applications for this project using Swift, SwiftUI, AppKit interop, Xcode project conventions, menu bar/status item UX, launch agents, sandbox/capability decisions, and local verification. Use when an agent needs to plan, scaffold, implement, review, or test native macOS features for Mac Metrics View, especially menu bar UI, popovers, app lifecycle, preferences, packaging, and macOS-specific behavior.
---

# macOS Native App

## Overview

Use this skill to keep Mac Metrics View idiomatic to macOS: native Swift first, SwiftUI for most UI, AppKit where SwiftUI does not expose the needed menu bar or window behavior, and small focused services for system integration.

## Default Stack

- Language: Swift.
- UI: SwiftUI, with AppKit bridges for `NSStatusItem`, `NSPopover`, activation policy, and menu bar lifecycle when needed.
- Minimum target: macOS 14 unless the PRD or user changes it.
- Project style: Xcode app target first; add Swift Package modules only when separation becomes useful.
- Concurrency: Swift Concurrency and `Timer`/`AsyncSequence` patterns for periodic updates.
- Persistence: `UserDefaults` for V1 preferences.

## Workflow

1. Read `docs/PRD.md` and `docs/TECH_DECISIONS.md` before making product or platform choices.
2. Prefer a menu bar-only app for V1: no Dock icon, no main window on launch, visible status item near the system clock.
3. Keep the status item compact and glanceable. Use text, SF Symbols, or a tiny sparkline only when it remains legible in light/dark mode.
4. Use a popover for detail views and preferences. Avoid separate windows unless the workflow clearly needs one.
5. Keep system metric sampling isolated from UI code so metrics can be tested without launching the app.
6. Verify behavior on a real macOS run target or with unit tests where possible. Do not claim status item behavior is verified unless the app was launched.

## Implementation Notes

- Use `NSStatusBar.system.statusItem(withLength:)` when SwiftUI `MenuBarExtra` is too limiting for custom updating labels or popover control.
- Use `MenuBarExtra` only if the V1 UI can stay simple and the deployment target supports it cleanly.
- Set app activation policy to accessory for menu bar-only behavior.
- Put reusable UI in small SwiftUI views and keep `AppDelegate`/status item coordination thin.
- Treat energy usage as a product requirement: avoid high-frequency timers, heavy process scans, and unnecessary main-thread work.

## References

Read `references/status-item-patterns.md` when implementing menu bar lifecycle, popover behavior, or launch/accessory app behavior.
