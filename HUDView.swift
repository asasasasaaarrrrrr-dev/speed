import SwiftUI
import UIKit

struct HUDView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var location: LocationTelemetryManager
    @Binding var isPresented: Bool

    @State private var mirrorVertical: Bool = true
    @State private var mirrorHorizontal: Bool = false
    @State private var hudOpacity: Double = 1.0

    private var displayedSpeed: Double {
        settings.unit.convertSpeed(fromKmh: location.speedKmh)
    }

    private var isOverLimit: Bool {
        settings.speedLimitEnabled && location.speedKmh > settings.speedLimitKmh
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 14) {
                Text(String(format: "%.0f", displayedSpeed))
                    .font(.system(size: 148, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Palette.alertRed : Color.white)

                HStack(spacing: 24) {
                    Text(settings.unit.rawValue)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color.white.opacity(0.7))

                    if location.headingDegrees >= 0 {
                        Text("\(Int(location.headingDegrees))° \(location.compassDirection)")
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.6))
                    }

                    Text(String(format: "%.2f G", location.currentG))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }
            .opacity(hudOpacity)
            .scaleEffect(x: mirrorHorizontal ? -1 : 1, y: mirrorVertical ? -1 : 1)

            // Controls overlay
            VStack {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Label("Закрыть", systemImage: "xmark")
                    }
                    .buttonStyle(GlassPillButtonStyle())

                    Spacer()

                    Button {
                        mirrorVertical.toggle()
                    } label: {
                        Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                    }
                    .buttonStyle(GlassPillButtonStyle(isPrimary: mirrorVertical))

                    Button {
                        mirrorHorizontal.toggle()
                    } label: {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    }
                    .buttonStyle(GlassPillButtonStyle(isPrimary: mirrorHorizontal))
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                HStack(spacing: 12) {
                    Image(systemName: "sun.min")
                        .foregroundStyle(Palette.secondaryText)
                    Slider(value: $hudOpacity, in: 0.25...1.0)
                        .tint(.white)
                    Image(systemName: "sun.max")
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }
}
