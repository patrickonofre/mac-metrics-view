# Technical Decisions

## TD-001: Use Swift and SwiftUI for the Native macOS App

Status: Superseded by TD-015

Decision: Build Mac Metrics View as a native macOS application in Swift, using SwiftUI for the user interface and AppKit interop where needed for menu bar behavior.

Rationale:

- Swift is the first-class language for modern macOS development.
- SwiftUI gives us fast iteration for popovers, preferences, and small native views.
- AppKit remains the most reliable path for precise `NSStatusItem` behavior in the menu bar.
- A native app gives better access to macOS system APIs, lower overhead, and a more platform-correct experience than Electron or a cross-platform shell.

Implications:

- The V1 will be developed and verified on macOS with Xcode tooling.
- The initial architecture should separate metric collection from UI rendering.
- Some implementation points may use AppKit even when the app is mostly SwiftUI.

Alternatives Considered:

- Electron: rejected for V1 because it adds runtime overhead for a lightweight menu bar monitor.
- Tauri: possible in other contexts, but unnecessary for a macOS-only system utility.
- Objective-C/AppKit only: viable, but slower for modern UI iteration and less ergonomic for new development.

## TD-002: Use Local Interface Counters for Network Traffic

Status: Accepted

Decision: Implement V1 network traffic monitoring from local macOS network interface byte counters, aggregated across active non-loopback interfaces.

Rationale:

- Interface counters provide download/upload throughput without sending probe requests.
- Delta-based byte rates fit the existing CPU/RAM sampling pattern: snapshot, calculate, format, publish.
- Aggregating active non-loopback interfaces keeps the menu bar signal simple and avoids turning V1 into a network diagnostics tool.
- The approach supports offline and restricted-network environments because it does not depend on external services.

Implications:

- Network sampling should remain isolated from UI rendering, like CPU and RAM sampling.
- The first valid network display requires two snapshots so a byte-rate delta can be computed.
- V1 should show aggregate throughput, not per-interface detail, remote hosts, packet contents, or process-level network activity.
- Privacy requirements remain intact: network monitoring reads local counters only and does not make external network calls.

Alternatives Considered:

- External speed-test request: rejected because it creates network traffic, has privacy implications, and measures the test endpoint more than current app/system traffic.
- Per-process network inspection: useful later, but too broad and potentially expensive for V1.
- Primary-interface-only display: possible later, but aggregate active interfaces is more predictable when Wi-Fi, Ethernet, VPN, or hotspot interfaces coexist.

## TD-003: Stop Sampling Hidden Metrics

Status: Accepted

Decision: Tie each metric sampler lifecycle to its visibility setting. If CPU, RAM, or network is hidden, the corresponding sampler must stop and must not append new history samples until the metric is shown again.

Rationale:

- A hidden metric provides no user value while still consuming CPU, memory, battery, or native API calls.
- Visibility switches should be an actual performance control, not only a display preference.
- Independent sampler lifecycle keeps the implementation simple and matches the domain model: CPU, RAM, and network are separate signals.
- Persisted visibility settings let the app avoid starting unnecessary samplers during launch.

Implications:

- Metric visibility must be loaded before starting samplers.
- Showing a hidden metric requires a fresh sampling start and may briefly show a fallback value.
- Hiding a metric should remove its menu bar segment, popover detail, and trend immediately.
- If all metrics are hidden, the app still needs a minimal menu bar control for reopening the popover and quitting, but no metric samplers should run.

Alternatives Considered:

- Keep all samplers running and only hide UI segments: rejected because it wastes resources and violates the lightweight product goal.
- Use one shared timer that always reads all metrics: rejected for V1 because it makes hidden metrics harder to optimize.
- Prevent users from hiding every metric: rejected because a minimal control can preserve access without forcing unnecessary sampling.

## TD-004: Use Compact Menu Bar Metric Identifiers

Status: Accepted

Decision: Add a persisted `identifierStyle` display setting that controls whether menu bar metric segments use compact SF Symbols or explicit `CPU`, `RAM`, and `NET` labels. The default value is `.icons`. Legacy `showMetricLabels` preferences migrate to the equivalent style.

Rationale:

