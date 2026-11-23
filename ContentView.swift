import SwiftUI

enum AppTab: Int, CaseIterable {
    case speedometer
    case speedtest
    case journal

    var title: String {
        switch self {
        case .speedometer: return "Спидометр"
        case .speedtest: return "Спидтест"
        case .journal: return "Журнал"
        }
    }

    var icon: String {
        switch self {
        case .speedometer: return "speedometer"
        case .speedtest: return "waveform.path.ecg"
        case .journal: return "list.bullet.rectangle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var locationManager: LocationTelemetryManager
    @EnvironmentObject var speedTestManager: NetworkSpeedTestManager

    @State private var selectedTab: AppTab = .speedometer
    @State private var showHUD: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.background
                .ignoresSafeArea()

            // Subtle ambient monochrome top glow
            RadialGradient(
                colors: [Color.white.opacity(0.06), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 380
            )
            .ignoresSafeArea()

            Group {
                switch selectedTab {
                case .speedometer:
                    SpeedometerView(showHUD: $showHUD)
                case .speedtest:
                    SpeedTestView()
                case .journal:
                    JournalView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            floatingTabBar
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
        .fullScreenCover(isPresented: $showHUD) {
            HUDView(isPresented: $showHUD)
                .environmentObject(settings)
                .environmentObject(locationManager)
        }
        .onAppear {
            locationManager.onAccelRunCompleted = { record in
                history.addAccelRun(record)
            }
            speedTestManager.onTestCompleted = { record in
                history.addSpeedTest(record)
            }
        }
    }

    private var floatingTabBar: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selectedTab = tab
                    }
                    Haptics.impact(.light, enabled: settings.hapticsEnabled)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 15, weight: .semibold))
                        if isSelected {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(isSelected ? Color.black : Palette.secondaryText)
                    .padding(.horizontal, isSelected ? 16 : 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: isSelected ? .infinity : nil)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white : Color.clear)
                    )
                }
            }
        }
        .padding(6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 22, x: 0, y: 12)
        )
    }
}
