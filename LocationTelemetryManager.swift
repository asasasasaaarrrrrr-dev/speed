import Foundation
import CoreLocation
import CoreMotion
import UIKit

struct GForcePoint: Identifiable {
    let id = UUID()
    let x: Double
    let y: Double
}

final class LocationTelemetryManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let motionManager = CMMotionManager()

    private var lastValidLocation: CLLocation?
    private var gOffsetX: Double = 0
    private var gOffsetY: Double = 0
    private var rawGX: Double = 0
    private var rawGY: Double = 0

    // Acceleration run state
    private var accelArmed: Bool = false
    private var runStartTime: Date?
    private var hundredReachedTime: Date?
    private var runPeakSpeed: Double = 0

    @Published var isTracking: Bool = false
    @Published var authStatus: CLAuthorizationStatus = .notDetermined
    @Published var statusMessage: String = "GPS отключён"

    @Published var speedKmh: Double = 0
    @Published var maxSpeedKmh: Double = 0
    @Published var distanceKm: Double = 0
    @Published var altitudeMeters: Double = 0
    @Published var headingDegrees: Double = -1
    @Published var accuracyMeters: Double = -1

    @Published var speedHistory: [Double] = Array(repeating: 0, count: 40)

    // G-Force (real accelerometer)
    @Published var gX: Double = 0
    @Published var gY: Double = 0
    @Published var currentG: Double = 0
    @Published var peakG: Double = 0
    @Published var gTrail: [GForcePoint] = []
    @Published var motionAvailable: Bool = false

    // 0-100 / 100-200 live values
    @Published var liveZeroToHundred: Double?
    @Published var liveHundredToTwoHundred: Double?
    @Published var accelStatusText: String = "Ожидание остановки (0 км/ч)"

    var onAccelRunCompleted: ((AccelRecord) -> Void)?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        authStatus = locationManager.authorizationStatus
        motionAvailable = motionManager.isDeviceMotionAvailable
    }

    var signalStrengthBars: Int {
        guard isTracking, accuracyMeters >= 0 else { return 0 }
        if accuracyMeters <= 6 { return 4 }
        if accuracyMeters <= 12 { return 3 }
        if accuracyMeters <= 25 { return 2 }
        return 1
    }

    var compassDirection: String {
        guard headingDegrees >= 0 else { return "—" }
        let dirs = ["С", "СВ", "В", "ЮВ", "Ю", "ЮЗ", "З", "СЗ"]
        let idx = Int((headingDegrees + 22.5) / 45.0) % 8
        return dirs[idx]
    }

    func toggleTracking() {
        if isTracking {
            stopTracking()
        } else {
            startTracking()
        }
    }

    func startTracking() {
        authStatus = locationManager.authorizationStatus
        switch authStatus {
        case .notDetermined:
            statusMessage = "Запрос доступа к GPS..."
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            statusMessage = "Доступ к GPS запрещён в настройках"
            isTracking = false
        case .authorizedWhenInUse, .authorizedAlways:
            beginHardwareUpdates()
        @unknown default:
            break
        }
    }

    func stopTracking() {
        isTracking = false
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        motionManager.stopDeviceMotionUpdates()
        UIApplication.shared.isIdleTimerDisabled = false
        speedKmh = 0
        gX = 0
        gY = 0
        currentG = 0
        gTrail.removeAll()
        statusMessage = "GPS отключён"
    }

    func resetTrip() {
        maxSpeedKmh = 0
        distanceKm = 0
        peakG = 0
        lastValidLocation = nil
        liveZeroToHundred = nil
        liveHundredToTwoHundred = nil
        runStartTime = nil
        hundredReachedTime = nil
        runPeakSpeed = 0
        accelArmed = speedKmh < 1.0
        accelStatusText = accelArmed ? "Готов к старту" : "Ожидание остановки (0 км/ч)"
        speedHistory = Array(repeating: 0, count: 40)
    }

    func calibrateGForce() {
        gOffsetX = rawGX
        gOffsetY = rawGY
        gX = 0
        gY = 0
        currentG = 0
        peakG = 0
        gTrail.removeAll()
    }

    private func beginHardwareUpdates() {
        isTracking = true
        statusMessage = "Поиск спутников..."
        UIApplication.shared.isIdleTimerDisabled = true
        locationManager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        }
        startMotionUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            motionAvailable = false
            return
        }
        motionAvailable = true
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion, self.isTracking else { return }
            self.rawGX = motion.userAcceleration.x
            self.rawGY = motion.userAcceleration.y

            // Low-pass smoothing for readable real G-Force without jitter
            let nx = self.rawGX - self.gOffsetX
            let ny = self.rawGY - self.gOffsetY
            self.gX = self.gX * 0.72 + nx * 0.28
            self.gY = self.gY * 0.72 + ny * 0.28

            let mag = hypot(self.gX, self.gY)
            self.currentG = mag < 0.02 ? 0 : mag
            if self.currentG > self.peakG {
                self.peakG = self.currentG
            }

            self.gTrail.append(GForcePoint(x: self.gX, y: self.gY))
            if self.gTrail.count > 24 {
                self.gTrail.removeFirst()
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authStatus = manager.authorizationStatus
            if self.authStatus == .authorizedWhenInUse || self.authStatus == .authorizedAlways {
                if self.statusMessage == "Запрос доступа к GPS..." {
                    self.beginHardwareUpdates()
                }
            } else if self.authStatus == .denied || self.authStatus == .restricted {
                self.statusMessage = "Доступ к GPS запрещён в настройках"
                self.isTracking = false
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.statusMessage = "Ошибка GPS: \(error.localizedDescription)"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            self.headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking, let location = locations.last else { return }

        DispatchQueue.main.async {
            self.accuracyMeters = location.horizontalAccuracy
            self.altitudeMeters = location.altitude

            guard location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 40 else {
                self.statusMessage = "Слабый сигнал GPS (±\(Int(max(0, location.horizontalAccuracy))) м)"
                return
            }

            self.statusMessage = "GPS активен (±\(Int(location.horizontalAccuracy)) м)"

            // Real speed from GPS or fallback to distance/dt
            var computedKmh: Double = 0
            if location.speed >= 0 {
                computedKmh = location.speed * 3.6
            } else if let prev = self.lastValidLocation {
                let dt = location.timestamp.timeIntervalSince(prev.timestamp)
                if dt > 0.2 {
                    let dist = location.distance(from: prev)
                    computedKmh = (dist / dt) * 3.6
                }
            }

            // Jitter filter below 1.5 km/h
            if computedKmh < 1.5 {
                computedKmh = 0
            }

            self.speedKmh = computedKmh
            if computedKmh > self.maxSpeedKmh {
                self.maxSpeedKmh = computedKmh
            }

            if location.course >= 0 && computedKmh >= 3.0 {
                self.headingDegrees = location.course
            }

            // Distance accumulation
            if let prev = self.lastValidLocation {
                let delta = location.distance(from: prev)
                if delta > 0.8 && delta < 500 && computedKmh > 0 {
                    self.distanceKm += delta / 1000.0
                }
            }
            self.lastValidLocation = location

            // Telemetry history
            self.speedHistory.append(computedKmh)
            if self.speedHistory.count > 40 {
                self.speedHistory.removeFirst()
            }

            // 0-100 / 100-200 real acceleration logic
            self.updateAccelerationTimer(speed: computedKmh, timestamp: location.timestamp)
        }
    }

    private func updateAccelerationTimer(speed: Double, timestamp: Date) {
        if speed < 1.0 {
            if let start = runStartTime, let z100 = liveZeroToHundred, runPeakSpeed >= 100 {
                let record = AccelRecord(
                    zeroToHundred: z100,
                    hundredToTwoHundred: liveHundredToTwoHundred,
                    peakSpeedKmh: runPeakSpeed
                )
                onAccelRunCompleted?(record)
                _ = start
            }
            accelArmed = true
            runStartTime = nil
            hundredReachedTime = nil
            runPeakSpeed = 0
            accelStatusText = "Готов к старту"
            return
        }

        if accelArmed && runStartTime == nil && speed >= 2.5 {
            runStartTime = timestamp
            liveZeroToHundred = nil
            liveHundredToTwoHundred = nil
            runPeakSpeed = speed
            accelStatusText = "Идёт замер 0–100..."
        }

        if let start = runStartTime {
            if speed > runPeakSpeed { runPeakSpeed = speed }

            if liveZeroToHundred == nil && speed >= 100.0 {
                liveZeroToHundred = timestamp.timeIntervalSince(start)
                hundredReachedTime = timestamp
                accelStatusText = "0–100 завершён · Замер 100–200..."
            }

            if let t100 = hundredReachedTime, liveHundredToTwoHundred == nil && speed >= 200.0 {
                liveHundredToTwoHundred = timestamp.timeIntervalSince(t100)
                accelStatusText = "Замер 0–200 завершён"
            }
        }
    }
}
