import SwiftUI

@main
struct MontexSpeedApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var history = HistoryStore()
    @StateObject private var locationManager = LocationTelemetryManager()
    @StateObject private var speedTestManager = NetworkSpeedTestManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(locationManager)
                .environmentObject(speedTestManager)
                .preferredColorScheme(.dark)
        }
    }
}
