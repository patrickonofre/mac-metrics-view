# Validation: Release 2.7.1

Date: 2026-08-27
Status: PASS

## Scope

Release Mac Metrics View 2.7.1 after the RAM menu bar correction. Publish the signed app zip, Sparkle appcast entry, and static site download/version copy.

## Evidence

- `xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Release -destination platform=macOS -derivedDataPath .build/ReleaseDD clean build`
  - PASS: Release app built at `.build/ReleaseDD/Build/Products/Release/MacMetricsView.app`.
- `scripts/sign-app.sh .build/ReleaseDD/Build/Products/Release/MacMetricsView.app`
  - PASS: bundle and nested Sparkle code signed with `Mac Metrics View Self-Signed`.
  - PASS: designated requirement uses `identifier "com.pso.MacMetricsView"` and certificate leaf `6ae72354e235b9ea4d51a5bc9dd9f71553d03d4a`.
- `ditto -c -k --sequesterRsrc --keepParent .build/ReleaseDD/Build/Products/Release/MacMetricsView.app docs/downloads/MacMetricsView-2.7.1.zip`
  - PASS: release zip created.
- `.build/ReleaseDD/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update docs/downloads/MacMetricsView-2.7.1.zip`
  - PASS: `sparkle:edSignature="bmhfp9VLfRPxR2bP4jZEf9nSsS47Ha4L9CoGHIXFyvM+7dybdmVkBoG8E8RHJSpFN6oC5liBtb90UHOCZ+k5Cg==" length="2178603"`.
- `scripts/verify-release.sh .build/ReleaseDD/Build/Products/Release/MacMetricsView.app docs/appcast.xml`
  - PASS: plist valid.
  - PASS: appcast XML valid.
  - PASS: signature valid.
  - PASS: public key resolved.
  - PASS: bundle version `2.7.1` matches newest appcast item.
- `node scripts/build-en-page.mjs`
  - PASS: generated `docs/en/index.html`.
- `swift scripts/render_menu_bar_shot.swift docs/assets/menu-bar-2.0.png`
  - PASS: regenerated menu bar shot with RAM `12.4/16 GB`.
- `node scripts/check-i18n-parity.mjs`
  - PASS: 141 PT keys, 141 EN keys, all referenced keys resolve.
- `node scripts/check-site-assets.mjs`
  - PASS: 1 menu-bar PNG and 8 popover PNGs present, sized, within budget.
- `swift test`
  - PASS: 705 tests, 0 failures.

## Handoff

- PM -> Dev: Release 2.7.1 to ship RAM used/total correction. Decision: proceed as patch release.
- Dev -> QA: Bundle version, appcast, zip, and site updated. Evidence: commands above.
- QA -> SecOps: No telemetry/network behavior added. Release signing uses existing self-signed identity. Decision: pass.
- SecOps -> DBA: No persisted format change in release packaging/site work. Decision: n/a.
- DBA -> DevOps: Sparkle appcast newest item points to signed `MacMetricsView-2.7.1.zip`. Decision: pass.
- DevOps -> QA Final: Release build, signature, appcast, site assets, i18n, and tests passed. Decision: pass.
- QA Final -> PM Validate: Ready to push main and tag `v2.7.1`. Pending: remote push/tag availability.
