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
        
        XCTAssertTrue(appDelegate.geminiTokenSampler.isRunning)
        XCTAssertEqual(appDelegate.geminiTokenSampler.interval, 1.0)
        
        if BatterySampler.batteryIsPresent() {
            XCTAssertTrue(appDelegate.batterySampler.isRunning)
            XCTAssertEqual(appDelegate.batterySampler.pollInterval, 1.0)
        } else {
            XCTAssertFalse(appDelegate.batterySampler.isRunning)
        }
    }
    
    func testClosingPopoverStartsVisibleSamplersAtBackgroundRateAndStopsHiddenSamplers() {
        // Set background update rate to 3s
        appDelegate.state.setUpdateRate(3)
        
        // Let's set some visible and some hidden
        appDelegate.state.setCPUVisible(true)
        appDelegate.state.setRAMVisible(false)
        appDelegate.state.setNetworkVisible(true)
        appDelegate.state.setTemperatureVisible(false)
        appDelegate.state.setDiskVisible(true)
        appDelegate.state.setTokenVisible(false)
        appDelegate.state.setBatteryVisible(false)
        
        // Close popover
        appDelegate.state.isPopoverOpen = false
        
        // Visible metrics: running at 3s background interval
        XCTAssertTrue(appDelegate.cpuSampler.isRunning)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 3.0)
        
        XCTAssertTrue(appDelegate.networkSampler.isRunning)
        XCTAssertEqual(appDelegate.networkSampler.interval, 3.0)
        
        XCTAssertTrue(appDelegate.diskSampler.isRunning)
        XCTAssertEqual(appDelegate.diskSampler.interval, 3.0)
        
        // Hidden metrics: stopped
        XCTAssertFalse(appDelegate.ramSampler.isRunning)
        XCTAssertFalse(appDelegate.temperatureSampler.isRunning)
        XCTAssertFalse(appDelegate.tokenSampler.isRunning)
        XCTAssertFalse(appDelegate.codexTokenSampler.isRunning)
        XCTAssertFalse(appDelegate.geminiTokenSampler.isRunning)
        XCTAssertFalse(appDelegate.batterySampler.isRunning)
    }
    
    func testTogglingVisibilityWhenClosedUpdatesSamplerState() {
        appDelegate.state.setUpdateRate(2)
        appDelegate.state.isPopoverOpen = false
        
        // Start showing CPU
        appDelegate.state.setCPUVisible(true)
        XCTAssertTrue(appDelegate.cpuSampler.isRunning)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 2.0)
        
        // Hide CPU
        appDelegate.state.setCPUVisible(false)
        XCTAssertFalse(appDelegate.cpuSampler.isRunning)
        
        // Start showing Tokens (which run at 5 * background rate in background)
        appDelegate.state.setTokenVisible(true)
        XCTAssertTrue(appDelegate.tokenSampler.isRunning)
        XCTAssertEqual(appDelegate.tokenSampler.interval, 10.0)
        XCTAssertTrue(appDelegate.codexTokenSampler.isRunning)
        XCTAssertEqual(appDelegate.codexTokenSampler.interval, 10.0)
        XCTAssertTrue(appDelegate.geminiTokenSampler.isRunning)
        XCTAssertEqual(appDelegate.geminiTokenSampler.interval, 10.0)
        
        // Hide Tokens
        appDelegate.state.setTokenVisible(false)
        XCTAssertFalse(appDelegate.tokenSampler.isRunning)
        XCTAssertFalse(appDelegate.codexTokenSampler.isRunning)
        XCTAssertFalse(appDelegate.geminiTokenSampler.isRunning)
    }

    func testChangingUpdateRateWhileClosedReschedulesActiveSamplers() {
        appDelegate.state.isPopoverOpen = false
        appDelegate.state.setCPUVisible(true)
        appDelegate.state.setRAMVisible(false)
        appDelegate.state.setUpdateRate(3)
        
        XCTAssertEqual(appDelegate.cpuSampler.interval, 3.0)
        
        appDelegate.state.setUpdateRate(2)
        XCTAssertEqual(appDelegate.cpuSampler.interval, 2.0)
        
        // Hidden sampler stays stopped
        XCTAssertFalse(appDelegate.ramSampler.isRunning)
    }
}
