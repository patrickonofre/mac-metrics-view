# Prompt: Create a spec

Vendor-neutral. Produces a SPEC artifact in `docs/ai/specs/`.

---

You are writing a **spec** (technical + functional contract) for Mac Metrics View.
Read `AGENTS.md`, `docs/ai/architecture.md`, `docs/ai/domain-catalog.md`, and the
parent plan if one exists.

Source: <plan path or direct request>

Produce a spec that defines:
1. **Summary** — what this delivers.
2. **Functional requirements** — observable behavior (menu bar, popover, settings).
3. **Technical requirements** — data shapes and the correct **architecture layer** for
   each piece (Reader → Sampler → Sample/History → Formatter → CPUState → UI).
4. **Edge cases** — no-previous-snapshot, counter resets, clamping (no NaN/negative/
   impossible values), light/dark legibility.
5. **Acceptance criteria** — each one **testable** so validation can prove it.
6. **Non-goals**.

Constraints:
- Keep metric logic UI-free and unit-testable (inject reader protocols).
- Respect severity thresholds (normal <80%, elevated 80–<90%, high ≥90%; RAM shows GB).
- Link existing `docs/` design docs instead of duplicating them.
- Save to `docs/ai/specs/spec-<kebab-name>.md` with `Status: draft` and the format in
  `docs/ai/specs/README.md`. Never in a vendor folder.

Output the file path and the acceptance-criteria checklist.
