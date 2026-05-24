# CPU Sampling Reference

## Preferred Model

Represent each sample as:

- `timestamp`
- `totalUsagePercent`
- `userUsagePercent`
- `systemUsagePercent`
- `idlePercent`
- `topProcesses`

Overall usage should be computed from two snapshots of CPU ticks. Store the previous snapshot and compare it with the current snapshot.

## Process Ranking

For V1, top processes are useful in the popover but not required for the first visible menu bar label. If implemented, show:

- Process name
- PID only if useful for debugging or advanced users
- CPU percentage

Group or aggregate child processes only after the basic ranking is correct.

## Validation

- Test delta calculations with fixed fake snapshots.
- Test formatting for 0%, normal values, 100%, and invalid raw values.
- Test CPU visual severity boundaries: 79.9% is normal, 80% is elevated/yellow, 89.9% is elevated/yellow, 90% is high/red, and values above 90% are high/red.
- Compare a running build against Activity Monitor for broad sanity, not exact equality.
- Watch the app's own CPU usage during idle monitoring.