- The menu bar is space-constrained, so the default should favor compact, recognizable identifiers.
- Apple's Human Interface Guidelines recommend symbols for menu bar extras when they improve recognition, and SF Symbols inherit the platform's monochrome menu bar behavior.
- `cpu`, `memorychip`, and `network` clearly map to CPU, RAM, and network context without adding a third-party icon style.
- Users who prefer explicit names can switch to labels without changing which metrics are sampled.

Implications:

- Identifier display is a formatting preference only.
- Toggling between icons and labels must update the status item immediately.
- Toggling display style must not start, stop, restart, or force-read CPU, RAM, or network samplers.
- The setting should persist in `UserDefaults` with the metric visibility settings.

Alternatives Considered:

- Always show labels: rejected because it makes the default menu bar item wider than necessary.
- Never show labels: rejected because explicit labels are useful for users who prefer clarity over compactness.
- Third-party/custom icons: rejected because native SF Symbols fit macOS menu bar rendering better and avoid asset maintenance.
- Per-metric identifier switches: rejected for V1 because a single global display control is simpler and covers the main need.

## TD-005: Prefer Official Thermal State Before Numeric Temperature

Status: Accepted

Decision: For the planned temperature feature, use `ProcessInfo.processInfo.thermalState` as the primary source for thermal condition and treat numeric Celsius readings as optional. A lower-level SMC/IOKit reader may be added behind a protocol only if it fails gracefully, does not require elevated privileges, and preserves a fallback to the official thermal state.

Rationale:

- macOS exposes thermal pressure through a public API, but does not provide a simple public Celsius API for all Macs.
- Temperature sensors vary across Intel Macs, Apple Silicon Macs, and macOS releases.
- A menu bar utility should not require `sudo`, shell out to `powermetrics`, or block the main thread to show a glanceable thermal signal.
- Showing a reliable Portuguese state such as `Normal`, `Aquecido`, `Quente`, or `Crítico` is more honest than showing a fragile numeric value.

Implications:

- The first implementation can ship with thermal state even when Celsius is unavailable.
- The UI must support both numeric temperature and state-only fallback.
- Tests should validate formatting, severity, persistence, history, and sampler lifecycle before production code is added.
- The temperature sampler is **event-driven**: it observes `ProcessInfo.thermalStateDidChangeNotification` and samples once at start, instead of polling on a timer. Thermal state only changes by event, so polling (the earlier ~5 s target) is unnecessary wakeups.
- The popover trend plots a normalized thermal-state level (`TemperatureState.trendLevel`) so the state-only fallback still shows a real, always-present trend. `TemperatureHistory` therefore keeps every sample, not only Celsius ones. When a numeric source exists, `TemperatureSample.trendValue` prefers the Celsius reading.

Alternatives Considered:

- `powermetrics`: rejected for production because it commonly requires elevated privileges and is too heavy for a menu bar sampler.
- Always require SMC/IOKit Celsius: rejected because sensor availability and key names are not stable enough across supported Macs.
- Do not add temperature: rejected as a product direction because thermal pressure is a core reason users reach for lightweight Mac monitoring tools.

Update (2026-05-27): **Numeric Celsius is now wired on Apple Silicon**, privilege-free, keeping thermal state as the always-present source and fallback exactly as decided above. A spike confirmed a usable source on this M1, and the feature shipped as `IOKitTemperatureReader` behind the existing `TemperatureReading` protocol. See [`docs/ai/plans/plan-numeric-celsius-temperature.md`](ai/plans/plan-numeric-celsius-temperature.md), [`docs/ai/specs/spec-numeric-celsius-temperature.md`](ai/specs/spec-numeric-celsius-temperature.md), and [`docs/ai/validation/validation-numeric-celsius-temperature.md`](ai/validation/validation-numeric-celsius-temperature.md).

