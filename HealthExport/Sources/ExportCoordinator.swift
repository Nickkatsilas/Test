import Foundation
import BackgroundTasks
import UIKit

enum SettingsKey {
    static let endpoint = "endpointURL"
    static let daysBack = "daysBack"
    static let lastExport = "lastExportDate"
    static let lastStatus = "lastStatus"
    static let hourly = "includeHourly"
    static let token = "uploadToken"   // stored in the Keychain
}

@MainActor
final class ExportCoordinator: ObservableObject {
    static let shared = ExportCoordinator()
    nonisolated static let refreshTaskID = "com.lapota.healthexport.refresh"

    @Published var status: String = UserDefaults.standard.string(forKey: SettingsKey.lastStatus) ?? "Not exported yet"
    @Published var isRunning = false
    @Published var lastFiles: [URL] = []

    private var defaults: UserDefaults { .standard }

    /// Minimum gap between successful automatic uploads; failures/locked-phone runs retry on every trigger.
    private static let minInterval: TimeInterval = 3 * 3600

    /// Runs the export. With `force == false` it skips if a successful upload happened within `minInterval`.
    @discardableResult
    func run(force: Bool) async -> Bool {
        guard !isRunning else { return false }

        if !force, let last = defaults.object(forKey: SettingsKey.lastExport) as? Date,
           Date().timeIntervalSince(last) < Self.minInterval {
            return true
        }
        guard HealthExporter.isAvailable else { setStatus("Health data isn't available on this device"); return false }
        guard UIApplication.shared.isProtectedDataAvailable else {
            setStatus("Phone was locked - will retry when unlocked")
            return false
        }

        isRunning = true
        defer { isRunning = false }

        do {
            try await HealthExporter.requestAuthorization()
            let days = defaults.object(forKey: SettingsKey.daysBack) as? Int ?? 7
            setStatus("Reading Health data...")
            let (csv, rowCount, range) = try await HealthExporter.buildCSV(daysBack: days)
            let (samplesCSV, sampleCount) = try await HealthExporter.buildSamplesCSV(daysBack: days)
            let (profileCSV, _) = HealthExporter.buildProfileCSV()

            let date = Self.fileDate()
            var datasets: [(kind: String, name: String, csv: String)] = [
                ("daily", "health-export-\(date).csv", csv),
                ("samples", "health-samples-\(date).csv", samplesCSV),
                ("profile", "health-profile-\(date).csv", profileCSV),
            ]
            var hourlyCount = 0
            if defaults.object(forKey: SettingsKey.hourly) as? Bool ?? true {
                let (hourlyCSV, n) = try await HealthExporter.buildHourlyCSV(daysBack: days)
                hourlyCount = n
                datasets.append(("hourly", "health-hourly-\(date).csv", hourlyCSV))
            }
            let counts = "\(rowCount) daily, \(sampleCount) samples, \(hourlyCount) hourly"

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            for d in datasets { try d.csv.write(to: docs.appendingPathComponent(d.name), atomically: true, encoding: .utf8) }
            lastFiles = datasets.map { docs.appendingPathComponent($0.name) }

            let raw = (defaults.string(forKey: SettingsKey.endpoint) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                setStatus("Saved locally: \(counts) (\(range)). Set a dashboard URL to upload.")
                return false
            }
            guard let url = URL(string: raw), url.scheme == "https" else {
                setStatus("Dashboard URL must be a valid https:// address")
                return false
            }

            setStatus("Uploading \(counts)...")
            let token = Keychain.get(SettingsKey.token)
            for d in datasets {
                try await Uploader.upload(csv: Data(d.csv.utf8), filename: d.name, range: range,
                                          dataset: d.kind, to: url, token: token)
            }
            defaults.set(Date(), forKey: SettingsKey.lastExport)
            setStatus("Uploaded \(counts) (\(range)) at \(Date().formatted(date: .abbreviated, time: .shortened))")
            return true
        } catch {
            setStatus("Export failed: \(error.localizedDescription)")
            return false
        }
    }

    private func setStatus(_ text: String) {
        status = text
        defaults.set(text, forKey: SettingsKey.lastStatus)
    }

    private static func fileDate() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Asks iOS to wake the app again. iOS decides the exact time; this is a "no sooner than" hint.
    nonisolated static func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
