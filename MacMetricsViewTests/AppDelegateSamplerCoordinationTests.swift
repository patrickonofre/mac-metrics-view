import XCTest
@testable import MacMetricsView

@MainActor
final class AppDelegateSamplerCoordinationTests: XCTestCase {
    
    private var appDelegate: AppDelegate!
    
    override func setUp() {
        super.setUp()
        // Clear updates & visibility defaults
        UserDefaults.standard.removeObject(forKey: "MetricDisplaySettings.updateRate")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showCPU")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showRAM")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showNetwork")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showTemperature")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showDisk")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showTokens")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showBattery")
        
        appDelegate = AppDelegate()
        // Simulate application launch
        appDelegate.applicationDidFinishLaunching(Notification(name: Notification.Name("Test")))
    }
    
    override func tearDown() {
        appDelegate.applicationWillTerminate(Notification(name: Notification.Name("Test")))
        appDelegate = nil
        UserDefaults.standard.removeObject(forKey: "MetricDisplaySettings.updateRate")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showCPU")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showRAM")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showNetwork")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showTemperature")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showDisk")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showTokens")
        UserDefaults.standard.removeObject(forKey: "MetricVisibilitySettings.showBattery")
        super.tearDown()
    }
    
    func testOpeningPopoverStartsAllSamplersAtOneSecond() {
        // Force popover open
        appDelegate.state.isPopoverOpen = true
        
        XCTAssertTrue(appDelegate.cpuSampler.isRunning)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 1.0)
        // Open popover runs at an exact 1s cadence: tolerance must be 0.
        XCTAssertEqual(appDelegate.cpuSampler.tolerance, 0)
        XCTAssertEqual(appDelegate.diskSampler.tolerance, 0)
        XCTAssertEqual(appDelegate.tokenSampler.tolerance, 0)

        XCTAssertTrue(appDelegate.ramSampler.isRunning)
        XCTAssertEqual(appDelegate.ramSampler.interval, 1.0)

        XCTAssertTrue(appDelegate.networkSampler.isRunning)
        XCTAssertEqual(appDelegate.networkSampler.interval, 1.0)
        
        XCTAssertTrue(appDelegate.temperatureSampler.isRunning)
        XCTAssertEqual(appDelegate.temperatureSampler.pollInterval, 1.0)
        
        XCTAssertTrue(appDelegate.diskSampler.isRunning)
        XCTAssertEqual(appDelegate.diskSampler.interval, 1.0)
        
        XCTAssertTrue(appDelegate.tokenSampler.isRunning)
        XCTAssertEqual(appDelegate.tokenSampler.interval, 1.0)
        
        XCTAssertTrue(appDelegate.codexTokenSampler.isRunning)
        XCTAssertEqual(appDelegate.codexTokenSampler.interval, 1.0)

        if BatterySampler.batteryIsPresent() {
            XCTAssertTrue(appDelegate.batterySampler.isRunning)
            XCTAssertEqual(appDelegate.batterySampler.pollInterval, 1.0)
        } else {
            XCTAssertFalse(appDelegate.batterySampler.isRunning)
        }
    }
    
    func testClosingPopoverStartsVisibleSamplersAtBackgroundRateAndStopsHiddenSamplers() {
        // Set background update rate to 3s
        appDelegate.state.metrics.setUpdateRate(3)
        
        // Let's set some visible and some hidden
        appDelegate.state.metrics.setCPUVisible(true)
        appDelegate.state.metrics.setRAMVisible(false)
        appDelegate.state.metrics.setNetworkVisible(true)
        appDelegate.state.metrics.setTemperatureVisible(false)
        appDelegate.state.metrics.setDiskVisible(true)
        appDelegate.state.metrics.setTokenVisible(false)
        appDelegate.state.metrics.setBatteryVisible(false)
        
        // Close popover
        appDelegate.state.isPopoverOpen = false
        
        // Visible metrics: running at 3s background interval with 25% tolerance.
        XCTAssertTrue(appDelegate.cpuSampler.isRunning)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 3.0)
        XCTAssertEqual(appDelegate.cpuSampler.tolerance, 0.75)

        XCTAssertTrue(appDelegate.networkSampler.isRunning)
        XCTAssertEqual(appDelegate.networkSampler.interval, 3.0)
        XCTAssertEqual(appDelegate.networkSampler.tolerance, 0.75)

        XCTAssertTrue(appDelegate.diskSampler.isRunning)
        XCTAssertEqual(appDelegate.diskSampler.interval, 3.0)
        XCTAssertEqual(appDelegate.diskSampler.tolerance, 0.75)
        
        // Hidden metrics: stopped
        XCTAssertFalse(appDelegate.ramSampler.isRunning)
        XCTAssertFalse(appDelegate.temperatureSampler.isRunning)
        XCTAssertFalse(appDelegate.tokenSampler.isRunning)
        XCTAssertFalse(appDelegate.codexTokenSampler.isRunning)
        XCTAssertFalse(appDelegate.batterySampler.isRunning)
    }
    
    func testTogglingVisibilityWhenClosedUpdatesSamplerState() {
        appDelegate.state.metrics.setUpdateRate(2)
        appDelegate.state.isPopoverOpen = false
        
        // Start showing CPU
        appDelegate.state.metrics.setCPUVisible(true)
        XCTAssertTrue(appDelegate.cpuSampler.isRunning)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 2.0)
        // 2s background interval -> 25% tolerance = 0.5.
        XCTAssertEqual(appDelegate.cpuSampler.tolerance, 0.5)

        // Hide CPU
        appDelegate.state.metrics.setCPUVisible(false)
        XCTAssertFalse(appDelegate.cpuSampler.isRunning)

        // Start showing Tokens (which run at 5 * background rate in background)
        appDelegate.state.metrics.setTokenVisible(true)
        XCTAssertTrue(appDelegate.tokenSampler.isRunning)
        XCTAssertEqual(appDelegate.tokenSampler.interval, 10.0)
        // Token interval is 10s -> 25% tolerance = 2.5.
        XCTAssertEqual(appDelegate.tokenSampler.tolerance, 2.5)
        XCTAssertTrue(appDelegate.codexTokenSampler.isRunning)
        XCTAssertEqual(appDelegate.codexTokenSampler.interval, 10.0)

        // Hide Tokens
        appDelegate.state.metrics.setTokenVisible(false)
        XCTAssertFalse(appDelegate.tokenSampler.isRunning)
        XCTAssertFalse(appDelegate.codexTokenSampler.isRunning)
    }

    func testChangingUpdateRateWhileClosedReschedulesActiveSamplers() {
        appDelegate.state.isPopoverOpen = false
        appDelegate.state.metrics.setCPUVisible(true)
        appDelegate.state.metrics.setRAMVisible(false)
        appDelegate.state.metrics.setUpdateRate(3)
        
        XCTAssertEqual(appDelegate.cpuSampler.interval, 3.0)
        
        appDelegate.state.metrics.setUpdateRate(2)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 2.0)
        
        // Hidden sampler stays stopped
        XCTAssertFalse(appDelegate.ramSampler.isRunning)
    }
}