- **Source (Apple Silicon):** SoC/CPU temperature sensors read via the private `IOHIDEventSystemClient` API. Symbols are resolved at runtime with `dlsym` (no private header linked into the app); services are matched by `PrimaryUsagePage 0xff00` / `PrimaryUsage 0x0005`, and the reader averages the die / core-cluster sensors (names containing `tdie` or `MTR Temp Sensor`) **after** the existing 0–150 °C plausibility clamp. Runs from a normal user process — no `sudo`, no `powermetrics`, no new entitlement. Verified on real M1 hardware: ~44 °C idle, rising to ~50 °C under all-core load.
- **Graceful failure preserved:** a missing symbol, no client, or zero usable sensors yields `celsius = nil` (never a crash), and the UI shows the thermal-state label unchanged — the TD-005 fallback contract still holds.
- **Polling is bounded:** thermal state stays event-driven (`thermalStateDidChangeNotification`); the numeric value is polled on a modest timer (default 3 s) **only while the temperature metric is visible** (`TemperatureSampler.start()`/`stop()`, tied to visibility per TD-003), so most of the event-driven efficiency win is retained.
- **Intel (`SMCTemperatureReader`):** **code-complete; on-hardware evidence deferred** (owner decision 2026-06-15 — no Intel Mac available). The reader reads CPU SMC keys (`TC0P`/`TC0D`/`TCXC`/…) via `IOConnectCallStructMethod` on the `AppleSMC` IOService, decodes `sp78`/`flt ` types, then averages plausible CPU keys after the same 0–150 °C clamp — behind the injectable `SMCKeySource` seam so selection/clamp/averaging/decoding are unit-tested without hardware (`SMCTemperatureReaderTests`). `TemperatureReaderFactory` now selects it on x86_64. Graceful-fallback contract preserved: a missing service, closed connection, unknown key, or unsupported type yields `celsius = nil` (never a crash), so the worst case on an unvalidated Intel Mac is today's state-only behavior — no regression. Real-Intel sign-off (plausible reading under load) remains the one open item. Tracked in `docs/ai/tasks/task-003-smc-reader-intel-optional.md`.
- **Cost (honest):** the IOHID symbols are undocumented private API and can break on a future macOS. Accepted because the app is distributed outside the App Store and self-signed, and because the failure mode is a clean fallback, not a crash. Noted in the README.

## TD-006: Use SMAppService for Launch at Login

Status: Proposed

Decision: For the planned "abrir ao inicializar" feature, use `SMAppService.mainApp` from Apple's `ServiceManagement` framework to register and unregister Mac Metrics View as a login item for the current user. Keep the API behind a small testable service rather than calling it directly from SwiftUI views.

Rationale:

- `SMAppService` is the modern native macOS API for login item registration.
- The app already targets macOS 14, so the modern API is available.
- Direct plist editing, `launchctl`, launch agents, and shell scripts are unnecessary and more fragile.
- Opening at login is a user preference, not a metric setting, so it should not affect sampler lifecycle or metric visibility.

Implications:

- The UI should expose a simple `Abrir ao inicializar` toggle.
- The system status should be the source of truth; `UserDefaults` may cache user intent but must not override macOS status.
- Registration failures must revert or refresh the UI so it does not claim the app will open at login when registration failed.
- Automated tests should use a fake login-item manager instead of touching real macOS login item state.

Alternatives Considered:

- `launchctl` or manual LaunchAgent plist: rejected because it is heavier, harder to test safely, and less appropriate for a bundled macOS app.
- Add the app silently at first launch: rejected because launch-at-login should be an explicit user choice.
- Store only a `UserDefaults` boolean: rejected because it can drift from the actual macOS login item state.

## TD-007: Define RAM "Used" as App Memory + Wired + Compressed

Status: Superseded by TD-011 (formula retained internally; no longer the default menu-bar value)

Decision: Compute displayed RAM usage from `vm_statistics64` as `(internal_page_count - purgeable_count) + wire_count + compressor_page_count`, multiplied by the page size. This approximates Activity Monitor's "Memory Used" (App Memory + Wired Memory + Compressed). Inactive and other file-cache pages are excluded because the system treats them as available.

Rationale:

- The product answers "is my Mac under memory pressure right now?", so the number should track what the system considers actually in use, not reclaimable cache.
- The previous formula (`active + inactive + wire + compressor`) included `inactive`, which is largely reclaimable file cache, and so read consistently higher than Activity Monitor — confusing for users comparing the two.
- `internal_page_count - purgeable_count` is the commonly used approximation of Apple's "App Memory" (anonymous, non-purgeable app pages).

Implications:

- The menu bar still displays GB (not percent); severity thresholds keep using `usedPercent`.
- The reader must guard against `purgeable_count > internal_page_count` to avoid unsigned underflow (clamped to 0).
- The value is still an approximation: it can differ from Activity Monitor by a small amount because Apple's exact accounting is not fully public. It should be close, not bit-exact.

Alternatives Considered:

- Keep `active + inactive + wire + compressor`: rejected because including reclaimable inactive cache overstates usage versus Activity Monitor.
- Align to `active + wire + compressor` (drop only inactive): rejected as a less accurate approximation of App Memory than the internal/purgeable form.
- Report memory pressure level instead of GB: rejected for V1 because the GB figure is the established, glanceable signal and matches the CPU/network pattern.

## TD-008: Suppress Input via CGEventTap for the Cleaning Lock

Status: Accepted

Decision: Implement the temporary keyboard/trackpad lock ("modo limpeza") with a `CGEventTap` installed at the session level that consumes keyboard and pointing-device events while a lock session is active. The tap lives behind a testable `InputLockService` protocol in `Services/`, isolated from UI. The feature is opt-in, requires the user to grant macOS Accessibility permission, and always releases input on timer expiry, emergency abort, or app termination.

Rationale:

- A `CGEventTap` that returns `nil` from its callback is the only privilege-free, stable way to suppress hardware input on macOS without disabling devices via IOKit/`hidutil`.
- Keeping the tap behind a protocol matches the project's "system access isolated from UI, testable with fakes" pattern (Readers/Samplers).
- A glanceable, local-only utility should not require `sudo`, kernel extensions, or device reconfiguration.

Implications:

- **New capability:** the app must request and verify Accessibility permission (`AXIsProcessTrusted`); without it the lock cannot start and the UI must guide the user to System Settings → Privacy & Security → Accessibility.
- **Non-sandbox requirement:** event taps do not work under App Sandbox, so this feature confirms the app is distributed outside the App Store. The Xcode target must remain non-sandboxed. This is a conscious trade-off that **forecloses App Store distribution** while the feature exists.
- **No permanent lockout:** the lock is always bounded by a timer; an always-visible full-screen countdown overlay communicates state; a deliberate, hard-to-trigger emergency abort and a release-on-terminate failsafe guarantee the user is never trapped.
- **Privacy posture:** the tap reads input only to suppress it during an explicit, user-started session. No input is logged, stored, or transmitted — consistent with the local-only, no-telemetry rule.
- Some hardware events (power button, force-restart) are never suppressible by macOS and remain as last-resort escape valves; this is acceptable and intentional.

Alternatives Considered:

- IOKit / `hidutil` to disable HID devices: rejected as heavier, riskier, harder to guarantee clean restore, and worse for testability.
- Block clicks but allow pointer movement: rejected for V1 because the overlay is opaque and the goal is to suppress all accidental input while cleaning.
- Password/biometric unlock before timer end: rejected because the timer (plus emergency abort) is the contract; adding auth complicates the escape path during a lock.
- Not building it: deferred to a product decision — the feature is a deliberate departure from the pure "metrics viewer" identity and is only justified if accepted here first.

## TD-009: In-App Auto-Update via Sparkle with EdDSA-Signed Static Appcast

Status: Accepted

Decision: Add in-app update checking and installation using the Sparkle framework (2.x), fed by a static `appcast.xml` hosted on the existing GitHub Pages site next to the release zip. Update archives are signed with an EdDSA (Ed25519) key; the public key is embedded in `Info.plist` (`SUPublicEDKey`) and Sparkle verifies every download against it. No backend, no CI/CD, no telemetry. The integration lives behind a testable `AppUpdateService` protocol in `Services/`; the concrete Sparkle wrapper is compiled only when the framework is present (`#if canImport(Sparkle)`), so the SPM `swift test` build stays Sparkle-free.

Rationale:

- Sparkle is the de-facto standard for non-App-Store macOS app updates and fits the project's "no backend" reality: the appcast is a static XML file served by the same GitHub Pages site that already hosts the beta zip.
- EdDSA signing gives genuine update integrity **without** an Apple Developer ID. The download is rejected unless it matches the embedded public key, so a tampered or man-in-the-middled archive cannot be installed.
- Sparkle's installer replaces the running bundle in place without re-applying the quarantine flag, so updates it delivers do not re-trigger Gatekeeper — directly relieving the first-launch Gatekeeper friction that the current manual-zip distribution documents.
- Isolating Sparkle behind a protocol matches the project's "system access behind a testable protocol" pattern and preserves the dual SPM + Xcode build: pure update logic (settings, persistence) is unit-tested by `swift test`; the Sparkle wrapper is exercised only in the real Xcode-built app.

Implications:

