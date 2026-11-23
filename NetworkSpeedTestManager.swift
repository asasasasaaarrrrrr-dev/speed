import Foundation

final class NetworkSpeedTestManager: NSObject, ObservableObject, URLSessionDataDelegate, URLSessionTaskDelegate {
    @Published var phase: SpeedTestPhase = .idle
    @Published var isRunning: Bool = false
    @Published var liveMbps: Double = 0
    @Published var progress: Double = 0

    @Published var pingMs: Double?
    @Published var jitterMs: Double?
    @Published var downloadMbps: Double?
    @Published var uploadMbps: Double?
    @Published var errorMessage: String?

    @Published var downloadCurve: [Double] = []
    @Published var uploadCurve: [Double] = []

    var onTestCompleted: ((SpeedTestRecord) -> Void)?

    private var session: URLSession!
    private var activeTask: URLSessionTask?
    private var runTask: Task<Void, Never>?

    // Streaming measurement state
    private var stageStart: CFAbsoluteTime = 0
    private var bytesReceived: Int64 = 0
    private var lastSampleTime: CFAbsoluteTime = 0
    private var downloadContinuation: CheckedContinuation<Double, Error>?
    private var uploadContinuation: CheckedContinuation<Double, Error>?

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 35
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    @MainActor
    func startTest() {
        guard !isRunning else { return }

        isRunning = true
        errorMessage = nil
        pingMs = nil
        jitterMs = nil
        downloadMbps = nil
        uploadMbps = nil
        liveMbps = 0
        progress = 0
        downloadCurve = []
        uploadCurve = []

        runTask = Task {
            do {
                // 1. Ping & Jitter (6 real probes)
                phase = .ping
                let (ping, jitter) = try await measurePingAndJitter(samples: 6)
                try Task.checkCancellation()
                pingMs = ping
                jitterMs = jitter
                progress = 0.18

                // 2. Real streaming Download (25 MB)
                phase = .download
                liveMbps = 0
                let dl = try await measureDownload(bytes: 25_000_000)
                try Task.checkCancellation()
                downloadMbps = dl
                progress = 0.62

                // 3. Real streaming Upload (8 MB)
                phase = .upload
                liveMbps = 0
                let ul = try await measureUpload(bytes: 8_000_000)
                try Task.checkCancellation()
                uploadMbps = ul
                liveMbps = dl
                progress = 1.0
                phase = .finished
                isRunning = false

                let record = SpeedTestRecord(
                    pingMs: ping,
                    jitterMs: jitter,
                    downloadMbps: dl,
                    uploadMbps: ul
                )
                onTestCompleted?(record)
            } catch is CancellationError {
                phase = .idle
                isRunning = false
                liveMbps = 0
                progress = 0
            } catch {
                phase = .error
                isRunning = false
                liveMbps = 0
                errorMessage = "Нет ответа от сервера: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    func stopTest() {
        runTask?.cancel()
        runTask = nil
        activeTask?.cancel()
        activeTask = nil

        if let cont = downloadContinuation {
            downloadContinuation = nil
            cont.resume(throwing: CancellationError())
        }
        if let cont = uploadContinuation {
            uploadContinuation = nil
            cont.resume(throwing: CancellationError())
        }

        isRunning = false
        phase = .idle
        liveMbps = 0
        progress = 0
    }

    // MARK: - Ping

    private func measurePingAndJitter(samples: Int) async throws -> (Double, Double) {
        var latencies: [Double] = []
        for i in 0..<samples {
            try Task.checkCancellation()
            guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=0&r=\(UUID().uuidString)") else {
                throw URLError(.badURL)
            }
            var req = URLRequest(url: url)
            req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            req.httpMethod = "GET"

            let t0 = CFAbsoluteTimeGetCurrent()
            let (_, response) = try await session.data(for: req)
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

            if let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) {
                latencies.append(dtMs)
            }

            let stepProgress = 0.18 * Double(i + 1) / Double(samples)
            await MainActor.run {
                self.progress = stepProgress
                if let minPing = latencies.min() {
                    self.pingMs = minPing
                }
            }
        }

        guard !latencies.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }

