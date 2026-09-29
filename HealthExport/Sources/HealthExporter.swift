import HealthKit

struct ExportRow {
    let date: String
    let metric: String
    let stat: String
    let value: Double
    let unit: String
}

/// Reads Apple Health and turns it into daily rows: date,metric,stat,value,unit
enum HealthExporter {
    static let store = HKHealthStore()

    private struct Spec {
        let id: HKQuantityTypeIdentifier
        let name: String
        let unit: HKUnit
        let cumulative: Bool   // true = daily sum, false = daily avg/min/max
    }

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private static let vo2 = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    private static let specs: [Spec] = [
        // Activity (daily totals)
        Spec(id: .stepCount, name: "steps", unit: .count(), cumulative: true),
        Spec(id: .distanceWalkingRunning, name: "distance_walking_running", unit: .meter(), cumulative: true),
        Spec(id: .distanceCycling, name: "distance_cycling", unit: .meter(), cumulative: true),
        Spec(id: .flightsClimbed, name: "flights_climbed", unit: .count(), cumulative: true),
        Spec(id: .activeEnergyBurned, name: "active_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .basalEnergyBurned, name: "basal_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .appleExerciseTime, name: "exercise_minutes", unit: .minute(), cumulative: true),
        Spec(id: .appleStandTime, name: "stand_minutes", unit: .minute(), cumulative: true),
        Spec(id: .timeInDaylight, name: "time_in_daylight", unit: .minute(), cumulative: true),
        // Heart & vitals (daily avg/min/max)
        Spec(id: .heartRate, name: "heart_rate", unit: bpm, cumulative: false),
        Spec(id: .restingHeartRate, name: "resting_heart_rate", unit: bpm, cumulative: false),
        Spec(id: .walkingHeartRateAverage, name: "walking_heart_rate_avg", unit: bpm, cumulative: false),
        Spec(id: .heartRateVariabilitySDNN, name: "hrv_sdnn", unit: .secondUnit(with: .milli), cumulative: false),
        Spec(id: .oxygenSaturation, name: "blood_oxygen", unit: .percent(), cumulative: false),
        Spec(id: .respiratoryRate, name: "respiratory_rate", unit: bpm, cumulative: false),
        Spec(id: .vo2Max, name: "vo2_max", unit: vo2, cumulative: false),
        Spec(id: .bloodPressureSystolic, name: "blood_pressure_systolic", unit: .millimeterOfMercury(), cumulative: false),
        Spec(id: .bloodPressureDiastolic, name: "blood_pressure_diastolic", unit: .millimeterOfMercury(), cumulative: false),
        Spec(id: .bloodGlucose, name: "blood_glucose", unit: HKUnit(from: "mg/dL"), cumulative: false),
        Spec(id: .bodyTemperature, name: "body_temperature", unit: .degreeCelsius(), cumulative: false),
        // Body
        Spec(id: .bodyMass, name: "body_mass", unit: .gramUnit(with: .kilo), cumulative: false),
        Spec(id: .bodyFatPercentage, name: "body_fat", unit: .percent(), cumulative: false),
        Spec(id: .leanBodyMass, name: "lean_body_mass", unit: .gramUnit(with: .kilo), cumulative: false),
        Spec(id: .bodyMassIndex, name: "bmi", unit: .count(), cumulative: false),
        Spec(id: .height, name: "height", unit: .meter(), cumulative: false),
        // Mobility
        Spec(id: .walkingSpeed, name: "walking_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .walkingStepLength, name: "walking_step_length", unit: .meter(), cumulative: false),
        Spec(id: .walkingAsymmetryPercentage, name: "walking_asymmetry", unit: .percent(), cumulative: false),
        Spec(id: .appleWalkingSteadiness, name: "walking_steadiness", unit: .percent(), cumulative: false),
        // Nutrition (daily totals)
        Spec(id: .dietaryEnergyConsumed, name: "dietary_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .dietaryProtein, name: "dietary_protein", unit: .gram(), cumulative: true),
        Spec(id: .dietaryCarbohydrates, name: "dietary_carbs", unit: .gram(), cumulative: true),
        Spec(id: .dietaryFatTotal, name: "dietary_fat", unit: .gram(), cumulative: true),
        Spec(id: .dietaryWater, name: "dietary_water", unit: .liter(), cumulative: true),
        Spec(id: .dietaryCaffeine, name: "dietary_caffeine", unit: .gramUnit(with: .milli), cumulative: true),
        // Environment
        Spec(id: .environmentalAudioExposure, name: "environmental_audio", unit: .decibelAWeightedSoundPressureLevel(), cumulative: false),
        Spec(id: .headphoneAudioExposure, name: "headphone_audio", unit: .decibelAWeightedSoundPressureLevel(), cumulative: false),
    ]

    private static var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [sleepType, .workoutType()]
        for spec in specs { types.insert(HKQuantityType(spec.id)) }
        return types
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Wakes the app in the background when new Health data lands (throttled by ExportCoordinator.minInterval).
    static func startBackgroundDelivery() {
        guard isAvailable else { return }
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
                                     HKQuantityType(.heartRateVariabilitySDNN), sleepType, .workoutType()]
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                Task { @MainActor in
                    await ExportCoordinator.shared.run(force: false)
                    completion()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - CSV

    static func buildCSV(daysBack: Int) async throws -> (csv: String, rowCount: Int, range: String) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(max(daysBack, 1) - 1), to: now) ?? now)

        var rows: [ExportRow] = []
        for spec in specs {
            rows += try await dailyStatistics(spec, from: start, to: now)
        }
        rows += try await sleepRows(from: start, to: now)
        rows += try await workoutRows(from: start, to: now)

        rows.sort { ($0.date, $0.metric, $0.stat) < ($1.date, $1.metric, $1.stat) }

        var lines = ["date,metric,stat,value,unit"]
        for r in rows {
            lines.append("\(r.date),\(r.metric),\(r.stat),\(r.value),\(r.unit)")
        }
        let range = "\(dayString(start))..\(dayString(now))"
        return (lines.joined(separator: "\n") + "\n", rows.count, range)
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = Calendar.current.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The Health database can't be read while the phone is locked; surface that, ignore other per-type errors.
    private static func shouldRethrow(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible || error is CancellationError
    }

    private static func dailyStatistics(_ spec: Spec, from start: Date, to end: Date) async throws -> [ExportRow] {
        let type = HKQuantityType(spec.id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let options: HKStatisticsOptions = spec.cumulative ? .cumulativeSum : [.discreteAverage, .discreteMin, .discreteMax]
        let unitLabel = spec.unit.unitString

        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ExportRow], Error>) in
                let query = HKStatisticsCollectionQuery(quantityType: type,
                                                        quantitySamplePredicate: predicate,
                                                        options: options,
                                                        anchorDate: start,
                                                        intervalComponents: DateComponents(day: 1))
                query.initialResultsHandler = { _, results, error in
                    if let error { cont.resume(throwing: error); return }
                    var rows: [ExportRow] = []
                    results?.enumerateStatistics(from: start, to: end) { stats, _ in
                        let day = dayString(stats.startDate)
                        func add(_ stat: String, _ q: HKQuantity?) {
                            guard let q else { return }
                            rows.append(ExportRow(date: day, metric: spec.name, stat: stat,
                                                  value: q.doubleValue(for: spec.unit), unit: unitLabel))
                        }
                        if spec.cumulative {
                            add("sum", stats.sumQuantity())
                        } else {
                            add("avg", stats.averageQuantity())
                            add("min", stats.minimumQuantity())
                            add("max", stats.maximumQuantity())
                        }
                    }
                    cont.resume(returning: rows)
                }
                store.execute(query)
            }
        } catch {
            if shouldRethrow(error) { throw error }
            return []
        }
    }

    private static func samples(of type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    /// Hours asleep per night per stage, attributed to the day the sleep ended.
    private static func sleepRows(from start: Date, to end: Date) async throws -> [ExportRow] {
        let all: [HKSample]
        do { all = try await samples(of: sleepType, from: start, to: end) }
        catch { if shouldRethrow(error) { throw error }; return [] }

        var totals: [String: Double] = [:]   // "day|metric" -> hours
        for case let s as HKCategorySample in all {
            let stage: String
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepCore: stage = "sleep_core"
            case .asleepDeep: stage = "sleep_deep"
            case .asleepREM: stage = "sleep_rem"
            case .asleepUnspecified: stage = "sleep_asleep"
            case .awake: stage = "sleep_awake"
            case .inBed: stage = "sleep_in_bed"
            default: continue
            }
            let key = "\(dayString(s.endDate))|\(stage)"
            totals[key, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        return totals.map { key, hours in
            let parts = key.split(separator: "|")
            return ExportRow(date: String(parts[0]), metric: String(parts[1]), stat: "sum", value: hours, unit: "hr")
        }
    }

    /// Workout count, minutes and active energy per day, per workout type.
    private static func workoutRows(from start: Date, to end: Date) async throws -> [ExportRow] {
        let all: [HKSample]
        do { all = try await samples(of: .workoutType(), from: start, to: end) }
        catch { if shouldRethrow(error) { throw error }; return [] }

        var totals: [String: Double] = [:]   // "day|metric|unit" -> value
        for case let w as HKWorkout in all {
            let day = dayString(w.startDate)
            let name = workoutName(w.workoutActivityType)
            totals["\(day)|workout_\(name)_count|count", default: 0] += 1
            totals["\(day)|workout_\(name)_minutes|min", default: 0] += w.duration / 60
            if let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                totals["\(day)|workout_\(name)_energy|kcal", default: 0] += kcal
            }
        }
        return totals.map { key, value in
            let p = key.split(separator: "|").map(String.init)
            return ExportRow(date: p[0], metric: p[1], stat: "sum", value: value, unit: p[2])
        }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        default: return "other"
        }
    }
}
