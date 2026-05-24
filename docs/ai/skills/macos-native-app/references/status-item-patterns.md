# Status Item Patterns

Use these patterns for Mac Metrics View menu bar work.

## App Shape

- Prefer a menu bar-only app for V1.
- Hide the Dock icon by using accessory activation behavior.
- Keep the app useful without opening a full window.
- Make Quit available from the popover or menu so users are never trapped.

## Status Item

- Show compact CPU and RAM values such as `CPU 18%  RAM 12.4 GB` by default.
- Keep the label width stable enough to avoid distracting jitter. Consider fixed-width digits or a short icon plus percentage.
- Update every 1-2 seconds by default. Faster updates are not necessary for a glanceable system monitor.
- Support light mode, dark mode, and high contrast by using system colors and SF Symbols.
- Use normal system text color below 80% usage, yellow text from 80% to below 90%, and red text at 90% or higher. For CPU, severity is based on CPU percentage. For RAM, severity is based on percent of total memory used while the displayed value remains GB. Treat these as visual states, not alerts.

## Popover

- Show current CPU usage, RAM usage in GB, short recent trends, and top CPU processes if process ranking is included.
- Include a small Preferences entry for refresh interval and display format when preferences exist.
- Close the popover when the user clicks outside it, unless an interaction requires persistence.

## Verification

- Build with Xcode or `xcodebuild`.
- Launch the app and confirm the status item appears in the macOS menu bar.
- Confirm the app idles with low CPU usage while monitoring CPU.
