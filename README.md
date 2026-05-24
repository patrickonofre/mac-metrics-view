# Mac Metrics View

Native macOS menu bar app for compact CPU, RAM, and network metrics.

Menu bar metric identifiers can be shown as compact SF Symbols by default or as explicit `CPU`, `RAM`, and `NET` labels from the popover display control.

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

## Build Beta App

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
ditto -c -k --sequesterRsrc --keepParent .build/DerivedData/Build/Products/Release/MacMetricsView.app MacMetricsView-beta.zip
```

For testers close to you, this unsigned/local beta may require right-clicking the app and choosing Open on first launch. For broader distribution, use an Apple Developer ID certificate and notarize the zip so Gatekeeper accepts it normally.

## Test

```sh
swift test
```
