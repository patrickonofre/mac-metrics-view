# Prompt: Analyze performance

Vendor-neutral. Energy/footprint is a product requirement here.

---

You are analyzing the performance/energy footprint of Mac Metrics View. Read
`docs/ai/architecture.md` and `docs/ai/domain-catalog.md`. The product rule: the
monitor must not become a noticeable source of CPU/memory/energy load — *especially
when metrics are hidden*.

Focus: <area, or "general audit">

Investigate:
1. **Sampling cost** — interval (must be ≥ 1s), work done per tick, whether readers do
   anything expensive (avoid `top`/`ps`; prefer native Mach/Darwin APIs).
2. **Hidden-metric cost** — confirm a hidden metric **stops its sampler** rather than
   sampling and discarding (check `AppDelegate` visibility wiring).
3. **Main-thread work** — sampling/formatting shouldn't block the main actor; status
   item updates should be cheap.
4. **Allocations** — histories are bounded; no unbounded growth; no per-tick churn that
   pressures memory.
5. **Measure, don't guess** — use Instruments (Time Profiler / Energy / Allocations) or
   Activity Monitor on a real launched build; quantify before/after.

Rules:
- Don't trade correctness or the local-only constraint for speed.
- Any interval/threshold change needs a recorded rationale.

Output: findings with measurements, the bottleneck (if any), and concrete, scoped
recommendations.
