import SwiftUI

struct ContentView: View {
    @ObservedObject private var coordinator = ExportCoordinator.shared
    @AppStorage(SettingsKey.endpoint) private var endpoint = ""
    @AppStorage(SettingsKey.daysBack) private var daysBack = 7
    @State private var token = Keychain.get(SettingsKey.token)

    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard") {
                    TextField("https://your-dashboard.com/api/health", text: $endpoint)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API token (optional)", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: token) { _, new in Keychain.set(new, for: SettingsKey.token) }
                }

                Section {
                    Stepper("Days included: \(daysBack)", value: $daysBack, in: 1...365)
                } footer: {
                    Text("Each export re-sends the last \(daysBack) day(s) so late-syncing data (e.g. Apple Watch) is picked up. Raise it once to backfill history.")
                }

                Section("Export") {
                    Button {
                        Task { await coordinator.run(force: true) }
                    } label: {
                        HStack {
                            Text("Export now")
                            if coordinator.isRunning { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(coordinator.isRunning)

                    Text(coordinator.status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if let file = coordinator.lastFile {
                        ShareLink(item: file) { Label("Share latest CSV", systemImage: "square.and.arrow.up") }
                    }
                }

                Section {
                    Text("Runs automatically about once a day in the background. iOS can't read Health while the phone is locked, so if it was locked the export happens the next time it's unlocked or the app is opened.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Health Export")
        }
    }
}
