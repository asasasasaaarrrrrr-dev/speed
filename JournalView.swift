import SwiftUI

struct JournalView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var history: HistoryStore

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM · HH:mm"
        return f
    }()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ЖУРНАЛ И НАСТРОЙКИ")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .tracking(2.0)
                            .foregroundStyle(Color.white)
                        Text("Только реальные замеры")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.secondaryText)
                    }
                    Spacer()
                    if !history.speedTests.isEmpty || !history.accelRuns.isEmpty {
                        Button("Очистить") {
                            Haptics.impact(.light, enabled: settings.hapticsEnabled)
                            history.clearAll()
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.secondaryText)
                    }
                }

                // Settings Card
                VStack(alignment: .leading, spacing: 14) {
                    Text("ПАРАМЕТРЫ")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Palette.secondaryText)

                    HStack {
                        Text("Единицы скорости")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Picker("", selection: $settings.unit) {
                            ForEach(SpeedUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Шкала спидометра")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Picker("", selection: $settings.maxScale) {
                            ForEach(SpeedScaleMax.allCases) { s in
                                Text(s.label).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 140)
                    }

                    Toggle(isOn: $settings.speedLimitEnabled) {
                        Text("Предупреждение о лимите (\(Int(settings.speedLimitKmh)) км/ч)")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .tint(.white)

                    if settings.speedLimitEnabled {
                        Slider(value: $settings.speedLimitKmh, in: 40...220, step: 10)
                            .tint(.white)
                    }

                    Toggle(isOn: $settings.hapticsEnabled) {
                        Text("Тактильный отклик (Haptics)")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .tint(.white)
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)

                // Speedtest History
                VStack(alignment: .leading, spacing: 12) {
                    Text("ИСТОРИЯ СПИДТЕСТОВ")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Palette.secondaryText)

                    if history.speedTests.isEmpty {
                        Text("Замеров сети пока нет.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(history.speedTests) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dateFormatter.string(from: item.date))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Palette.secondaryText)
                                    Text(String(format: "Ping %.0f мс · Jitter %.1f мс", item.pingMs, item.jitterMs))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "↓ %.1f Мбит/с", item.downloadMbps))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    Text(String(format: "↑ %.1f Мбит/с", item.uploadMbps))
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Palette.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                            if item.id != history.speedTests.last?.id {
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)

                // Acceleration History
                VStack(alignment: .leading, spacing: 12) {
                    Text("ИСТОРИЯ РАЗГОНОВ")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(Palette.secondaryText)

                    if history.accelRuns.isEmpty {
                        Text("Завершённых заездов 0–100 пока нет.")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    } else {
                        ForEach(history.accelRuns) { run in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(dateFormatter.string(from: run.date))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(Palette.secondaryText)
                                    Text(String(format: "Пик %.0f км/ч", run.peakSpeedKmh))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Palette.tertiaryText)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    if let z100 = run.zeroToHundred {
                                        Text(String(format: "0–100: %.2f с", z100))
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    }
                                    if let h200 = run.hundredToTwoHundred {
                                        Text(String(format: "100–200: %.2f с", h200))
                                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                                            .foregroundStyle(Palette.secondaryText)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                            if run.id != history.accelRuns.last?.id {
                                Divider().background(Color.white.opacity(0.08))
                            }
                        }
                    }
                }
                .liquidGlassCard(cornerRadius: 22, padding: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
    }
}
