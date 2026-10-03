import SwiftUI
import Charts

struct DayPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

/// A metric shown on the Summary tab. `key` is "metric|stat" from the daily export rows.
struct MetricDef {
    let key: String
    let title: String
    let unit: String
    var scale = 1.0              // converts the exported unit to the displayed unit
    var decimals = 0
    var cumulative = false       // daily totals: today is partial, so skip it when comparing
    var minRelChange = 0.05      // ignore flags smaller than this fraction of the usual value

    var metric: String { String(key.split(separator: "|")[0]) }

    private static let imperial = Locale.current.measurementSystem == .us

    static let all: [MetricDef] = [
        MetricDef(key: "steps|sum", title: "Steps", unit: "", cumulative: true),
        MetricDef(key: "active_energy|sum", title: "Active energy", unit: "kcal", cumulative: true),
        MetricDef(key: "exercise_minutes|sum", title: "Exercise", unit: "min", cumulative: true),
        MetricDef(key: "sleep_total_asleep|sum", title: "Sleep", unit: "hr", decimals: 1),
        MetricDef(key: "resting_heart_rate|avg", title: "Resting heart rate", unit: "bpm", minRelChange: 0.05),
        MetricDef(key: "heart_rate|avg", title: "Average heart rate", unit: "bpm"),
        MetricDef(key: "hrv_sdnn|avg", title: "HRV", unit: "ms", decimals: 1, minRelChange: 0.15),
        MetricDef(key: "blood_oxygen|avg", title: "Blood oxygen", unit: "%", scale: 100, decimals: 1, minRelChange: 0.02),
        MetricDef(key: "respiratory_rate|avg", title: "Respiratory rate", unit: "br/min", decimals: 1, minRelChange: 0.10),
        MetricDef(key: "vo2_max|avg", title: "VO2 max", unit: "mL/kg/min", decimals: 1),
        MetricDef(key: "body_mass|avg", title: "Weight", unit: imperial ? "lb" : "kg",
                  scale: imperial ? 2.20462 : 1, decimals: 1, minRelChange: 0.02),
        MetricDef(key: "body_fat|avg", title: "Body fat", unit: "%", scale: 100, decimals: 1, minRelChange: 0.05),
        MetricDef(key: "dietary_energy|sum", title: "Calories eaten", unit: "kcal", cumulative: true, minRelChange: 0.20),
        MetricDef(key: "dietary_protein|sum", title: "Protein", unit: "g", cumulative: true, minRelChange: 0.25),
        MetricDef(key: "dietary_carbs|sum", title: "Carbs", unit: "g", cumulative: true, minRelChange: 0.25),
        MetricDef(key: "dietary_fat|sum", title: "Fat", unit: "g", cumulative: true, minRelChange: 0.25),
        MetricDef(key: "dietary_sodium|sum", title: "Sodium", unit: "mg", cumulative: true, minRelChange: 0.25),
        MetricDef(key: "walking_steadiness|avg", title: "Walking steadiness", unit: "%", scale: 100),
    ]

    func format(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(decimals)))
    }
}

@MainActor
final class SummaryModel: ObservableObject {
    struct Flag: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    struct Card: Identifiable {
        var id: String { def.key }
        let def: MetricDef
        let points: [DayPoint]
        let latest: DayPoint
        let avg7: Double?
        let prev7: Double?
        let flag: Flag?
    }

    @Published var cards: [Card] = []
    @Published var flags: [Flag] = []
    @Published var loading = false
    @Published var message: String?

