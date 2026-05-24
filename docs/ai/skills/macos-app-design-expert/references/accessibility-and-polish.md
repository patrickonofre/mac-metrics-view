# Accessibility And Polish Reference

## Accessibility

- Give the status item a useful accessibility label that summarizes visible metrics.
- For menu bar values, do not rely on color alone. VoiceOver text should include severity when useful.
- Keep switches and buttons reachable by keyboard.
- Make sparklines decorative unless they expose meaningful accessibility summaries.
- Respect Reduce Motion for any animated transitions.
- Check contrast in light and dark mode, especially yellow severity text.
- Avoid truncating metric values in a way that hides units.

## Typography

- Use the system font unless a specific value benefits from monospaced digits.
- Use `.monospacedDigit()` for CPU percent, RAM GB, byte rates, and timestamps.
- Avoid oversized title styles inside compact popovers.
- Keep labels secondary and values primary.

## Color And Severity

For Mac Metrics View V1:

- Normal: semantic primary text.
- Elevated CPU/RAM: yellow or system warning-like color, readable in both appearances.
- High CPU/RAM: red or system destructive-like color, used only for the value or tiny indicator.
- Network: neutral unless thresholds are defined later.

Severity should communicate "look here" rather than "panic".

## Motion

- Avoid continuous animated graphs.
- If changing metric visibility, a simple native transition is enough.
- Do not animate numeric changes every second.

## Release Polish Checks

- Light and dark mode both look intentional.
- The popover has no accidental nested-card appearance.
- Long network rates do not push controls offscreen.
- First-launch placeholders look deliberate.
- Empty or all-hidden state keeps recovery obvious.
- Quit action is separated from frequently used settings.
- The app remains understandable without onboarding text.
