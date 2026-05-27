# Mac Metrics View

Native macOS menu bar app for compact CPU, RAM, and network metrics.

Menu bar metric identifiers can be shown as compact SF Symbols by default or as explicit `CPU`, `RAM`, and `NET` labels from the popover display control.

## Temperature

On Apple Silicon the temperature metric shows a numeric reading in °C (averaged SoC/CPU
die sensors). This reads private `IOHIDEventSystemClient` sensors — resolved at runtime
via `dlsym`, with **no `sudo`, no `powermetrics`, and no extra entitlement**. Because it
relies on undocumented API, a future macOS could remove it; in that case (or on hardware
with no usable sensor, including Intel Macs where the SMC reader is not yet shipped) the
app **falls back to the thermal-state label** (`Normal`/`Aquecido`/`Quente`/`Crítico`) —
never a crash and no wrong number. The numeric value is polled only while the temperature
metric is visible. See `docs/TECH_DECISIONS.md` TD-005.

## Run

Run the app through the Xcode project so macOS launches `MacMetricsView.app` with a real bundle identifier:

```sh
xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build
open .build/DerivedData/Build/Products/Debug/MacMetricsView.app
```

You can also open `MacMetricsView.xcodeproj` in Xcode and run the `MacMetricsView` scheme.

`swift run` is also supported for development. The package embeds `MacMetricsView/SwiftPMInfo.plist` into the executable so AppKit still receives a bundle identifier:

```sh
swift run
```

## Build Release App

Build a release `.app` artifact:

```sh
xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Release -destination platform=macOS -derivedDataPath .build/DerivedData build
```

The generated app will be here:

```sh
.build/DerivedData/Build/Products/Release/MacMetricsView.app
```

To share it as a zip while preserving macOS bundle metadata:

```sh
ditto -c -k --sequesterRsrc --keepParent .build/DerivedData/Build/Products/Release/MacMetricsView.app MacMetricsView-1.0.0.zip
```

This non-notarized build may require right-clicking the app and choosing Open on first launch (see the site's first-launch guide). Subsequent updates arrive in-app via Sparkle and do not re-trigger Gatekeeper. For a smoother first install, use an Apple Developer ID certificate and notarize the zip so Gatekeeper accepts it normally (deferred — see `docs/TECH_DECISIONS.md` TD-010).

> **Sign the app before zipping it for release.** Releases must be signed with a
> stable self-signed certificate so the macOS Accessibility (TCC) grant survives
> updates — see the per-release runbook below and `docs/TECH_DECISIONS.md`
> TD-010. The plain `xcodebuild` output above is ad-hoc signed (cdhash-keyed
> designated requirement), which is fine for local testing but loses the
> Accessibility grant on every version bump.

## Test

```sh
swift test
```

## Auto-update (Sparkle)

The app checks a static `appcast.xml` (served by GitHub Pages alongside the
release zip) and installs EdDSA-signed updates in place — no backend, no
telemetry, Sparkle's system profiling disabled. The popover exposes a
"Check for updates…" action and an automatic-check toggle (default on).

Sparkle is embedded **only in the Xcode `.app`**. The SPM build (`swift run` /
`swift test`) links a `NoOpUpdateService`, so tests stay Sparkle-free.

### One-time setup

1. **Generate the EdDSA key pair** with Sparkle's tool (the private key is stored
   in the Keychain — never commit it):

   ```sh
   ./bin/generate_keys   # from the Sparkle distribution
   ```

   Copy the printed **public** key into `MacMetricsView/Info.plist` →
   `SUPublicEDKey`, replacing `REPLACE_WITH_EDDSA_PUBLIC_KEY`.

   > Key custody: losing the private key means future builds can no longer be
   > signed for existing installs. Back up the Keychain item securely.

2. **Add Sparkle to the Xcode target** (Sparkle 2.x via Swift Package Manager in
   `MacMetricsView.xcodeproj`, or the binary framework). Ensure
   `Sparkle.framework` **and its XPC services are embedded** in the `.app`
   (Embed & Sign). Do **not** add Sparkle to `Package.swift`.

### One-time setup: stable signing certificate

Run **once per machine**, before your first signed release:

```sh
scripts/create-signing-cert.sh
```

This creates a self-signed code-signing certificate ("Mac Metrics View
Self-Signed") in your login keychain. Every release must be signed with **this
same certificate** so the app's designated requirement stays constant across
versions and the macOS Accessibility (TCC) grant survives updates (see
`docs/TECH_DECISIONS.md` TD-010). Back it up securely (Keychain Access →
right-click the identity → Export); losing it forces all users to re-grant
Accessibility one more time, exactly like the EdDSA key custody note above.

### Per-release runbook (manual, no CI)

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (monotonically) in
   `MacMetricsView.xcodeproj`. Sparkle compares `CFBundleVersion`
   (`CURRENT_PROJECT_VERSION`) and displays `CFBundleShortVersionString`
   (`MARKETING_VERSION`).
2. Build the release app. The extra flags strip debug info and disable code
   coverage so the shipped binary does **not** embed absolute build paths (which
   would leak your macOS username / source layout into the public zip):

   ```sh
   xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Release -destination platform=macOS -derivedDataPath .build/DerivedData clean build \
     ENABLE_CODE_COVERAGE=NO COPY_PHASE_STRIP=YES DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=debugging
   ```

   (The Release config also pins `ENABLE_CODE_COVERAGE = NO`.) After building, you
   can confirm the bundle is clean: `grep -rla "/Users/$(whoami)" .build/DerivedData/Build/Products/Release/MacMetricsView.app` should print nothing.

3. Sign the app with the stable certificate (nested Sparkle code first, main
   bundle last). This is what keeps the Accessibility grant across updates:

   ```sh
   scripts/sign-app.sh .build/DerivedData/Build/Products/Release/MacMetricsView.app
   ```

   The script verifies the signature and prints the designated requirement; it
   must read `identifier "com.pso.MacMetricsView" and certificate leaf = H"…"`
   (**not** a bare `cdhash`). The leaf hash must match every prior release.

4. Zip it preserving bundle metadata:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent .build/DerivedData/Build/Products/Release/MacMetricsView.app docs/downloads/MacMetricsView-<version>.zip
   ```

5. Sign the zip and capture the signature + byte length:

   ```sh
   ./bin/sign_update docs/downloads/MacMetricsView-<version>.zip
   ```

6. Add a new `<item>` to the **top** of `docs/appcast.xml` with the new
   `sparkle:version`, `sparkle:shortVersionString`, `pubDate`, the `enclosure`
   `url`, and the `sparkle:edSignature` / `length` from step 5.
7. Update the site download link, commit, and push — GitHub Pages publishes the
   new zip and appcast.

Updates delivered by Sparkle replace the running bundle without re-applying the
quarantine flag, so they do **not** re-trigger Gatekeeper. The Gatekeeper
right-click-Open step only applies to the initial manual install.
