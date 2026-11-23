import SwiftUI

struct SpeedometerView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var history: HistoryStore
    @EnvironmentObject var location: LocationTelemetryManager

    @Binding var showHUD: Bool

    private var displayedSpeed: Double {
        settings.unit.convertSpeed(fromKmh: location.speedKmh)
    }

    private var displayedMax: Double {
        settings.unit.convertSpeed(fromKmh: location.maxSpeedKmh)
    }

    private var displayedDistance: Double {
        settings.unit.convertDistance(fromKm: location.distanceKm)
    }

    private var isOverLimit: Bool {
        settings.speedLimitEnabled && location.speedKmh > settings.speedLimitKmh
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerBar

                // Main Arc Gauge Card
                VStack(spacing: 14) {
                    SpeedArcGauge(
                        value: displayedSpeed,
                        maxValue: Double(settings.maxScale.rawValue),
                        unitLabel: settings.unit.rawValue,
                        isOverLimit: isOverLimit
                    )
                    .frame(height: 255)

                    HStack(spacing: 10) {
                        Button {
                            Haptics.impact(.medium, enabled: settings.hapticsEnabled)
                            location.toggleTracking()
                        } label: {
                            Label(
                                location.isTracking ? "Стоп GPS" : "Запустить GPS",
                                systemImage: location.isTracking ? "stop.fill" : "location.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(GlassPillButtonStyle(isPrimary: !location.isTracking))

                        Button {
                            Haptics.impact(.light, enabled: settings.hapticsEnabled)
                            showHUD = true
                        } label: {
                            Label("HUD", systemImage: "rectangle.on.rectangle.angled")
                        }
                        .buttonStyle(GlassPillButtonStyle(isPrimary: false))

                        Button {
                            Haptics.impact(.light, enabled: settings.hapticsEnabled)
                            location.resetTrip()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(GlassPillButtonStyle(isPrimary: false))
                    }
                }
                .liquidGlassCard(cornerRadius: 28, padding: 18)

                // Telemetry Metrics Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    MetricTile(
                        title: "МАКС. СКОРОСТЬ",
                        value: String(format: "%.0f", displayedMax),
                        unit: settings.unit.rawValue,
                        icon: "arrow.up.right"
                    )
                    MetricTile(
                        title: "ДИСТАНЦИЯ",
                        value: String(format: "%.2f", displayedDistance),
                        unit: settings.unit.distanceLabel,
                        icon: "road.lanes"
                    )
                    MetricTile(
                        title: "ВЫСОТА",
                        value: location.isTracking ? String(format: "%.0f", location.altitudeMeters) : "—",
                        unit: "М",
                        icon: "mountain.2"
                    )
                    MetricTile(
                        title: "КУРС",
                        value: location.headingDegrees >= 0 ? "\(Int(location.headingDegrees))°" : "—",
                        unit: location.compassDirection,
                        icon: "safari"
                    )
                }

                // 2D G-Force + Acceleration Timer Row
                HStack(alignment: .top, spacing: 12) {
                    GForceCard(
                        gX: location.gX,
                        gY: location.gY,
                        currentG: location.currentG,
                        peakG: location.peakG,
                        trail: location.gTrail,
                        onCalibrate: {
                            Haptics.impact(.medium, enabled: settings.hapticsEnabled)
                            location.calibrateGForce()
                        }
                    )

                    AccelTimerCard(
                        zeroToHundred: location.liveZeroToHundred,
                        hundredToTwoHundred: location.liveHundredToTwoHundred,
                        bestZeroToHundred: history.bestZeroToHundred,
                        status: location.accelStatusText
                    )
                }

                // Speed History Line Chart
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("ТЕЛЕМЕТРИЯ СКОРОСТИ")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(1.1)
                            .foregroundStyle(Palette.secondaryText)
                        Spacer()
                        Text(location.statusMessage)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(Palette.tertiaryText)
                    }

                    TelemetrySparkline(
                        samples: location.speedHistory,
                        maxValue: max(60, location.maxSpeedKmh)
                    )
                    .frame(height: 68)
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("MONTEX SPEED")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Color.white)
                Text(location.statusMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.secondaryText)
            }

            Spacer()

            // GPS Signal Bars
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { bar in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(bar <= location.signalStrengthBars ? Color.white : Color.white.opacity(0.18))
                        .frame(width: 4, height: CGFloat(bar * 4 + 4))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
    }
}

struct SpeedArcGauge: View {
    let value: Double
    let maxValue: Double
    let unitLabel: String
    let isOverLimit: Bool

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
                let radius = min(size.width, size.height) * 0.44
                let startAngle = Angle.degrees(135)
                let sweep: Double = 270
                let endAngle = Angle.degrees(135 + sweep)

                // Background Track
                var trackPath = Path()
                trackPath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                context.stroke(trackPath, with: .color(Color.white.opacity(0.10)), style: StrokeStyle(lineWidth: 12, lineCap: .round))