        let sorted = latencies.sorted()
        let bestPing = sorted.first ?? 0
        var diffs: [Double] = []
        if latencies.count > 1 {
            for idx in 1..<latencies.count {
                diffs.append(abs(latencies[idx] - latencies[idx - 1]))
            }
        }
        let jitter = diffs.isEmpty ? 0 : diffs.reduce(0, +) / Double(diffs.count)
        return (bestPing, jitter)
    }

    // MARK: - Download

    private func measureDownload(bytes: Int) async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)&r=\(UUID().uuidString)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        return try await withCheckedThrowingContinuation { continuation in
            self.downloadContinuation = continuation
            self.bytesReceived = 0
            self.stageStart = CFAbsoluteTimeGetCurrent()
            self.lastSampleTime = self.stageStart
            let task = self.session.dataTask(with: request)
            self.activeTask = task
            task.resume()
        }
    }

    // MARK: - Upload

    private func measureUpload(bytes: Int) async throws -> Double {
        guard let url = URL(string: "https://speed.cloudflare.com/__up") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        // Generate real payload buffer
        var payload = Data(count: bytes)
        payload.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let bound = base.assumingMemoryBound(to: UInt8.self)
            for i in stride(from: 0, to: bytes, by: 64) {
                bound[i] = UInt8.random(in: 0...255)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.uploadContinuation = continuation
            self.stageStart = CFAbsoluteTimeGetCurrent()
            self.lastSampleTime = self.stageStart
            let task = self.session.uploadTask(with: request, from: payload)
            self.activeTask = task
            task.resume()
        }
    }

    // MARK: - URLSession Delegates

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard downloadContinuation != nil else { return }
        bytesReceived += Int64(data.count)
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = max(0.05, now - stageStart)
        let mbps = (Double(bytesReceived) * 8.0) / (elapsed * 1_000_000.0)

        if now - lastSampleTime >= 0.12 {
            lastSampleTime = now
            let expected = max(1, dataTask.countOfBytesExpectedToReceive)
            let frac = expected > 0 ? min(1.0, Double(bytesReceived) / Double(expected)) : 0.5
            DispatchQueue.main.async {
                self.liveMbps = mbps
                self.downloadMbps = mbps
                self.progress = 0.18 + frac * 0.44
                self.downloadCurve.append(mbps)
                if self.downloadCurve.count > 36 { self.downloadCurve.removeFirst() }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard uploadContinuation != nil else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = max(0.05, now - stageStart)
        let mbps = (Double(totalBytesSent) * 8.0) / (elapsed * 1_000_000.0)

        if now - lastSampleTime >= 0.12 {
            lastSampleTime = now
            let frac = totalBytesExpectedToSend > 0 ? min(1.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)) : 0.5
            DispatchQueue.main.async {
                self.liveMbps = mbps
                self.uploadMbps = mbps
                self.progress = 0.62 + frac * 0.36
                self.uploadCurve.append(mbps)
                if self.uploadCurve.count > 36 { self.uploadCurve.removeFirst() }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let elapsed = max(0.05, CFAbsoluteTimeGetCurrent() - stageStart)

        if let cont = downloadContinuation {
            downloadContinuation = nil
            if let error {
                cont.resume(throwing: error)
            } else {
                let finalMbps = (Double(bytesReceived) * 8.0) / (elapsed * 1_000_000.0)
                cont.resume(returning: finalMbps)
            }
            return
        }

        if let cont = uploadContinuation {
            uploadContinuation = nil
            if let error {
                cont.resume(throwing: error)
            } else {
                let sent = max(task.countOfBytesSent, 0)
                let finalMbps = (Double(sent) * 8.0) / (elapsed * 1_000_000.0)
                cont.resume(returning: finalMbps)
            }
        }
    }
}
