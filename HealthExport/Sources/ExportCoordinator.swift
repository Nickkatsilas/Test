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
    @Published var lastFile: URL?

    private var defaults: UserDefaults { .standard }

    /// Runs the export. With `force == false` it only runs once per calendar day (after a successful upload).
    @discardableResult
    func run(force: Bool) async -> Bool {
        guard !isRunning else { return false }

        if !force, let last = defaults.object(forKey: SettingsKey.lastExport) as? Date,
           Calendar.current.isDateInToday(last) {
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

            let name = "health-export-\(Self.fileDate()).csv"
            let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
            try csv.write(to: file, atomically: true, encoding: .utf8)
            lastFile = file

            let raw = (defaults.string(forKey: SettingsKey.endpoint) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else {
                setStatus("Saved \(rowCount) rows locally (\(range)). Set a dashboard URL to upload.")
                return false
            }
            guard let url = URL(string: raw), url.scheme == "https" else {
                setStatus("Dashboard URL must be a valid https:// address")
                return false
            }

            setStatus("Uploading \(rowCount) rows...")
            try await Uploader.upload(csv: Data(csv.utf8), filename: name, range: range,
                                      to: url, token: Keychain.get(SettingsKey.token))
            defaults.set(Date(), forKey: SettingsKey.lastExport)
            setStatus("Uploaded \(rowCount) rows (\(range)) at \(Date().formatted(date: .abbreviated, time: .shortened))")
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
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}