                // Tick marks
                let totalTicks = 24
                for i in 0...totalTicks {
                    let frac = Double(i) / Double(totalTicks)
                    let deg = 135 + sweep * frac
                    let rad = deg * .pi / 180
                    let isMajor = i % 4 == 0
                    let innerR = radius - (isMajor ? 22 : 16)
                    let outerR = radius - 9
                    var tick = Path()
                    tick.move(to: CGPoint(x: center.x + cos(rad) * innerR, y: center.y + sin(rad) * innerR))
                    tick.addLine(to: CGPoint(x: center.x + cos(rad) * outerR, y: center.y + sin(rad) * outerR))
                    context.stroke(
                        tick,
                        with: .color(Color.white.opacity(isMajor ? 0.5 : 0.18)),
                        style: StrokeStyle(lineWidth: isMajor ? 2 : 1, lineCap: .round)
                    )
                }

                // Active Arc
                let progress = min(1.0, max(0.0, value / max(1, maxValue)))
                if progress > 0.002 {
                    let activeEnd = Angle.degrees(135 + sweep * progress)
                    var activePath = Path()
                    activePath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: activeEnd, clockwise: false)
                    let strokeColor = isOverLimit ? Palette.alertRed : Color.white
                    context.stroke(activePath, with: .color(strokeColor), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
            }

            VStack(spacing: 2) {
                Text(String(format: "%.0f", value))
                    .font(.system(size: 74, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isOverLimit ? Palette.alertRed : Color.white)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.25, dampingFraction: 0.85), value: Int(value))

                Text(unitLabel)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(Palette.secondaryText)
            }
            .offset(y: 12)
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let unit: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.tertiaryText)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .liquidGlassCard(cornerRadius: 20, padding: 14)
    }
}

struct GForceCard: View {
    let gX: Double
    let gY: Double
    let currentG: Double
    let peakG: Double
    let trail: [GForcePoint]
    let onCalibrate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("G-FORCE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(Palette.secondaryText)
                Spacer()
                Button(action: onCalibrate) {
                    Text("0G")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.12)))
                }
            }

            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) * 0.44

                // Concentric rings (0.5G, 1.0G)
                for scale in [0.5, 1.0] {
                    let r = radius * scale
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                    context.stroke(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.14)), lineWidth: 1)
                }

                // Crosshair
                var cross = Path()
                cross.move(to: CGPoint(x: center.x - radius, y: center.y))
                cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                cross.move(to: CGPoint(x: center.x, y: center.y - radius))
                cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                context.stroke(cross, with: .color(Color.white.opacity(0.10)), lineWidth: 1)

                // Trail
                for (index, pt) in trail.enumerated() {
                    let frac = Double(index + 1) / Double(max(1, trail.count))
                    let px = center.x + CGFloat(max(-1.2, min(1.2, pt.x))) * radius
                    let py = center.y + CGFloat(max(-1.2, min(1.2, pt.y))) * radius
                    let r: CGFloat = 2.5
                    let dot = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: dot), with: .color(Color.white.opacity(frac * 0.35)))
                }

                // Live Dot
                let lx = center.x + CGFloat(max(-1.2, min(1.2, gX))) * radius
                let ly = center.y + CGFloat(max(-1.2, min(1.2, gY))) * radius
                let dotRect = CGRect(x: lx - 5, y: ly - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dotRect), with: .color(Color.white))
            }
            .frame(height: 108)

            HStack {
                Text(String(format: "%.2f G", currentG))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white)
                Spacer()
                Text(String(format: "MAX %.2f", peakG))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        .liquidGlassCard(cornerRadius: 20, padding: 14)
    }
}

struct AccelTimerCard: View {
    let zeroToHundred: Double?
    let hundredToTwoHundred: Double?
    let bestZeroToHundred: Double?
    let status: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("РАЗГОН")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(Palette.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("0 – 100 КМ/Ч")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                    Text(zeroToHundred.map { String(format: "%.2f с", $0) } ?? "—")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("100 – 200 КМ/Ч")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Palette.tertiaryText)
                    Text(hundredToTwoHundred.map { String(format: "%.2f с", $0) } ?? "—")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)

            Divider().background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 2) {
                Text(bestZeroToHundred.map { String(format: "РЕКОРД: %.2f с", $0) } ?? "РЕКОРД: —")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.secondaryText)
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .liquidGlassCard(cornerRadius: 20, padding: 14)
    }
}

struct TelemetrySparkline: View {
    let samples: [Double]
    let maxValue: Double

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }
            let stepX = size.width / CGFloat(samples.count - 1)
            let cap = max(1, maxValue)

            var line = Path()
            for (idx, val) in samples.enumerated() {
                let x = CGFloat(idx) * stepX
                let y = size.height - CGFloat(min(1.0, val / cap)) * (size.height - 6) - 3
                if idx == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }

            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()

            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0.0)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(line, with: .color(Color.white.opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}
