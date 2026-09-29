import Foundation
import BackgroundTasks
import UIKit

enum SettingsKey {
    static let endpoint = "endpointURL"
    static let daysBack = "daysBack"
    static let lastExport = "lastExportDate"
    static let lastStatus = "lastStatus"
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

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let name = "health-export-\(Self.fileDate()).csv"
            let samplesName = "health-samples-\(Self.fileDate()).csv"
            try csv.write(to: docs.appendingPathComponent(name), atomically: true, encoding: .utf8)
            try samplesCSV.write(to: docs.appendingPathComponent(samplesName), atomically: true, encoding: .utf8)
            lastFiles = [docs.appendingPathComponent(name), docs.appendingPathComponent(samplesName)]

            let raw = (defaults.string(forKey: SettingsKey.endpoint) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                setStatus("Saved \(rowCount) rows locally (\(range)). Set a dashboard URL to upload.")
                return false
            }
            guard let url = URL(string: raw), url.scheme == "https" else {
                setStatus("Dashboard URL must be a valid https:// address")
                return false
            }

            setStatus("Uploading \(rowCount) daily rows + \(sampleCount) samples...")
            let token = Keychain.get(SettingsKey.token)
            try await Uploader.upload(csv: Data(csv.utf8), filename: name, range: range,
                                      dataset: "daily", to: url, token: token)
            try await Uploader.upload(csv: Data(samplesCSV.utf8), filename: samplesName, range: range,
                                      dataset: "samples", to: url, token: token)
            defaults.set(Date(), forKey: SettingsKey.lastExport)
            setStatus("Uploaded \(rowCount) daily rows + \(sampleCount) samples (\(range)) at \(Date().formatted(date: .abbreviated, time: .shortened))")
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
