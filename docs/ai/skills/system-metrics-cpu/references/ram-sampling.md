# RAM Sampling Reference

Use this reference when implementing RAM usage for V1.

## Preferred Model

Represent each sample as:

- `timestamp`
- `usedGB`
- `totalGB`
- `usedPercent`

The menu bar must display GB, not percent. Use the percent only for color severity.

## Severity

- `< 80%`: normal
- `>= 80%` and `< 90%`: elevated/yellow
- `>= 90%`: high/red

Boundary tests:

- `79.9%` is normal.
- `80%` is elevated/yellow.
- `89.9%` is elevated/yellow.
- `90%` is high/red.
- Values above `90%` are high/red.

## Formatting

- Display used memory as `RAM 12.4 GB` by default.
- Use one decimal place by default.
- Never show `NaN`, negative values, or RAM percentage in the menu bar.