- **Privacy posture change:** this is the project's first deliberate outbound network call. It fetches a static appcast over HTTPS and sends only the standard Sparkle request headers (app version, OS version, CPU type). Sparkle's optional anonymous system-profiling is **disabled** (`SUEnableSystemProfiling = NO`); no user data, metrics, or input are ever transmitted. This TD is the recorded exception to the "no external network calls" rule in `AGENTS.md`.
- **Versioning must become real:** the app currently ships `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` while distributed as "beta 0.2.1". Sparkle compares `CFBundleVersion` and displays `CFBundleShortVersionString`, so both must be set to accurate, monotonically increasing values per release before auto-update is meaningful.
- **Xcode is the integration path:** Sparkle ships a framework plus XPC services that must be embedded in the `.app`. This is added to the `MacMetricsView.xcodeproj` target (where release builds already come from). The pure-SPM `swift run`/`swift test` path uses a `NoOpUpdateService` and does not link Sparkle.
- **Key custody:** the EdDSA private key is generated with Sparkle's `generate_keys` and stored in the macOS Keychain, never committed. Losing it means future releases cannot be signed for existing installs; this is an operational risk to manage.
- **Signing/notarization still open:** EdDSA secures the update payload, but the app remains ad-hoc-signed and un-notarized. Auto-update works today via EdDSA; obtaining a Developer ID + notarization is a **separate** future decision that would further smooth first-launch trust but is not required for this feature.
- **Persisted-format change:** adds an `UpdateSettings` `UserDefaults` key (auto-check enabled, default on). Backward-compatible — absence reads as the default. Follows the `MetricDisplaySettings` / `LaunchAtLoginSettings` pattern.

Alternatives Considered:

- Custom in-app updater (hand-rolled download + replace): rejected — re-implements Sparkle's signature verification, atomic install, and Gatekeeper handling, with far more risk and no backend savings.
- Homebrew Cask distribution: complementary, not a substitute — it updates via `brew upgrade`, not in-app, and still needs a versioned release feed; can be added later without conflicting with Sparkle.
- A backend update endpoint: rejected — violates the no-backend constraint and adds hosting/ops with no benefit over a static appcast.
- Requiring Developer ID + notarization before shipping auto-update: rejected as a blocker — Sparkle's EdDSA path makes auto-update viable now; notarization is tracked separately so it doesn't gate this feature.
- Doing nothing (manual zip downloads only): rejected — users on older betas have no in-app signal that a new build exists, and every manual install re-incurs the Gatekeeper first-launch friction.

## TD-010: Ship 1.0 Ad-Hoc/EdDSA-Signed, Defer Developer ID Notarization

Status: Accepted

Decision: Ship the first public release **1.0** with the existing distribution posture — ad-hoc-signed, **not** notarized, with update integrity provided by Sparkle's EdDSA signature (TD-009). Promote versioning to a real `MARKETING_VERSION = 1.0.0` and bump `CURRENT_PROJECT_VERSION` monotonically (21 → 22) so the appcast offers 1.0 to existing 0.2.1 installs. Obtaining an Apple Developer ID and notarizing the build is deferred to a separate, non-blocking future decision. Planned and gated in [`docs/ai/plans/plan-release-1.0.md`](ai/plans/plan-release-1.0.md).

Rationale:

- The product is feature-complete for a 1.0 (CPU, RAM, network, temperature, cleaning mode, launch-at-login, PT/EN, in-app auto-update). What separates "beta 0.2.1" from "1.0" is real versioning, closed validation, and consistent branding — not a new capability.
- EdDSA already gives genuine update integrity without a Developer ID (TD-009): every Sparkle-delivered update is verified against the embedded public key. The marginal trust gain of notarization applies mainly to the **first manual install**, not to subsequent in-app updates.
- A paid Apple Developer account and a notarization step are real cost/operational additions; gating the 1.0 on them would delay a release that is otherwise ready.

Implications:

- The Gatekeeper first-launch friction remains for the **initial manual install**, so the site's "primeira abertura" guide stays valid and is **not** removed for 1.0.
- The site should counterbalance this by **highlighting the auto-update**: once installed, the app updates itself with signed archives and those updates do **not** re-trigger Gatekeeper (see the site-improvement analysis in the release plan).
- Versioning becomes real and monotonic; the release follows the existing per-release Sparkle runbook (README → Auto-update). The release artifact drops the "beta" name (`MacMetricsView-1.0.0.zip`).
- Notarization remains tracked as a future decision; adopting it later would let the site drop the first-launch guide entirely.

