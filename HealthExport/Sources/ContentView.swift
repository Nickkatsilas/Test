import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SummaryView()
                .tabItem { Label("Summary", systemImage: "heart.text.square") }
            ExportView()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
    }
}

struct ExportView: View {
    @ObservedObject private var coordinator = ExportCoordinator.shared
    @AppStorage(SettingsKey.endpoint) private var endpoint = ""
    @AppStorage(SettingsKey.daysBack) private var daysBack = 7
    @AppStorage(SettingsKey.hourly) private var includeHourly = true
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

                Section {
                    Toggle("Include hourly data", isOn: $includeHourly)
                } footer: {
                    Text("Hour-by-hour heart rate, steps, energy, HRV, respiratory rate and blood oxygen (last 14 days max). Turn off for smaller uploads.")
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

                    ForEach(coordinator.lastFiles, id: \.self) { file in
                        ShareLink(item: file) { Label(file.lastPathComponent, systemImage: "square.and.arrow.up") }
                    }
                }

                Section {
                    Text("Runs automatically in the background: when new Health data arrives, on unlock, and at least hourly via iOS background refresh. Successful uploads are spaced 3+ hours apart; failed or locked-phone attempts retry on the next trigger.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Health Export")
        }
    }
}
