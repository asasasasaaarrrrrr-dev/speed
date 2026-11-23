import Foundation
import SwiftUI

enum SpeedUnit: String, CaseIterable, Codable, Identifiable {
    case kmh = "КМ/Ч"
    case mph = "MPH"

    var id: String { rawValue }

    var distanceLabel: String {
        switch self {
        case .kmh: return "КМ"
        case .mph: return "MI"
        }
    }

    func convertSpeed(fromKmh kmh: Double) -> Double {
        switch self {
        case .kmh: return kmh
        case .mph: return kmh * 0.621371
        }
    }

    func convertDistance(fromKm km: Double) -> Double {
        switch self {
        case .kmh: return km
        case .mph: return km * 0.621371
        }
    }
}

enum SpeedScaleMax: Int, CaseIterable, Codable, Identifiable {
    case standard = 240
    case performance = 320

    var id: Int { rawValue }
    var label: String { "\(rawValue)" }
}

enum SpeedTestPhase: String {
    case idle = "ОЖИДАНИЕ"
    case ping = "ЗАМЕР ПИНГА"
    case download = "ЗАГРУЗКА"
    case upload = "ОТДАЧА"
    case finished = "ЗАВЕРШЕНО"
    case error = "ОШИБКА СЕТИ"
}

struct SpeedTestRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let pingMs: Double
    let jitterMs: Double
    let downloadMbps: Double
    let uploadMbps: Double

    init(id: UUID = UUID(), date: Date = Date(), pingMs: Double, jitterMs: Double, downloadMbps: Double, uploadMbps: Double) {
        self.id = id
        self.date = date
        self.pingMs = pingMs
        self.jitterMs = jitterMs
        self.downloadMbps = downloadMbps
        self.uploadMbps = uploadMbps
    }
}

struct AccelRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let zeroToHundred: Double?
    let hundredToTwoHundred: Double?
    let peakSpeedKmh: Double

    init(id: UUID = UUID(), date: Date = Date(), zeroToHundred: Double?, hundredToTwoHundred: Double?, peakSpeedKmh: Double) {
        self.id = id
        self.date = date
        self.zeroToHundred = zeroToHundred
        self.hundredToTwoHundred = hundredToTwoHundred
        self.peakSpeedKmh = peakSpeedKmh
    }
}

final class AppSettings: ObservableObject {
    @AppStorage("vh_speed_unit") var unitRaw: String = SpeedUnit.kmh.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("vh_max_scale") var maxScaleRaw: Int = SpeedScaleMax.standard.rawValue {
        willSet { objectWillChange.send() }
    }
    @AppStorage("vh_speed_limit") var speedLimitKmh: Double = 110 {
        willSet { objectWillChange.send() }
    }
    @AppStorage("vh_speed_limit_enabled") var speedLimitEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("vh_haptics_enabled") var hapticsEnabled: Bool = true {
        willSet { objectWillChange.send() }
    }

    var unit: SpeedUnit {
        get { SpeedUnit(rawValue: unitRaw) ?? .kmh }
        set { unitRaw = newValue.rawValue }
    }

    var maxScale: SpeedScaleMax {
        get { SpeedScaleMax(rawValue: maxScaleRaw) ?? .standard }
        set { maxScaleRaw = newValue.rawValue }
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var speedTests: [SpeedTestRecord] = []
    @Published private(set) var accelRuns: [AccelRecord] = []

    private let speedKey = "vh_history_speedtests_v1"
    private let accelKey = "vh_history_accel_v1"

    init() {
        load()
    }

    func addSpeedTest(_ record: SpeedTestRecord) {
        speedTests.insert(record, at: 0)
        if speedTests.count > 50 {
            speedTests = Array(speedTests.prefix(50))
        }
        save()
    }

    func addAccelRun(_ record: AccelRecord) {
        accelRuns.insert(record, at: 0)
        if accelRuns.count > 50 {
            accelRuns = Array(accelRuns.prefix(50))
        }
        save()
    }

    var bestZeroToHundred: Double? {
        accelRuns.compactMap { $0.zeroToHundred }.min()
    }

    var bestHundredToTwoHundred: Double? {
        accelRuns.compactMap { $0.hundredToTwoHundred }.min()
    }

    func clearAll() {
        speedTests.removeAll()
        accelRuns.removeAll()
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: speedKey),
           let decoded = try? JSONDecoder().decode([SpeedTestRecord].self, from: data) {
            speedTests = decoded
        }
        if let data = UserDefaults.standard.data(forKey: accelKey),
           let decoded = try? JSONDecoder().decode([AccelRecord].self, from: data) {
            accelRuns = decoded
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(speedTests) {
            UserDefaults.standard.set(encoded, forKey: speedKey)
        }
        if let encoded = try? JSONEncoder().encode(accelRuns) {
            UserDefaults.standard.set(encoded, forKey: accelKey)
        }
    }
}