Alternatives Considered:

- Notarize for 1.0: rejected for now — adds a paid account and a notarization step for a trust gain that mostly affects first install, which EdDSA + the documented guide already handle. Reconsider as a standalone decision.
- Keep shipping as "beta": rejected — the product is feature-complete and validated; perpetual-beta framing understates maturity and confuses the auto-update/version story.
- Leave version at `1.0`/`21`: rejected — `CURRENT_PROJECT_VERSION` must increase or Sparkle won't offer 1.0 to existing installs (TD-009).

Update (2026-05-26): A known side effect of the ad-hoc posture surfaced — macOS TCC keys the **Accessibility** grant to the build's cdhash when there is no stable Developer ID designated requirement. Each new version (manual install *or* Sparkle update) has a different cdhash, so after an update `AXIsProcessTrusted()` returns `false` even though System Settings still lists the stale entry as ON, gating the cleaning lock. The **definitive fix is Developer ID signing + notarization** (still deferred — reopens this decision). Shipped **mitigation**: `AccessibilityGrantTracker` detects a grant that an update reset and the popover instructs the user to remove (−) and re-add the System Settings entry rather than toggle the stale one. See [`docs/ai/plans/plan-accessibility-permission-persistence.md`](ai/plans/plan-accessibility-permission-persistence.md).

Update (2026-05-26, follow-up): The remove/re-add mitigation alone was insufficient — users updating kept hitting "Permissão necessária" because (a) the grant was lost on *every* update, not just detectable ones, and (b) the running process needs to be relaunched after a grant. Adopted a **free fix for AX persistence that does not require an Apple Developer ID**: sign every release with a **stable self-signed certificate** (created once via [`scripts/create-signing-cert.sh`](../scripts/create-signing-cert.sh), applied by [`scripts/sign-app.sh`](../scripts/sign-app.sh)). This changes the designated requirement from a per-build `cdhash` to `identifier "com.pso.MacMetricsView" and certificate leaf = H"…"`, which is **constant across versions**, so TCC preserves the grant through manual installs and Sparkle updates. Verified on the real bundle: `codesign -d -r-` now reports the identifier+leaf requirement and `--verify --deep --strict` passes. Caveats: (1) Gatekeeper first-launch friction is **unchanged** — self-signed is not notarized, so Developer ID + notarization (backlog **B1**) is still the only thing that also smooths first launch and remains the eventual goal; (2) the **one-time** transition from the last ad-hoc build (≤ 1.0.1) to the first stably-signed build still drops the grant once, so users must re-grant a single time on that update. Detection was also broadened to track `lastSeenVersion` (not only `lastGrantedVersion`) so the recovery guidance shows even for users who never had a grant recorded, and the popover now tells users to **quit and reopen** the app after granting. See [`docs/ai/plans/plan-accessibility-permission-persistence.md`](ai/plans/plan-accessibility-permission-persistence.md).

## TD-011: Default RAM Menu Bar to App Memory; Add User-Selectable Pressure

Status: Accepted

Decision: Replace the single sticky "Used" value (TD-007) as the default menu-bar RAM metric with **App Memory** (`(internal − purgeable) × pageSize`, shown in GB), and add **Memory Pressure** (`(wired + compressed) / total`, shown in %) as a user-selectable alternative via `MetricDisplaySettings.ramMenuBarMetric` (`appMemory` default / `pressure`). The popover shows both App Memory and Pressure plus Total; an inline help (info button) explains the difference. The legacy "Used" value (TD-007 formula) is still computed on `RAMSample` for backward compatibility but is no longer surfaced by default. Planned in [`docs/ai/plans/plan-ram-app-memory-and-pressure.md`](ai/plans/plan-ram-app-memory-and-pressure.md).

Rationale:

- **"Used" is sticky and unresponsive.** Wired is near-constant and compressed pages persist after apps close, so opening/closing apps barely moved the value — users perceived it as static and disconnected from their actions. App Memory rises and falls with app usage (confirmed by spike: tracked a 1.2 GB allocation up and back down, while "Used" stayed flat at ~78%).
- **Pressure answers the original product question** ("is my Mac under memory pressure?") more honestly than a sticky GB figure: it stays low/green under normal use and climbs only under real pressure. Reframed as a *separate, optional* signal rather than overloading one number.
- **`(wired + compressed) / total`** is the iStat Menus / Stats convention and read the correct zone versus system state during the spike.

