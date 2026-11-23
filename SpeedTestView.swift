import SwiftUI

struct SpeedTestView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var net: NetworkSpeedTestManager

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SPEEDTEST")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(2.0)
                            .foregroundStyle(Color.white)
                        Text("Cloudflare Edge · Прямой замер")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    Text(net.phase.rawValue)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(net.phase == .error ? Palette.alertRed : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }

                // Logarithmic Gauge Card
                VStack(spacing: 16) {
                    LogSpeedGauge(mbps: net.liveMbps, progress: net.progress)
                        .frame(height: 245)

                    if let err = net.errorMessage {
                        Text(err)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Palette.alertRed)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Haptics.impact(.medium, enabled: settings.hapticsEnabled)
                        if net.isRunning {
                            net.stopTest()
                        } else {
                            net.startTest()
                        }
                    } label: {
                        Label(
                            net.isRunning ? "Остановить замер" : "Начать замер",
                            systemImage: net.isRunning ? "stop.fill" : "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GlassPillButtonStyle(isPrimary: !net.isRunning))
                }
                .liquidGlassCard(cornerRadius: 28, padding: 18)

                // Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricTile(
                        title: "ЗАГРУЗКА",
                        value: net.downloadMbps.map { String(format: "%.1f", $0) } ?? "—",
                        unit: "Мбит/с",
                        icon: "arrow.down"
                    )
                    MetricTile(
                        title: "ОТДАЧА",
                        value: net.uploadMbps.map { String(format: "%.1f", $0) } ?? "—",
                        unit: "Мбит/с",
                        icon: "arrow.up"
                    )
                    MetricTile(
                        title: "ПИНГ",
                        value: net.pingMs.map { String(format: "%.0f", $0) } ?? "—",
                        unit: "мс",
                        icon: "bolt"
                    )
                    MetricTile(
                        title: "ДЖИТТЕР",
                        value: net.jitterMs.map { String(format: "%.1f", $0) } ?? "—",
                        unit: "мс",
                        icon: "waveform"
                    )
                }

                // Dual-layer Live Graph
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ГРАФИК ПОТОКА")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        HStack(spacing: 10) {
                            Label("DL", systemImage: "circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white)
                            Label("UL", systemImage: "circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                        }
                    }

                    DualCurveChart(primary: net.downloadCurve, secondary: net.uploadCurve)
                        .frame(height: 84)
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)

                // Channel Readiness
                VStack(alignment: .leading, spacing: 10) {
                    Text("ОЦЕНКА КАНАЛА")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Palette.secondaryText)

                    ReadinessRow(title: "4K Стриминг", ready: (net.downloadMbps ?? 0) >= 25, hasData: net.downloadMbps != nil)
                    ReadinessRow(title: "Облачный гейминг", ready: (net.downloadMbps ?? 0) >= 35 && (net.pingMs ?? 999) <= 45, hasData: net.downloadMbps != nil && net.pingMs != nil)
                    ReadinessRow(title: "Видеозвонки HD", ready: (net.uploadMbps ?? 0) >= 5 && (net.pingMs ?? 999) <= 80, hasData: net.uploadMbps != nil)
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }
}

struct LogSpeedGauge: View {
    let mbps: Double
    let progress: Double

    // Logarithmic mapping 0..1000 Mbps -> 0..1
    private var logNormalized: Double {
        guard mbps > 0 else { return 0 }
        return min(1.0, log10(1.0 + mbps) / log10(1001.0))
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
                let radius = min(size.width, size.height) * 0.44
                let startAngle = Angle.degrees(135)
                let sweep: Double = 270
                let endAngle = Angle.degrees(135 + sweep)

                var track = Path()
                track.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                context.stroke(track, with: .color(Color.white.opacity(0.10)), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                // Outer thin progress ring
                if progress > 0 {
                    var prog = Path()
                    prog.addArc(center: center, radius: radius + 14, startAngle: startAngle, endAngle: Angle.degrees(135 + sweep * min(1, progress)), clockwise: false)
                    context.stroke(prog, with: .color(Color.white.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }

                // Active speed arc
                if logNormalized > 0.002 {
                    var active = Path()
                    active.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: Angle.degrees(135 + sweep * logNormalized), clockwise: false)
                    context.stroke(active, with: .color(Color.white), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }

            VStack(spacing: 3) {
                Text(String(format: "%.1f", mbps))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.15), value: mbps)

                Text("МБИТ/С")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Palette.secondaryText)
            }
            .offset(y: 12)
        }
    }
}

struct DualCurveChart: View {
    let primary: [Double]
    let secondary: [Double]

    var body: some View {
        Canvas { context, size in
            let maxVal = max(10, (primary + secondary).max() ?? 10)
            drawSeries(primary, maxVal: maxVal, color: .white, in: &context, size: size)
            drawSeries(secondary, maxVal: maxVal, color: Color.white.opacity(0.45), in: &context, size: size)
        }
    }

    private func drawSeries(_ values: [Double], maxVal: Double, color: Color, in context: inout GraphicsContext, size: CGSize) {
        guard values.count > 1 else { return }
        let step = size.width / CGFloat(values.count - 1)
        var path = Path()
        for (i, v) in values.enumerated() {
            let x = CGFloat(i) * step
            let y = size.height - CGFloat(min(1.0, v / maxVal)) * (size.height - 8) - 4
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

struct ReadinessRow: View {
    let title: String
    let ready: Bool
    let hasData: Bool

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
            Spacer()
            if !hasData {
                Text("—")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.tertiaryText)
            } else {
                Label(ready ? "Готово" : "Слабо", systemImage: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ready ? Color.white : Palette.secondaryText)
            }
        }
    }
}