    func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard HealthExporter.isAvailable else { message = "Health data isn't available on this device."; return }
        guard UIApplication.shared.isProtectedDataAvailable else { message = "Unlock your phone to read Health data."; return }
        do {
            try await HealthExporter.requestAuthorization()
            let metrics = Set(MetricDef.all.map(\.metric))
            let rows = try await HealthExporter.dailyRows(daysBack: 35, only: metrics)
            build(rows)
            message = cards.isEmpty ? "No Health data found yet. Check Settings > Health > Data Access." : nil
        } catch {
            message = "Couldn't read Health data: \(error.localizedDescription)"
        }
    }

    private func build(_ rows: [ExportRow]) {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"

        var series: [String: [DayPoint]] = [:]
        for r in rows {
            guard let date = parser.date(from: r.date) else { continue }
            series["\(r.metric)|\(r.stat)", default: []].append(DayPoint(date: date, value: r.value))
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var newCards: [Card] = []

        for def in MetricDef.all {
            let all = (series[def.key] ?? []).sorted { $0.date < $1.date }
                .map { DayPoint(date: $0.date, value: $0.value * def.scale) }
            // Daily totals for today are still accumulating, so compare using complete days only.
            let complete = def.cumulative ? all.filter { $0.date < today } : all
            guard let latest = complete.last else { continue }

            func mean(_ pts: [DayPoint]) -> Double? { pts.isEmpty ? nil : pts.map(\.value).reduce(0, +) / Double(pts.count) }
            func days(_ from: Int, _ to: Int) -> [DayPoint] {
                complete.filter {
                    let d = cal.dateComponents([.day], from: $0.date, to: latest.date).day ?? 99
                    return d >= from && d <= to
                }
            }

            var flag: Flag?
            let baseline = Array(complete.dropLast().suffix(28)).map(\.value)
            if baseline.count >= 10, let m = mean(complete.dropLast().suffix(28).map { $0 }) {
                let variance = baseline.map { pow($0 - m, 2) }.reduce(0, +) / Double(baseline.count)
                let sd = sqrt(variance)
                let diff = latest.value - m
                if sd > 0, abs(diff) / sd >= 2, m != 0, abs(diff) / abs(m) >= def.minRelChange {
                    let pct = diff / abs(m) * 100
                    let arrow = diff > 0 ? "above" : "below"
                    flag = Flag(id: def.key,
                                title: "\(def.title) is unusually \(diff > 0 ? "high" : "low")",
                                detail: "\(def.format(latest.value)) \(def.unit) vs. your usual \(def.format(m)) (\(abs(Int(pct.rounded())))% \(arrow))")
                }
            }

            newCards.append(Card(def: def, points: all, latest: latest,
                                 avg7: mean(days(0, 6)), prev7: mean(days(7, 13)), flag: flag))
        }
        cards = newCards
        flags = newCards.compactMap(\.flag)
    }
}

struct SummaryView: View {
    @StateObject private var model = SummaryModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if let message = model.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                    }
                    if !model.flags.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Worth a look", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline).foregroundStyle(.orange)
                            ForEach(model.flags) { flag in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(flag.title).font(.subheadline.weight(.semibold))
                                    Text(flag.detail).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            Text("Flagged when the latest value is 2+ standard deviations from your last 4 weeks. Not medical advice.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    ForEach(model.cards) { MetricCardView(card: $0) }
                }
                .padding()
            }
            .navigationTitle("Summary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.load() } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(model.loading)
                }
            }
            .refreshable { await model.load() }
            .task { await model.load() }
            .overlay { if model.loading && model.cards.isEmpty { ProgressView() } }
        }
    }
}

struct MetricCardView: View {
    let card: SummaryModel.Card

    private var deltaText: String? {
        guard let a = card.avg7, let p = card.prev7, p != 0 else { return nil }
        let pct = (a - p) / abs(p) * 100
        let arrow = pct >= 0 ? "↑" : "↓"
        return "\(arrow) \(abs(Int(pct.rounded())))% vs. prior week"
    }

    var body: some View {
        let def = card.def
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(def.title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(card.latest.date.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(def.format(card.latest.value)).font(.title.bold())
                Text(def.unit).font(.subheadline).foregroundStyle(.secondary)
            }
            if let avg = card.avg7 {
                Text("7-day avg \(def.format(avg)) \(def.unit)  \(deltaText ?? "")")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Chart(card.points) { p in
                if def.cumulative {
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value(def.title, p.value))
                } else {
                    LineMark(x: .value("Day", p.date), y: .value(def.title, p.value))
                    PointMark(x: .value("Day", p.date), y: .value(def.title, p.value)).symbolSize(12)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .foregroundStyle(card.flag == nil ? Color.accentColor : Color.orange)
            .frame(height: 50)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if card.flag != nil { RoundedRectangle(cornerRadius: 14).stroke(Color.orange, lineWidth: 1.5) }
        }
    }
}