Implications:

- **Behavior change for existing users:** the default menu-bar RAM value changes from "Used" to "App Memory" after update — called out in release notes.
- New `UserDefaults` key `MetricDisplaySettings.ramMenuBarMetric`; absent/invalid → `appMemory` (backward-compatible, no migration of existing keys).
- **Per-metric severity:** Pressure uses thresholds normal `< 60%`, elevated `60–80%`, high `> 80%` (Activity Monitor green/yellow/red analog), distinct from the CPU/App-Memory percent-of-total thresholds (80/90).

Alternatives Considered:

- **Discrete `DispatchSource` memory-pressure level** (normal/warning/critical) as the displayed value: rejected — it is event-driven and only fires on threshold crossings (stayed silent during the spike), so it cannot back a continuously displayed number. Left as a possible future severity override.
- **Page-in/out rate** as the pressure signal: rejected — truest stress indicator but too spiky for a glanceable menu-bar value.
- **Keep "Used" as default, add others in popover only:** rejected — the whole point was a menu-bar value that reflects user action; App Memory must be the default to deliver that.

## TD-012: Reposition as a Dev-First Mac Utilities Hub

Status: Superseded by TD-014

Decision: Ratify Mac Metrics View's identity as a **dev-first Mac utilities hub** spanning four pillars — (1) system metrics (CPU/RAM/network/disk/temperature/battery/GPU), (2) Dev/AI (token & cost tracking for Claude Code, Codex, Gemini CLI), (3) utilities (input-lock cleaning mode), (4) ambient (light-sensor theme suggestion) — superseding the original "narrow resource monitor" framing of the V1 PRD. Target audience is **developers and power users**. The V1 non-goals that conflict with the shipped product (disk/battery monitoring, automations, history analytics) no longer hold; the hard constraints (native-only, local-only, lightweight, menu-bar-first) remain inviolate. Planned in [`docs/ai/plans/plan-dev-utilities-hub-direction.md`](ai/plans/plan-dev-utilities-hub-direction.md).

Rationale:

- **The product already became this.** It shipped to the 2.3.x line, far past V1; the four pillars exist in code today (~27% of the ~11k LOC is non-core-metric: token-tracker ~16%, cleaning/input-lock ~7%, ambient-theme ~4.5%). The canonical narrative lagged: `docs/ai/project-context.md` still listed shipped features ("disk/battery monitoring", "automations") as **non-goals**. This decision aligns stated intent with the real product.
- **Dev-first makes the token-tracker coherent.** The AI token/cost tracker is the largest and most-coupled non-core cluster (169 references in `CPUState`) and only coheres under a developer audience. Choosing dev-first makes it a first-class **pillar** rather than apologized-for sprawl.
- **"Hub" provides a scope filter.** Future work belongs if it serves a developer/power-user at the menu bar — a concrete test, not "anything goes".

Implications:

- `docs/PRD.md` and `docs/ai/project-context.md` updated to state the hub identity and dev-first audience; the conflicting V1 non-goals are annotated as historical.
- **Enables and requires** decoupling the `CPUState` god-object (≈1,200 lines, 169 token refs, orchestrates the 1 Hz UI churn) so the pillars can scale — tracked in the plan; a spec follows.
- **No feature is removed.** No change to the local-only/lightweight/native/menu-bar-first posture; no telemetry or network access added.
- Distribution posture (notarization, TD-010) is unaffected and remains deferred.

Alternatives Considered:

- **Focused monitor** (cut or spin off token-tracker, cleaning-lock, ambient): rejected — discards shipped, working features and a developer audience that values them.
- **Keep everything but stay "resource monitor" in messaging:** rejected — perpetuates the narrative/product mismatch and supplies no scope filter for future decisions.
- **Defer the decision:** rejected — the god-object coupling and documentation drift compound with each added feature; a direction is needed before the next pillar lands.

## TD-013: Decouple Temperature Sampling Cadence from the Metric Update Rate

Status: Accepted

Context: `reevaluateSamplers` drove the temperature sampler at the user's metric update rate (default 1 s in the background, 1 s with the popover open), even though the sampler's own design default was 3 s. The numeric temperature reading is the dominant cost of background sampling (≈ 91 % of sampling-thread time in the round-1 profile), and after caching the HID sensor services (OPT-01) the cadence is the remaining multiplier.

