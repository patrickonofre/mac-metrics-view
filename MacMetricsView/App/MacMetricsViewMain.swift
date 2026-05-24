import AppKit
import Darwin

@main
enum MacMetricsViewMain {
    @MainActor
    static func main() {
        guard Bundle.main.bundleIdentifier != nil else {
            let message = """
            MacMetricsView must be launched from an app bundle.
            If you are in Xcode, open MacMetricsView.xcodeproj and run the app target scheme.
            Do not run the Swift Package scheme or `swift run`.

            From Terminal, use:
            xcodebuild -project MacMetricsView.xcodeproj -scheme MacMetricsView -configuration Debug -destination platform=macOS -derivedDataPath .build/DerivedData build
            open .build/DerivedData/Build/Products/Debug/MacMetricsView.app

            """
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()

        app.delegate = delegate
        app.run()
    }
}