Decision: The temperature sampler runs on a fixed cadence independent of the metric update rate: **3 s in the background** and **2 s while the popover is open**. All other samplers keep the update-rate/1 s behavior.

Rationale:

- SoC/die temperature changes slowly and the menu bar renders whole degrees Celsius, so a 1 s read produces essentially no additional visible change over 3 s — the value rarely differs between consecutive seconds.
- Reading every 3 s instead of 1 s removes ~66 % of the temperature read work, the single largest remaining background cost.
- The popover keeps a faster 2 s cadence so the temperature card/sparkline still feels live without paying the full 1 s cost for a slow signal; the sparkline series is smooth, so a 2 s step is visually indistinguishable from 1 s.
- Behavior-affecting: this is the one deviation from the round-2 "behavior-preserving" invariant, recorded here per the round-1 rule that any cadence change needs an explicit decision.

Implications:

- `AppDelegate` owns two named constants (`temperatureBackgroundInterval = 3`, `temperaturePopoverInterval = 2`); the sampler still receives its interval from `reevaluateSamplers`, so nothing else changes.
- Background temperature ticks still land on the shared epoch grid, so they coalesce with every third 1 s tick of the other samplers.
- Reversible with a one-line constant change if a future energy profile or user feedback argues for it.

Alternatives Considered:

- **Keep 1 s (status quo):** rejected — pays 3× the read cost for a signal that does not change that fast; wastes the OPT-01 win.
- **3 s in both states:** rejected — the open popover is the one place a user is actively watching the value, so 2 s keeps it responsive at modest cost.
- **A user-facing temperature-cadence setting:** rejected — adds configuration surface for a value with no meaningful user-visible tradeoff; a fixed sensible default is simpler.

## TD-014: Focus Product on Machine Resources

Status: Accepted

Decision: Remove AI token and cost tracking from Mac Metrics View. The product focuses on local machine-resource monitoring (CPU, GPU, RAM, network, temperature, disk, and battery) plus existing local utilities: cleaning mode, ambient theme suggestion, and keep-awake controls. This supersedes TD-012's Dev/AI pillar and its claim that the app is a dev-first utilities hub.

Rationale:

- Source tools already provide their own token accounting, so a duplicate tracker adds background work and maintenance without enough product value.
- A clear machine-resource focus keeps the menu bar and popover easier to scan and aligns development effort with the app's durable value.
- The removal preserves the local-only, lightweight, native, and menu-bar-first constraints.

Implications:

- No AI tool logs are read, and no token/cost sampler, reader, model, formatter, or persisted preference is used.
- Existing token `UserDefaults` values remain untouched and inert; no migration is needed.
- TD-012 remains as historical evidence, but its Dev/AI direction is no longer current.

Alternatives Considered:

- **Retain token tracking as an optional metric:** rejected — it keeps the duplicate collection stack and weakens the focused product direction.
- **Delete stored token preferences:** rejected — removed code cannot use them, and clearing user data is unnecessary.

## TD-015: Show RAM as Used / Total Only

Status: Accepted

Decision: The RAM menu-bar segment shows one value only: Activity Monitor-style Memory Used over physical total, formatted as `N.N/NN GB`. The app removes the user-facing RAM metric picker and ignores the legacy `MetricDisplaySettings.ramMenuBarMetric` key. Memory Used remains `(internal_page_count - purgeable_count) + wire_count + compressor_page_count`, multiplied by page size. Reclaimable file cache stays excluded from used memory. Planned in [`docs/ai/plans/plan-ram-used-total-only.md`](ai/plans/plan-ram-used-total-only.md).

Rationale:

- The menu bar should answer one question at a glance: how much RAM is in use on this Mac.
- Multiple RAM modes made the value harder to trust and contradicted the requested screenshot-style display.
- Used/total GB keeps the user's total RAM visible without showing percentages in the menu bar.
- Pressure remains useful for severity coloring, but not as a selectable displayed value.

Implications:

- Existing `appMemory` or `pressure` values in `UserDefaults` no longer change RAM display.
- Settings no longer expose a RAM value picker.
- The popover can still show RAM breakdown rows for context.
- RAM severity still prefers the kernel pressure level, falling back to the existing pressure proxy.
